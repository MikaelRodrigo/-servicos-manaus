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
import '../core/theme/app_theme.dart';
import '../data/models/categoria.dart';
import '../data/models/profissional.dart';
import '../data/services/api_client.dart';
import '../data/services/categorias_service.dart';
import '../providers/auth_provider.dart';
import '../providers/localizacao_provider.dart';
import '../providers/profissionais_provider.dart';
import '../widgets/avatar_iniciais.dart';
import '../widgets/busca_subcategoria_autocomplete.dart';
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

/// Distância mínima entre qualquer conteúdo e a borda da tela -- usada em
/// TODOS os paddings horizontais desta tela (cabeçalho, cartão do mapa,
/// busca, filtros, grade de categorias). Um valor único, em vez de cada
/// trecho inventar o seu, garante que a "respiração" nas bordas seja
/// sempre a mesma -- e que ajustar esse espaçamento no futuro seja uma
/// mudança de UMA linha, não uma caça por todo o arquivo.
const _paddingHorizontal = 24.0;

/// Saudação por horário do dia -- troca o "Olá, Nome" cru de antes por algo
/// que reage ao momento em que a pessoa está usando o app, mesmo detalhe
/// pequeno que apps de referência (Uber, iFood) já usam no topo da tela
/// inicial. Puramente cosmético -- nunca influencia busca nem dado nenhum.
String _saudacaoPorHorario() {
  final hora = DateTime.now().hour;
  if (hora < 12) return 'Bom dia';
  if (hora < 18) return 'Boa tarde';
  return 'Boa noite';
}

/// Ícone representativo de cada categoria, escolhido por palavra-chave no
/// nome -- NUNCA por foto (o backend não tem imagem nenhuma de categoria,
/// ver `categoria.dart`; inventar fotos de banco de imagens pareceria dado
/// real sem ser). É puramente decorativo/de navegação, com um fallback
/// neutro (`Icons.apps_rounded`) para qualquer categoria futura que não
/// bata em nenhuma palavra-chave conhecida.
IconData _iconeParaCategoria(String nome) {
  final n = nome.toLowerCase();
  if (n.contains('manuten') || n.contains('reform')) return Icons.home_repair_service_rounded;
  if (n.contains('log') || n.contains('transport')) return Icons.local_shipping_rounded;
  if (n.contains('beleza') || n.contains('bem-estar') || n.contains('bem estar')) {
    return Icons.spa_rounded;
  }
  if (n.contains('tecnolog') || n.contains('digital')) return Icons.computer_rounded;
  if (n.contains('educa') || n.contains('consultoria')) return Icons.school_rounded;
  if (n.contains('aliment') || n.contains('evento')) return Icons.restaurant_rounded;
  if (n.contains('pet') || n.contains('animal')) return Icons.pets_rounded;
  if (n.contains('limpeza')) return Icons.cleaning_services_rounded;
  if (n.contains('saude') || n.contains('saúde')) return Icons.health_and_safety_rounded;
  if (n.contains('jardim')) return Icons.yard_rounded;
  return Icons.apps_rounded;
}

/// Palavra-chave temática de uma categoria, pela MESMA lógica de
/// correspondência de `_iconeParaCategoria` -- usada por
/// `_urlImagemParaSubcategoria` pra montar a URL da foto de fundo de cada
/// cartão de subcategoria (ver `_CartaoSubcategoria`).
String _palavraChaveParaCategoria(String nome) {
  final n = nome.toLowerCase();
  if (n.contains('manuten') || n.contains('reform')) return 'repair';
  if (n.contains('log') || n.contains('transport')) return 'delivery';
  if (n.contains('beleza') || n.contains('bem-estar') || n.contains('bem estar')) return 'beauty';
  if (n.contains('tecnolog') || n.contains('digital')) return 'technology';
  if (n.contains('educa') || n.contains('consultoria')) return 'education';
  if (n.contains('aliment') || n.contains('evento')) return 'food';
  if (n.contains('pet') || n.contains('animal')) return 'pets';
  if (n.contains('limpeza')) return 'cleaning';
  if (n.contains('saude') || n.contains('saúde')) return 'healthcare';
  if (n.contains('jardim')) return 'garden';
  return 'business';
}

/// Foto real ilustrando uma subcategoria -- fundo dos cartões da lista
/// horizontal de cada seção (ver `_CartaoSubcategoria`). Usa a palavra-chave
/// TEMÁTICA da categoria-mãe (subcategorias não têm uma lógica própria de
/// correspondência -- "Pedreiro" e "Pintor", por exemplo, cairiam nas
/// mesmas fotos genéricas de "reparo" de qualquer forma), mas com o
/// `lock=` calculado a partir da combinação categoria+subcategoria, pra
/// cada cartão dentro da mesma categoria mostrar uma foto DIFERENTE (ainda
/// dentro do mesmo tema) -- em vez de repetir a mesma imagem em todos os
/// cartões da fileira.
///
/// PLACEHOLDER DE TERCEIROS -- ATENÇÃO ANTES DE PRODUÇÃO: o backend não
/// tem (ainda) um campo de imagem por subcategoria (ver `Subcategoria` em
/// categoria.dart), então esta função busca fotos temáticas prontas no
/// LoremFlickr (serviço gratuito, sem chave de API, que devolve fotos
/// reais do Flickr por palavra-chave -- ver https://loremflickr.com).
/// Isso resolve o pedido de "fotos reais de alta qualidade" sem inventar
/// nenhum dado sobre profissionais/avaliações/contagens (que continuam
/// 100% reais, vindos do backend) -- mas são fotos de TERCEIROS, sem
/// licença clara confirmada para uso comercial. Antes de lançar o app de
/// verdade, troque por fotos próprias (ou com licença comercial/CC
/// confirmada), idealmente vindas do backend (um campo de imagem por
/// subcategoria, com upload pelo painel administrativo).
String _urlImagemParaSubcategoria(String nomeCategoria, String nomeSubcategoria) {
  final palavraChave = _palavraChaveParaCategoria(nomeCategoria);
  final semente = '$nomeCategoria|$nomeSubcategoria'.hashCode.abs();
  return 'https://loremflickr.com/400/300/$palavraChave?lock=$semente';
}

/// Dimensões dos cartões de subcategoria na lista horizontal de cada seção
/// -- largura fixa (todo item de um `ListView` horizontal precisa de uma),
/// altura calculada pra ficar bem PRÓXIMA de um quadrado (pedido
/// explícito: "diminua menos verticalmente"), não mais um retângulo bem
/// mais alto do que largo como a versão anterior em grade.
const _larguraCartaoSubcategoria = 132.0;
const _alturaCartaoSubcategoria = 142.0;

/// As três formas de ordenar o resultado da busca -- espelha
/// `ordenar_por` em profissionais.routes.ts (`valorApi == null` equivale a
/// não mandar o parâmetro, que já é o padrão "distancia" no backend). São os
/// TRÊS botões fixos da barra principal -- o raio de proximidade (abaixo) só
/// existe (visual e FUNCIONALMENTE) quando a ordenação é "Mais próximos"
/// (`distancia`); trocar para qualquer um dos outros dois LIMPA o raio
/// escolhido automaticamente (ver `_aoMudarOrdenacao`) -- nos outros dois
/// modos a busca nunca fica restrita por um raio "esquecido" em segundo
/// plano (ver `_OpcaoRaio` e o `AnimatedCrossFade` no `build`).
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
  // NULLABLE de propósito: cada chip de raio funciona como um TOGGLE --
  // tocar num chip já ativo desliga o filtro (volta pra `null`), em vez de
  // ficar sempre preso a uma das cinco opções. `null` = "nenhum raio
  // escolhido à mão" -- ver o comentário grande em `_buscar` sobre o que
  // isso significa de verdade pra busca (mostrar TODO MUNDO da categoria,
  // sem "cerca" nenhuma vindo do botão "Mais próximos" sozinho).
  //
  // AGORA É RESETADO ao trocar de ordenação (`_aoMudarOrdenacao`) --
  // diferente de uma versão anterior deste código, que preservava o raio
  // escolhido "em segundo plano" ao trocar pra "Melhor custo-benefício"/
  // "Melhores avaliados". Isso causava exatamente o bug relatado: um raio
  // curto escolhido em "Mais próximos" continuava filtrando a busca
  // silenciosamente depois de trocar de aba, sem nenhum chip marcado pra
  // indicar isso. Cada troca de modo agora começa com o raio limpo.
  _OpcaoRaio? _raioSelecionado;

  // Guarda o ÚLTIMO raio que teve um círculo desenhado, mesmo depois de
  // `_raioSelecionado` voltar a `null` (toggle desligado). Existe só pra
  // animação do círculo: sem isso, desligar o toggle faria o raio do
  // `TweenAnimationBuilder` "saltar" pra 0 enquanto ele desaparece (fade +
  // encolhimento ao mesmo tempo) -- em vez disso, o círculo desaparece do
  // MESMO tamanho que tinha (só a opacidade anima), que é o efeito "elegante,
  // sem pular na tela" pedido. Só é lido dentro do `AnimatedOpacity` no
  // `build` -- nunca influencia a busca em si.
  _OpcaoRaio? _ultimoRaioComCirculo;

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
      // especialidade e a grade de categorias simplesmente ficam vazios --
      // o mapa em si (que já buscou por localização) continua funcionando
      // normalmente.
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
      // BUG CORRIGIDO NESTA SESSÃO: antes, `_raioSelecionado?.km` virava
      // `null` quando nenhum raio estava ativo, e o serviço OMITIA
      // `raio_km` da request -- o que parecia certo, mas o backend tem um
      // padrão PRÓPRIO pra esse parâmetro quando ele não vem
      // (`numeroOpcional(req.query.raio_km, 'raio_km', 5)` em
      // profissionais.routes.ts): 5km. Ou seja, "nenhum raio escolhido" na
      // prática virava "raio de 5km", uma cerca curta e INVISÍVEL --
      // exatamente o bug relatado ("Mais próximos" escondendo profissionais
      // além de 8km mesmo sem nenhum raio selecionado).
      //
      // O botão "Mais próximos" sozinho NÃO deve aplicar geofencing nenhum
      // -- só o clique explícito num chip de distância deve. Como o backend
      // não tem um "sem limite" de verdade (todo `raio_km` é validado entre
      // 0.1 e `RAIO_MAXIMO_KM`, sempre um número finito), a forma honesta de
      // pedir "sem restrição visível" é mandar o próprio TETO que o backend
      // já aceita -- o mesmo valor que alimenta o chip "Mais que 15km"
      // (`_OpcaoRaio.maisDe15km.km`, 50km) -- em vez de deixar a omissão
      // cair num padrão bem mais curto sem ninguém pedir.
      raioKm: _raioSelecionado?.km ?? _OpcaoRaio.maisDe15km.km,
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
    //
    // Com o raio virando toggle (pode ser `null`), sem círculo pra
    // enquadrar a câmera só centraliza no usuário com o zoom "de
    // navegação" padrão (14) -- o mesmo usado antes de qualquer raio
    // existir no app, e o mesmo que `_atualizarLocalizacaoEBuscar` usa na
    // primeira localização.
    final centro = LatLng(latitude, longitude);
    if (_raioSelecionado != null) {
      _ajustarCameraParaRaio(centro, _raioSelecionado!.km * 1000);
    } else {
      _mapController.move(centro, 14);
    }
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

  /// Chamado quando a pessoa escolhe (ou remove) uma especialidade -- seja
  /// pelo campo de busca (`BuscaSubcategoriaAutocomplete`) seja por um
  /// cartão da lista horizontal de especialidades (ver
  /// `_CartaoSubcategoria`) -- rebusca automaticamente com o novo filtro,
  /// sem precisar de um botão "aplicar" separado.
  void _aoMudarSubcategoria(Subcategoria? subcategoria) {
    setState(() => _subcategoriaSelecionada = subcategoria);
    final posicao = context.read<LocalizacaoProvider>().posicao;
    if (posicao != null) {
      _buscar(posicao.latitude, posicao.longitude);
    }
  }

  /// Mesmo espírito de `_aoMudarSubcategoria` acima -- trocar o raio ou a
  /// ordenação já rebusca na hora, reativo, sem botão "aplicar" separado.
  ///
  /// TOGGLE: tocar num chip que já está ativo desliga o filtro (`null`) em
  /// vez de não fazer nada -- só um raio ativo por vez, ou nenhum. Isso é
  /// tudo que `_aoMudarRaio` precisa saber sobre "desligar": o resto (sumir
  /// o círculo do mapa, desmarcar o chip, a busca cair no padrão do
  /// backend) já é consequência automática de `_raioSelecionado` virar
  /// `null` -- não tem um caminho de código separado pra "remover" nada.
  void _aoMudarRaio(_OpcaoRaio opcao) {
    final desativando = opcao == _raioSelecionado;
    setState(() {
      _raioSelecionado = desativando ? null : opcao;
      // Só atualiza a "memória" do círculo quando ESTÁ ativando um raio --
      // ver comentário completo no campo `_ultimoRaioComCirculo`. Ao
      // desativar, deixa o valor antigo aí de propósito, pra o círculo
      // desaparecer do mesmo tamanho (só perdendo opacidade) em vez de
      // encolher e desaparecer ao mesmo tempo.
      if (!desativando) {
        _ultimoRaioComCirculo = opcao;
      }
    });
    final posicao = context.read<LocalizacaoProvider>().posicao;
    if (posicao != null) {
      _buscar(posicao.latitude, posicao.longitude);
    }
  }

  /// Trocar de modo de ordenação agora LIMPA o raio automaticamente
  /// (requisito: "se o usuário clicar em 'Mais próximos' e depois decidir
  /// mudar para 'Melhor custo-benefício', o filtro de distância deve ser
  /// limpo, garantindo que nenhum raio indesejado fique aplicado em segundo
  /// plano"). Isso vale nos dois sentidos -- sair de "Mais próximos" limpa,
  /// e voltar pra "Mais próximos" também começa limpo (sem raio
  /// pré-aplicado, só a linha de chips reaparecendo vazia). O círculo no
  /// mapa e a busca em si já refletem isso sozinhos assim que
  /// `_raioSelecionado` vira `null` -- não tem lógica extra pra "esconder"
  /// nada além disso.
  void _aoMudarOrdenacao(_OrdenacaoBusca ordenacao) {
    if (ordenacao == _ordenacaoSelecionada) return;
    setState(() {
      _ordenacaoSelecionada = ordenacao;
      _raioSelecionado = null;
    });
    final posicao = context.read<LocalizacaoProvider>().posicao;
    if (posicao != null) {
      _buscar(posicao.latitude, posicao.longitude);
    }
  }

  /// Chamado pelo botão "Limpar filtros" do cartão de "nenhum resultado"
  /// (ver `_CartaoSemResultados`) -- volta aos três filtros para o estado
  /// neutro (sem especialidade, sem raio, ordenação por distância) e
  /// rebusca. Existe porque a causa mais comum de "nenhum profissional
  /// encontrado" é justamente um filtro combinado demais restritivo (raio
  /// curto + especialidade rara), não a ausência real de profissionais na
  /// base.
  void _limparFiltros() {
    setState(() {
      _subcategoriaSelecionada = null;
      _raioSelecionado = null;
      _ordenacaoSelecionada = _OrdenacaoBusca.distancia;
    });
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
    final pontoUsuario =
        posicaoAtual != null ? LatLng(posicaoAtual.latitude, posicaoAtual.longitude) : null;

    // Cor do círculo do raio -- puxa do tema central (ver core/theme/app_theme.dart)
    // em vez de fixar uma cor aqui, pra ficar automaticamente consistente com o
    // resto da identidade visual do app (e acompanhar se o tema mudar no futuro).
    final corRaio = Theme.of(context).colorScheme.primary;

    final marcadores = <Marker>[
      if (pontoUsuario != null)
        Marker(
          point: pontoUsuario,
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

    final nomeUsuario = usuario?.nome.trim() ?? '';
    final urlFotoUsuario = ApiConfig.urlAbsoluta(usuario?.urlFotoPerfil);

    final temFiltrosAtivos = _subcategoriaSelecionada != null ||
        _raioSelecionado != null ||
        _ordenacaoSelecionada != _OrdenacaoBusca.distancia;

    return Scaffold(
      backgroundColor: AppColors.fundo,
      // `Column` (não mais um único `ListView`) de propósito: o pedido foi
      // travar o cabeçalho + mapa + filtros no lugar, deixando só a grade
      // de especialidades, mais abaixo, rolar. A parte de cima (até os
      // chips de raio) fica FORA de qualquer `Scrollable` -- só o `Expanded`
      // no fim da coluna rola, e é ele quem carrega o resto.
      body: Column(
        children: [
          _construirCabecalhoComMapa(
            context,
            nomeUsuario: nomeUsuario,
            urlFotoUsuario: urlFotoUsuario,
            pontoUsuario: pontoUsuario,
            marcadores: marcadores,
            corRaio: corRaio,
          ),
          // Compensa a altura que o cartão do mapa "protrai" para fora do
          // cabeçalho curvo (ver `_construirCabecalhoComMapa` acima) -- sem
          // isso, o próximo conteúdo nasceria por baixo do cartão. Recalculado
          // depois de aumentar `alturaCartaoMapa` para 220 (mapa mais
          // "quadrado"): protrusão = topoDoCartao(92) + altura(220) -
          // cabeçalho(128) = 184.
          const SizedBox(height: 182),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              _paddingHorizontal,
              0,
              _paddingHorizontal,
              8,
            ),
            child: _construirBarraDeBusca(context),
          ),

          // Contagem viva do resultado -- some durante o carregamento/erro
          // (a barra de progresso e a faixa de erro abaixo já cobrem esses
          // casos) e some também quando a busca ainda não aconteceu.
          // Reage a cada busca nova, sem precisar tocar em mais nada.
          if (!profissionais.carregando &&
              profissionais.erro == null &&
              profissionais.resultados.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _paddingHorizontal,
                0,
                _paddingHorizontal,
                8,
              ),
              child: Text(
                '${profissionais.resultados.length} profissional(is) encontrado(s) por perto',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          // Barra principal de ordenação: só os TRÊS botões fixos pedidos
          // (requisito 1) -- "Mais próximos", "Melhor custo-benefício",
          // "Melhores avaliados". Nada de raio aqui; o raio virou um
          // SUB-filtro, que só aparece quando faz sentido (ver abaixo).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _paddingHorizontal),
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
          // baixo empurrando o resto, sai do mesmo jeito), sem precisar de
          // `AnimatedContainer`/`AnimatedSize` manual: ele já anima altura E
          // opacidade dos dois lados ao trocar `crossFadeState`.
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
            crossFadeState: _ordenacaoSelecionada == _OrdenacaoBusca.distancia
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                _paddingHorizontal,
                8,
                _paddingHorizontal,
                0,
              ),
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

          // A PARTIR DAQUI a tela rola -- só a grade de especialidades (e o
          // aviso de "nenhum resultado", que pertence ao mesmo bloco de
          // baixo por ficar logo depois dela na ordem de leitura). Tudo
          // acima desta linha (cabeçalho, mapa, busca, ordenação e raio)
          // fica fixo na tela, sem rolar junto.
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Aviso de "nenhum resultado" -- antes vivia como um cartão
                // flutuante sobre o mapa; agora entra no topo da área que
                // rola, logo abaixo dos filtros fixos.
                if (!localizacao.carregando &&
                    !profissionais.carregando &&
                    localizacao.erro == null &&
                    profissionais.erro == null &&
                    profissionais.jaBuscou &&
                    profissionais.resultados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _paddingHorizontal,
                      12,
                      _paddingHorizontal,
                      0,
                    ),
                    child: _CartaoSemResultados(
                      temFiltrosAtivos: temFiltrosAtivos,
                      aoLimparFiltros: _limparFiltros,
                    ),
                  ),

                const SizedBox(height: 24),

                // Grade de categorias -- segunda forma de encontrar um
                // profissional, além do campo de busca: navegar visualmente
                // por especialidade em vez de já saber o termo exato para
                // digitar. Cada cartão mostra a contagem REAL de
                // profissionais (soma das subcategorias, já calculada pelo
                // backend em `GET /categorias`) -- nunca uma nota ou foto
                // inventada.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _paddingHorizontal),
                  child: Text(
                    'Explore por especialidade',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _paddingHorizontal),
                  child: Text(
                    'Arraste para o lado dentro de cada categoria pra ver as especialidades',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 14),
                if (_categorias.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  // Lista de listas: uma seção por categoria (título em
                  // negrito + fileira horizontal das subcategorias dela),
                  // empilhadas verticalmente -- rola pra BAIXO entre
                  // categorias, rola pro LADO dentro de cada uma pra ver
                  // as especialidades. Construída aqui como um `for` dentro
                  // do `ListView` (vertical) que já envolve toda esta área
                  // rolável -- funcionalmente equivalente a um
                  // `ListView.builder` vertical dedicado (mesmo resultado:
                  // uma seção por item da lista de categorias), só que sem
                  // precisar de um SEGUNDO `Scrollable` aninhado dentro do
                  // primeiro (o que exigiria truques extras de scroll pra
                  // funcionar direito). A lista horizontal DE VERDADE usa
                  // `ListView.builder` (ver `_construirSecaoCategoria`).
                  for (final categoria in _categorias)
                    _construirSecaoCategoria(context, categoria),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Uma seção da lista de listas: título em negrito da categoria + uma
  /// fileira horizontal (`ListView.builder`, `scrollDirection:
  /// Axis.horizontal`) com um `_CartaoSubcategoria` por especialidade
  /// dela. Tocar num cartão já filtra o mapa E recentraliza a câmera (ver
  /// `_aoMudarSubcategoria`) -- sem passo intermediário nenhum.
  Widget _construirSecaoCategoria(BuildContext context, Categoria categoria) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _paddingHorizontal),
            child: Text(
              categoria.nome,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          if (categoria.subcategorias.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _paddingHorizontal),
              child: Text(
                'Nenhuma especialidade cadastrada nesta categoria ainda.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            SizedBox(
              height: _alturaCartaoSubcategoria,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: _paddingHorizontal),
                itemCount: categoria.subcategorias.length,
                itemBuilder: (context, indice) {
                  final subcategoria = categoria.subcategorias[indice];
                  final ultimo = indice == categoria.subcategorias.length - 1;
                  return Padding(
                    padding: EdgeInsets.only(right: ultimo ? 0 : 12),
                    child: _CartaoSubcategoria(
                      categoria: categoria,
                      subcategoria: subcategoria,
                      onTap: () => _aoMudarSubcategoria(subcategoria),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Cabeçalho curvo com identidade + saudação, com o cartão do mapa
  /// "flutuando" sobre a borda inferior dele -- o layout pedido a partir de
  /// uma referência visual, adaptado à paleta e aos dados reais do app
  /// (`AppColors.destaque`, a mesma cor de destaque usada em todo o resto,
  /// nada de cor nova inventada só para esta tela).
  ///
  /// `Stack` com `clipBehavior: Clip.none` de propósito: é o que permite o
  /// cartão do mapa (um `Positioned`) desenhar PARA FORA da altura do
  /// `Container` de fundo, criando o efeito de sobreposição -- o
  /// `SizedBox` logo depois desta chamada, no `build`, compensa esse
  /// espaço "extra" para o próximo conteúdo não nascer por baixo do cartão.
  Widget _construirCabecalhoComMapa(
    BuildContext context, {
    required String nomeUsuario,
    required String? urlFotoUsuario,
    required LatLng? pontoUsuario,
    required List<Marker> marcadores,
    required Color corRaio,
  }) {
    const alturaCabecalho = 128.0;
    // Mapa mais "quadrado" (pedido explícito) -- 172 -> 220, ocupando mais
    // espaço vertical em vez do formato baixo/alongado de antes.
    const alturaCartaoMapa = 220.0;
    const sobreposicao = 36.0;
    const topoDoCartao = alturaCabecalho - sobreposicao;

    // Versão mais escura da cor de destaque, só para o cabeçalho -- pedido
    // explícito de novo ("escurecer o azul do topo"; a primeira tentativa,
    // 30% de preto, não foi escura o bastante). `AppColors.destaque` em si
    // NÃO muda (ela é usada em botões/chips/ícones em todo o resto do
    // app); em vez de escurecer a paleta inteira, misturamos 45% de preto
    // só aqui, com `Color.lerp` -- mantém a MESMA cor-base (nada de um tom
    // novo inventado, como um azul genérico do Material) só que bem mais
    // profunda, quase um "petróleo".
    final corCabecalho = Color.lerp(AppColors.destaque, Colors.black, 0.45)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: alturaCabecalho,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [corCabecalho, corCabecalho.withValues(alpha: 0.85)],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            _paddingHorizontal,
            MediaQuery.of(context).padding.top + 14,
            16,
            0,
          ),
          child: Row(
            children: [
              ClipOval(
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: urlFotoUsuario != null
                      ? Image.network(
                          urlFotoUsuario,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              AvatarIniciais(nome: nomeUsuario, tamanho: 42),
                        )
                      : AvatarIniciais(nome: nomeUsuario, tamanho: 42),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _saudacaoPorHorario(),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      nomeUsuario.isNotEmpty ? nomeUsuario : 'Olá!',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Atualizar localização e buscar',
                icon: const Icon(Icons.my_location, color: Colors.white),
                onPressed: _atualizarLocalizacaoEBuscar,
              ),
              IconButton(
                tooltip: 'Sair',
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () => context.read<AuthProvider>().logout(),
              ),
            ],
          ),
        ),
        Positioned(
          left: _paddingHorizontal,
          right: _paddingHorizontal,
          top: topoDoCartao,
          child: Container(
            height: alturaCartaoMapa,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: pontoUsuario ?? _centroManaus,
                  initialZoom: 12.5,
                  // Explícito de propósito (mesmo sendo o padrão do
                  // pacote): garante arrastar/pinçar/zoom por toque
                  // sempre habilitados. O cartão do mapa agora vive
                  // DIRETO na `Column` fixa do topo (não mais dentro de
                  // um `ListView`/`Scrollable`) -- então não há mais um
                  // scroll de página "roubando" o gesto de toque do mapa;
                  // essa era a causa raiz do mapa parecer "travado".
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  // Camada de "ladrilhos" (as imagens do mapa em si), vindo
                  // dos servidores públicos do OpenStreetMap.
                  // `userAgentPackageName` é OBRIGATÓRIO pela política de
                  // uso do OSM -- sem ele, requests podem ser bloqueadas.
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.servicosmanaus.servicos_manaus_app',
                  ),

                  // Círculo do raio de busca -- puramente visual (overlay),
                  // nunca participa da consulta em si: o filtro de verdade
                  // continua sendo o `ST_DWithin` do backend (ver
                  // profissionais.repository.ts).
                  if (pontoUsuario != null && _ultimoRaioComCirculo != null)
                    AnimatedOpacity(
                      opacity: _raioSelecionado != null ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: _ultimoRaioComCirculo!.km * 1000),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeInOut,
                        builder: (context, raioAnimadoEmMetros, child) {
                          return CircleLayer(
                            circles: [
                              CircleMarker(
                                point: pontoUsuario,
                                radius: raioAnimadoEmMetros,
                                useRadiusInMeter: true,
                                color: corRaio.withValues(alpha: 0.10),
                                borderColor: corRaio.withValues(alpha: 0.3),
                                borderStrokeWidth: 1.2,
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                  MarkerLayer(markers: marcadores),
                  // Créditos ao OpenStreetMap -- também exigido pela
                  // política de uso deles. Nunca remova isto de um app que
                  // usa os ladrilhos gratuitos do OSM.
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors', onTap: () {}),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Campo de busca dentro de um "pill" branco flutuante -- o mesmo
  /// `BuscaSubcategoriaAutocomplete` de sempre, só que embrulhado num
  /// `Theme` local que zera a decoração PADRÃO de campo do app (fundo
  /// cinza + borda, ver `app_theme.dart`) só aqui, porque o fundo já vem do
  /// `Container` branco por fora -- sem isso, ficaria "cinza dentro de
  /// branco", um campo dentro do outro.
  Widget _construirBarraDeBusca(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          ),
        ),
        child: BuscaSubcategoriaAutocomplete(
          categorias: _categorias,
          subcategoriaSelecionada: _subcategoriaSelecionada,
          onSelecionada: _aoMudarSubcategoria,
        ),
      ),
    );
  }
}

/// Um cartão de subcategoria na fileira horizontal "Explore por
/// especialidade" -- foto real de fundo (ver `_urlImagemParaSubcategoria`;
/// PLACEHOLDER de terceiros, ver comentário completo lá) com um degradê
/// escuro por baixo pra manter o texto branco legível em qualquer foto,
/// clara ou escura. Nome + contagem REAL de profissionais
/// (`totalProfissionais`, já calculada pelo backend). Tocar já filtra o
/// mapa por essa especialidade (ver `_aoMudarSubcategoria`).
///
/// Largura fixa (`_larguraCartaoSubcategoria`), altura próxima da largura
/// (quase quadrado, correção explícita do usuário; ver
/// `_alturaCartaoSubcategoria`). Se a foto falhar ao carregar (sem
/// internet, serviço fora do ar etc.), cai no MESMO visual de ícone que a
/// tela usava antes -- nunca mostra um quadrado quebrado/cinza no lugar
/// dela.
class _CartaoSubcategoria extends StatelessWidget {
  final Categoria categoria;
  final Subcategoria subcategoria;
  final VoidCallback onTap;

  const _CartaoSubcategoria({
    required this.categoria,
    required this.subcategoria,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _larguraCartaoSubcategoria,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                _urlImagemParaSubcategoria(categoria.nome, subcategoria.nome),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progresso) {
                  if (progresso == null) return child;
                  return const ColoredBox(color: AppColors.superficieSecundaria);
                },
                errorBuilder: (_, __, ___) => _fundoIconeFallback(),
              ),
              // Degradê -- só a metade de baixo escurece, o suficiente pra
              // nome + contagem (sempre brancos) ficarem legíveis sem
              // esconder demais a foto.
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subcategoria.nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${subcategoria.totalProfissionais} prof.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mesmo visual de "antes" (ícone sobre um fundo claro) -- usado só como
  /// FALLBACK, quando a foto real falha ao carregar.
  Widget _fundoIconeFallback() {
    return ColoredBox(
      color: AppColors.destaque.withValues(alpha: 0.12),
      child: Center(
        child: Icon(_iconeParaCategoria(categoria.nome), color: AppColors.destaque, size: 32),
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

/// Aviso mostrado quando uma busca já terminou (sem erro, sem estar
/// carregando) e voltou vazia -- ver o `if` que envolve este widget, no
/// `build` de `_MapaScreenState`. Sem isso, o resultado simplesmente
/// desaparecia sem nenhuma explicação -- parecia bug ("sumiu tudo?") em vez
/// de um resultado real de busca.
///
/// `temFiltrosAtivos` decide a MENSAGEM e se o botão "Limpar filtros"
/// aparece: a causa mais comum de zero resultados é um filtro (raio curto,
/// especialidade rara, ou os dois combinados) restritivo demais -- não a
/// ausência real de profissionais cadastrados na base.
class _CartaoSemResultados extends StatelessWidget {
  final bool temFiltrosAtivos;
  final VoidCallback aoLimparFiltros;

  const _CartaoSemResultados({
    required this.temFiltrosAtivos,
    required this.aoLimparFiltros,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 36, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(
              'Nenhum profissional encontrado por aqui',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              temFiltrosAtivos
                  ? 'Tente aumentar o raio de busca ou escolher outra especialidade.'
                  : 'Ainda não há profissionais cadastrados nesta região.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (temFiltrosAtivos) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: aoLimparFiltros,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Limpar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
