import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// `hide Path`: o pacote latlong2 também exporta uma classe chamada `Path`
// (usada para rotas geográficas), que colide com `dart:ui`'s `Path` --
// exatamente o que `CustomPainter.paint` precisa para desenhar o triângulo
// do marcador (`Path()..moveTo(...)..lineTo(...)`). Sem o `hide`, o Dart
// resolve `Path()` para a classe errada e o app não compila.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../data/models/categoria.dart';
import '../data/models/profissional.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/categorias_service.dart';
import '../providers/auth_provider.dart';
import '../providers/localizacao_provider.dart';
import '../providers/profissionais_provider.dart';
import '../widgets/busca_subcategoria_autocomplete.dart';
import 'editar_perfil_screen.dart';
import 'perfil_profissional_screen.dart';

/// Coordenada de fallback -- Teatro Amazonas, Centro de Manaus. Só é usada
/// se a localização do usuário ainda não chegou (evita o mapa nascer no
/// meio do Oceano Atlântico, em 0,0, antes do GPS responder).
const _centroManaus = LatLng(-3.130130, -60.023400);

/// Quantos profissionais no máximo pedir ao backend por busca -- bem acima
/// do padrão da API (20) de propósito. O mapa mostra um "cerco" geográfico
/// (todo mundo dentro do raio escolhido), não uma lista paginada; um teto
/// baixo demais cortaria silenciosamente quem está mais longe dentro do
/// próprio raio à medida que a base de profissionais cresce -- ver
/// comentário completo em profissionais.routes.ts sobre o teto do backend
/// ter sido levantado de 100 para 500 especificamente para esta rota.
const _limiteDeProfissionaisNoMapa = 200;

/// As três formas de ordenar o resultado da busca -- espelha
/// `ordenar_por` em profissionais.routes.ts (`valorApi == null` equivale a
/// não mandar o parâmetro, que já é o padrão "distancia" no backend). São os
/// TRÊS botões fixos da barra principal -- o raio de proximidade (abaixo)
/// só faz sentido escolher "à mão" quando a ordenação é por distância; nos
/// outros dois casos ele continua definindo até onde a busca alcança, só
/// que sem controle visível (ver `_OpcaoRaio` e o `AnimatedCrossFade` no
/// `build`).
enum _OrdenacaoBusca {
  distancia('Mais próximos', null),
  melhorCustoBeneficio('Melhor custo-benefício', 'melhor_custo_beneficio'),
  melhoresAvaliados('Melhores avaliados', 'melhores_avaliados');

  final String rotulo;
  final String? valorApi;

  const _OrdenacaoBusca(this.rotulo, this.valorApi);
}

/// As faixas de raio do sub-filtro que aparece só quando a ordenação é
/// "Mais próximos". `km` é o valor de verdade mandado pro backend
/// (`raio_km`) -- as faixas "Até Xkm" e "Mais que 15km" são só o RÓTULO;
/// tecnicamente toda busca aqui é "raio ≤ X" (o `ST_DWithin` do backend não
/// muda). `maisDe15km` usa o TETO que o backend já aceita hoje
/// (`RAIO_MAXIMO_KM`, padrão 50 -- ver backend/src/env.ts): é o mais longe
/// que a busca consegue ir sem o servidor rejeitar o parâmetro com 400.
enum _OpcaoRaio {
  ate2km(2, 'Até 2km'),
  ate5km(5, 'Até 5km'),
  ate8km(8, 'Até 8km'),
  ate15km(15, 'Até 15km'),
  maisDe15km(50, 'Mais que 15km');

  final double km;
  final String rotulo;

  const _OpcaoRaio(this.km, this.rotulo);
}

class MapaScreen extends StatefulWidget {
  const MapaScreen({super.key});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  final _mapController = MapController();

  // Busca por especialidade -- ver BuscaSubcategoriaAutocomplete. Carregada
  // uma única vez (não a cada busca no mapa, não a cada tecla digitada).
  List<Categoria> _categorias = [];
  Subcategoria? _subcategoriaSelecionada;

  // Filtros avançados -- raio de proximidade e ordenação. Reativos, no
  // mesmo espírito de `_subcategoriaSelecionada` acima: mudar qualquer um
  // dos dois já rebusca automaticamente (ver `_aoMudarRaio`/`_aoMudarOrdenacao`),
  // sem precisar de um botão "aplicar" separado.
  //
  // `_raioSelecionado` NUNCA é resetado ao trocar de ordenação -- só a
  // LINHA de chips que escolhe ele fica visível/invisível (requisito 4:
  // "estado do filtro mantido de forma intuitiva"). Trocar para "Melhores
  // avaliados" e voltar para "Mais próximos" preserva o raio que a pessoa
  // tinha escolhido antes, em vez de voltar pro padrão toda vez.
  _OpcaoRaio _raioSelecionado = _OpcaoRaio.ate5km;
  _OrdenacaoBusca _ordenacaoSelecionada = _OrdenacaoBusca.distancia;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
    // `addPostFrameCallback` porque não dá para chamar `context.read` (que
    // dispara `notifyListeners`) durante o `initState` -- o Flutter ainda
    // está no meio da construção da árvore de widgets nesse momento.
    WidgetsBinding.instance.addPostFrameCallback((_) => _atualizarLocalizacaoEBuscar());
  }

  Future<void> _carregarCategorias() async {
    try {
      final categorias = await CategoriasService.instancia.listarCategorias();
      if (!mounted) return;
      setState(() => _categorias = categorias);
    } on ApiException {
      // Falha silenciosa de propósito: sem a lista, o campo de busca por
      // especialidade simplesmente fica sem opções -- o mapa em si (que já
      // buscou por localização) continua funcionando normalmente.
    }
  }

  Future<void> _atualizarLocalizacaoEBuscar() async {
    final localizacao = context.read<LocalizacaoProvider>();
    await localizacao.obterLocalizacaoAtual();

    if (!mounted) return;

    final posicao = localizacao.posicao;
    if (posicao == null) {
      // `obterLocalizacaoAtual` já guardou a mensagem de erro em
      // `localizacao.erro` -- o `build()` abaixo mostra ela na tela.
      return;
    }

    _mapController.move(LatLng(posicao.latitude, posicao.longitude), 14);
    await _buscar(posicao.latitude, posicao.longitude);
  }

  Future<void> _buscar(double latitude, double longitude) async {
    final provider = context.read<ProfissionaisProvider>();
    await provider.buscarProximos(
      latitude: latitude,
      longitude: longitude,
      raioKm: _raioSelecionado.km,
      subcategoriaId: _subcategoriaSelecionada?.id,
      ordenarPor: _ordenacaoSelecionada.valorApi,
      limite: _limiteDeProfissionaisNoMapa,
    );

    if (!mounted) return;

    // Reenquadra a câmera pelo CÍRCULO do raio escolhido (não mais pelos
    // pontos dos resultados) -- requisito: "sempre que um raio for
    // selecionado ou alterado, a câmera deve se centralizar no usuário e o
    // zoom deve se ajustar para que o círculo fique bem visível e
    // centralizado". Também é a correção do bug relatado antes: "aumentar
    // o raio parece substituir a lista em vez de somar". A causa real não
    // era o backend (ST_DWithin já é cumulativo por natureza -- "distância
    // <= raio", ver o comentário grande em profissionais.repository.ts):
    // era o mapa manter o MESMO zoom fixo (14) de sempre, então pinos que
    // só entram no resultado com um raio maior nasciam fora da área
    // visível na tela -- pareciam ter sumido, mas na verdade nunca tinham
    // chegado a aparecer. Enquadrar pelo círculo (em vez de pelos
    // profissionais retornados) resolve isso de vez: como a busca já é uma
    // "cerca" exata (`distância <= raio`), todo profissional no resultado
    // está, por construção, dentro do círculo -- então caber o círculo
    // inteiro na tela também garante caber todos eles, mesmo quando a
    // lista vem vazia (situação em que não haveria pontos de resultado
    // para basear um enquadramento).
    _ajustarCameraParaRaio(LatLng(latitude, longitude), _raioSelecionado.km * 1000);
  }

  /// Ver comentário em `_buscar` acima. Calcula a "caixa" (bounding box) do
  /// círculo do raio -- centro ± raio convertido de metros para graus -- e
  /// pede pro `fitCamera` enquadrar exatamente essa área. Sempre tem área
  /// > 0 (o menor raio possível é 2km), então, ao contrário da versão
  /// anterior baseada nos resultados, não precisa de um caso especial para
  /// "nenhum profissional encontrado".
  ///
  /// A conversão metros -> graus é uma aproximação (Terra tratada como
  /// esfera perfeita), suficiente para enquadrar câmera -- não é usada em
  /// nenhum cálculo de distância real (isso continua 100% no backend, via
  /// PostGIS/`ST_DWithin`, que é exato).
  void _ajustarCameraParaRaio(LatLng centro, double raioMetros) {
    const metrosPorGrauDeLatitude = 111320.0;
    final grausDeLatitude = raioMetros / metrosPorGrauDeLatitude;
    final grausDeLongitude =
        raioMetros / (metrosPorGrauDeLatitude * math.cos(centro.latitude * math.pi / 180));

    final bounds = LatLngBounds.fromPoints([
      LatLng(centro.latitude + grausDeLatitude, centro.longitude + grausDeLongitude),
      LatLng(centro.latitude - grausDeLatitude, centro.longitude - grausDeLongitude),
    ]);

    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
    );
  }

  /// Chamado quando a pessoa escolhe (ou remove) uma especialidade no
  /// `BuscaSubcategoriaAutocomplete` -- rebusca automaticamente com o novo
  /// filtro, sem precisar de um botão "aplicar" separado.
  void _aoMudarSubcategoria(Subcategoria? subcategoria) {
    setState(() => _subcategoriaSelecionada = subcategoria);
    final posicao = context.read<LocalizacaoProvider>().posicao;
    if (posicao != null) {
      _buscar(posicao.latitude, posicao.longitude);
    }
  }

  /// Mesmo espírito de `_aoMudarSubcategoria` acima -- trocar o raio ou a
  /// ordenação já rebusca na hora, reativo, sem botão "aplicar" separado.
  void _aoMudarRaio(_OpcaoRaio opcao) {
    if (opcao == _raioSelecionado) return;
    setState(() => _raioSelecionado = opcao);
    final posicao = context.read<LocalizacaoProvider>().posicao;
    if (posicao != null) {
      _buscar(posicao.latitude, posicao.longitude);
    }
  }

  void _aoMudarOrdenacao(_OrdenacaoBusca ordenacao) {
    if (ordenacao == _ordenacaoSelecionada) return;
    setState(() => _ordenacaoSelecionada = ordenacao);
    final posicao = context.read<LocalizacaoProvider>().posicao;
    if (posicao != null) {
      _buscar(posicao.latitude, posicao.longitude);
    }
  }

  /// Toca no pino -> vai direto para o perfil público do profissional
  /// (foto, descrição, avaliações e portfólio). O pedido de serviço agora
  /// mora dentro dessa tela, não mais num bottom sheet resumido aqui.
  void _abrirPerfilProfissional(Profissional profissional) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PerfilProfissionalScreen(profissionalId: profissional.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizacao = context.watch<LocalizacaoProvider>();
    final profissionais = context.watch<ProfissionaisProvider>();
    final usuario = context.watch<AuthProvider>().usuario;

    final posicaoAtual = localizacao.posicao;

    // Cor do círculo do raio -- puxa do tema central (ver core/theme/app_theme.dart)
    // em vez de fixar uma cor aqui, pra ficar automaticamente consistente com o
    // resto da identidade visual do app (e acompanhar se o tema mudar no futuro).
    final corRaio = Theme.of(context).colorScheme.primary;

    final marcadores = <Marker>[
      if (posicaoAtual != null)
        Marker(
          point: LatLng(posicaoAtual.latitude, posicaoAtual.longitude),
          width: 24,
          height: 24,
          child: const DecoratedBox(
            decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
            child: Icon(Icons.circle, color: Colors.white, size: 10),
          ),
        ),
      ...profissionais.resultados.map(
        (p) => Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 48,
          height: 56,
          // O `alignment` desloca o marcador pra cima: o ponto (latitude,
          // longitude) precisa cair na PONTA do pino (embaixo), não no
          // centro do círculo da foto -- senão o profissional parece estar
          // um pouco acima de onde ele realmente está.
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => _abrirPerfilProfissional(p),
            child: _MarcadorProfissional(profissional: p),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Olá, ${usuario?.nome ?? ''}'),
        actions: [
          // Só profissional tem perfil público para editar -- cliente não
          // aparece no mapa, então não tem "perfil" nesse sentido.
          if (usuario?.papel == Papel.profissional)
            IconButton(
              tooltip: 'Editar meu perfil',
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditarPerfilScreen()),
                );
              },
            ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: BuscaSubcategoriaAutocomplete(
                    categorias: _categorias,
                    subcategoriaSelecionada: _subcategoriaSelecionada,
                    onSelecionada: _aoMudarSubcategoria,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Atualizar localização e buscar',
                  onPressed: _atualizarLocalizacaoEBuscar,
                  icon: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),

          // Barra principal de ordenação: só os TRÊS botões fixos pedidos
          // (requisito 1) -- "Mais próximos", "Melhor custo-benefício",
          // "Melhores avaliados". Nada de raio aqui; o raio virou um
          // SUB-filtro, que só aparece quando faz sentido (ver abaixo).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ordenacao in _OrdenacaoBusca.values)
                  ChoiceChip(
                    label: Text(ordenacao.rotulo),
                    selected: _ordenacaoSelecionada == ordenacao,
                    onSelected: (_) => _aoMudarOrdenacao(ordenacao),
                  ),
              ],
            ),
          ),

          // Sub-filtro de raio (requisito 2): só existe -- visualmente --
          // quando a ordenação é "Mais próximos". `AnimatedCrossFade` faz a
          // transição pedida no requisito 3 (entra com fade + desliza pra
          // baixo empurrando o mapa, sai do mesmo jeito), sem precisar de
          // `AnimatedContainer`/`AnimatedSize` manual: ele já anima altura E
          // opacidade dos dois lados ao trocar `crossFadeState`.
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
            crossFadeState: _ordenacaoSelecionada == _OrdenacaoBusca.distancia
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.social_distance, size: 18, color: Colors.grey.shade600),
                  for (final opcao in _OpcaoRaio.values)
                    ChoiceChip(
                      label: Text(opcao.rotulo),
                      selected: _raioSelecionado == opcao,
                      onSelected: (_) => _aoMudarRaio(opcao),
                    ),
                ],
              ),
            ),
            // Placeholder de altura zero -- é o que faz o `AnimatedCrossFade`
            // "colapsar" a linha inteira (não só esconder o conteúdo) quando
            // a ordenação não é por distância.
            secondChild: const SizedBox(width: double.infinity, height: 0),
          ),
          const SizedBox(height: 8),

          if (localizacao.erro != null)
            _AvisoFaixa(mensagem: localizacao.erro!, cor: Colors.orange),
          if (profissionais.erro != null)
            _AvisoFaixa(mensagem: profissionais.erro!, cor: Colors.red),
          if (localizacao.carregando || profissionais.carregando)
            const LinearProgressIndicator(minHeight: 2),

          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: posicaoAtual != null
                    ? LatLng(posicaoAtual.latitude, posicaoAtual.longitude)
                    : _centroManaus,
                initialZoom: 13,
              ),
              children: [
                // Camada de "ladrilhos" (as imagens do mapa em si), vindo
                // dos servidores públicos do OpenStreetMap. `userAgentPackageName`
                // é OBRIGATÓRIO pela política de uso do OSM -- sem ele,
                // requests podem ser bloqueadas.
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.servicosmanaus.servicos_manaus_app',
                ),

                // Círculo do raio de busca -- puramente visual (overlay), nunca
                // participa da consulta em si: o filtro de verdade continua sendo
                // o `ST_DWithin` do backend (ver profissionais.repository.ts). Este
                // círculo só representa, na tela, a mesma "cerca" que o backend já
                // está aplicando -- se algum dia os dois divergirem é bug de UI, não
                // de busca.
                //
                // Fica ANTES do `MarkerLayer` de propósito: assim o preenchimento
                // translúcido desenha por baixo dos pinos dos profissionais, nunca
                // por cima escondendo-os.
                //
                // `TweenAnimationBuilder` sozinho, sem `AnimationController`
                // manual: ele detecta a troca de `_raioSelecionado.km` a cada
                // rebuild e anima o valor atual do raio (em metros) suavemente até
                // o novo alvo -- é o que faz o círculo "crescer"/"encolher" ao
                // trocar de 2km pra 15km, em vez de saltar de um tamanho pro outro.
                if (posicaoAtual != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _raioSelecionado.km * 1000),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeInOut,
                    builder: (context, raioAnimadoEmMetros, child) {
                      return CircleLayer(
                        circles: [
                          CircleMarker(
                            point: LatLng(posicaoAtual.latitude, posicaoAtual.longitude),
                            radius: raioAnimadoEmMetros,
                            useRadiusInMeter: true,
                            // Preenchimento suave e translúcido...
                            color: corRaio.withValues(alpha: 0.16),
                            // ...com borda na MESMA cor, mas bem menos transparente --
                            // o contraste de opacidade entre preenchimento e borda é o
                            // que dá a leitura de "borda levemente mais escura
                            // delimitando o raio", sem precisar de uma segunda cor.
                            borderColor: corRaio.withValues(alpha: 0.65),
                            borderStrokeWidth: 2,
                          ),
                        ],
                      );
                    },
                  ),

                MarkerLayer(markers: marcadores),
                // Créditos ao OpenStreetMap -- também exigido pela política
                // de uso deles. Nunca remova isto de um app que usa os
                // ladrilhos gratuitos do OSM.
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Marcador de profissional no mapa: a foto de perfil dele dentro de um
/// círculo com borda branca, com um "raboinho" (triângulo) apontando pro
/// ponto exato da localização -- o mesmo efeito visual de apps como Uber/
/// iFood, só que com a cara de quem está prestando o serviço em vez de um
/// pino genérico.
///
/// Quando o profissional ainda não tem `url_foto_perfil` (não editou o
/// perfil ainda -- ver EditarPerfilScreen) ou a imagem falha ao carregar,
/// cai num ícone de pessoa sobre fundo vermelho, mantendo a mesma "cara" de
/// pino que o app tinha antes.
class _MarcadorProfissional extends StatelessWidget {
  final Profissional profissional;

  const _MarcadorProfissional({required this.profissional});

  @override
  Widget build(BuildContext context) {
    final urlFoto = ApiConfig.urlAbsoluta(profissional.urlFotoPerfil);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2.5)),
            boxShadow: [
              BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
            ],
          ),
          child: ClipOval(
            child: urlFoto != null
                ? Image.network(
                    urlFoto,
                    fit: BoxFit.cover,
                    // Se a URL existir mas a imagem falhar ao carregar (arquivo
                    // apagado, rede lenta etc.), cai no mesmo fallback de quem
                    // nunca teve foto -- nunca mostra um ícone de "imagem quebrada".
                    errorBuilder: (_, __, ___) => _IconeFallback(profissional: profissional),
                  )
                : _IconeFallback(profissional: profissional),
          ),
        ),
        // O "raboinho" do pino -- um triângulo simples apontando para baixo,
        // exatamente sob o centro do círculo, encostado nele (sem espaço).
        CustomPaint(
          size: const Size(12, 7),
          painter: _TrianguloPainter(),
        ),
      ],
    );
  }
}

class _IconeFallback extends StatelessWidget {
  final Profissional profissional;

  const _IconeFallback({required this.profissional});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.redAccent,
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.white, size: 26),
    );
  }
}

/// Desenha o triângulo do "raboinho" do pino. `moveTo`/`lineTo` formam um
/// triângulo isósceles: base no topo (largura toda), ponta embaixo no meio
/// -- é o que dá a impressão de "pino apontando para o chão".
class _TrianguloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()..color = Colors.white;
    final caminho = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(caminho, tinta);
  }

  @override
  bool shouldRepaint(covariant _TrianguloPainter oldDelegate) => false;
}

class _AvisoFaixa extends StatelessWidget {
  final String mensagem;
  final Color cor;

  const _AvisoFaixa({required this.mensagem, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: cor.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(mensagem, style: TextStyle(color: cor.withValues(alpha: 1))),
    );
  }
}
