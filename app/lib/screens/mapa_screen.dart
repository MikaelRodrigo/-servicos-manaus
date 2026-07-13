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

/// Raios de busca oferecidos no filtro de proximidade -- em km, sempre
/// nessa ordem (menor pro maior). Lista fechada de propósito (o pedido foi
/// especificamente "1km, 2km, 3km, 4km ou 5km", não um slider contínuo).
const _raiosDisponiveisKm = [1.0, 2.0, 3.0, 4.0, 5.0];

/// As três formas de ordenar o resultado da busca -- espelha
/// `ordenar_por` em profissionais.routes.ts (`valorApi == null` equivale a
/// não mandar o parâmetro, que já é o padrão "distancia" no backend).
enum _OrdenacaoBusca {
  distancia('Mais próximos', null),
  melhorCustoBeneficio('Melhor custo-benefício', 'melhor_custo_beneficio'),
  melhoresAvaliados('Melhores avaliados', 'melhores_avaliados');

  final String rotulo;
  final String? valorApi;

  const _OrdenacaoBusca(this.rotulo, this.valorApi);
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
  double _raioKmSelecionado = 5;
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
    await context.read<ProfissionaisProvider>().buscarProximos(
          latitude: latitude,
          longitude: longitude,
          raioKm: _raioKmSelecionado,
          subcategoriaId: _subcategoriaSelecionada?.id,
          ordenarPor: _ordenacaoSelecionada.valorApi,
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
  /// ordenação já rebusca na hora, reativo, sem botão "aplicar" separado
  /// (requisito 3 do filtro avançado).
  void _aoMudarRaio(double raioKm) {
    if (raioKm == _raioKmSelecionado) return;
    setState(() => _raioKmSelecionado = raioKm);
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

          // Filtros avançados: raio de proximidade + ordenação. Chips logo
          // abaixo da barra de busca principal (requisito 3), sempre
          // visíveis -- diferente da especialidade (que só filtra quando a
          // pessoa escolhe uma), aqui SEMPRE existe um raio e uma ordenação
          // selecionados (com valores padrão: 5km, "Mais próximos").
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.social_distance, size: 18, color: Colors.grey.shade600),
                for (final km in _raiosDisponiveisKm)
                  ChoiceChip(
                    label: Text('${km.toStringAsFixed(0)} km'),
                    selected: _raioKmSelecionado == km,
                    onSelected: (_) => _aoMudarRaio(km),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.sort, size: 18, color: Colors.grey.shade600),
                for (final ordenacao in _OrdenacaoBusca.values)
                  ChoiceChip(
                    label: Text(ordenacao.rotulo),
                    selected: _ordenacaoSelecionada == ordenacao,
                    onSelected: (_) => _aoMudarOrdenacao(ordenacao),
                  ),
              ],
            ),
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
