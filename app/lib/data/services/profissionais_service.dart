import 'package:image_picker/image_picker.dart';
import '../models/categoria.dart' show TagSubcategoria;
import '../models/perfil_profissional.dart';
import '../models/profissional.dart';
import 'api_client.dart';

/// Camada de transporte para /profissionais/*. É a rota PÚBLICA -- não
/// exige login, é o que alimenta o mapa antes mesmo da pessoa criar conta.
class ProfissionaisService {
  ProfissionaisService._();
  static final ProfissionaisService instancia = ProfissionaisService._();

  final _api = ApiClient.instancia;

  /// `subcategoriaId` é o filtro EXATO alimentado pelo
  /// `BuscaSubcategoriaAutocomplete` (o cliente escolhe da lista, nunca
  /// digita livre) -- ver `subcategoria_id` em profissionais.repository.ts
  /// no backend. `profissao` continua existindo por compatibilidade (busca
  /// textual antiga), mas a tela do mapa não usa mais os dois ao mesmo
  /// tempo.
  Future<List<Profissional>> buscarProximos({
    required double latitude,
    required double longitude,
    /// `null` quando nenhum chip de raio está "ativo" no mapa (estado de
    /// toggle desligado -- ver `_OpcaoRaio` em mapa_screen.dart). Nesse
    /// caso o parâmetro `raio_km` simplesmente não é mandado na request, e
    /// o backend já tem um padrão pra isso (5km -- ver
    /// `numeroOpcional(req.query.raio_km, 'raio_km', 5)` em
    /// profissionais.routes.ts): a busca continua funcionando normalmente,
    /// só sem um raio "escolhido à mão" pelo usuário.
    double? raioKm,
    String? profissao,
    int? subcategoriaId,
    /// Uma de `'distancia'` (padrão), `'melhor_custo_beneficio'` ou
    /// `'melhores_avaliados'` -- ver `ordenar_por` em
    /// profissionais.routes.ts no backend. `null` equivale a `'distancia'`.
    String? ordenarPor,
    /// Quantos profissionais no máximo devolver (padrão do backend: 20,
    /// teto: 500 -- ver comentário em profissionais.routes.ts). O mapa
    /// passa um valor bem mais alto que o padrão de propósito: ele quer
    /// mostrar TODO MUNDO dentro do raio escolhido (um "cerco" geográfico),
    /// não uma página de 20 em 20 -- sem isso, aumentar o raio poderia
    /// silenciosamente cortar profissionais mais distantes.
    int? limite,
  }) async {
    final resposta = await _api.get(
      '/profissionais/proximos',
      comAutenticacao: false,
      query: {
        'latitude': latitude,
        'longitude': longitude,
        if (raioKm != null) 'raio_km': raioKm,
        if (profissao != null && profissao.isNotEmpty) 'profissao': profissao,
        if (subcategoriaId != null) 'subcategoria_id': subcategoriaId,
        if (ordenarPor != null) 'ordenar_por': ordenarPor,
        if (limite != null) 'limite': limite,
      },
    );

    final dados = (resposta as Map<String, dynamic>)['dados'] as List<dynamic>;
    return dados
        .map((item) => Profissional.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// GET /profissionais/:id -- perfil público completo (foto, descrição,
  /// atuação, endereço de atuação). Alimenta o topo da tela de perfil.
  /// NÃO inclui contato -- ver comentário no backend (profissionais.repository.ts).
  Future<PerfilProfissional> buscarPerfilPublico(String profissionalId) async {
    final resposta = await _api.get(
      '/profissionais/$profissionalId',
      comAutenticacao: false,
    );
    return PerfilProfissional.fromJson(resposta as Map<String, dynamic>);
  }

  /// GET /profissionais/:id/avaliacoes/resumo -- médias por critério +
  /// contagem total. Vira o "selo de qualidade" (estrelinhas) do perfil.
  Future<ResumoAvaliacoes> buscarResumoAvaliacoes(String profissionalId) async {
    final resposta = await _api.get(
      '/profissionais/$profissionalId/avaliacoes/resumo',
      comAutenticacao: false,
    );
    return ResumoAvaliacoes.fromJson(resposta as Map<String, dynamic>);
  }

  /// GET /profissionais/:id/portfolio -- histórico de serviços concluídos e
  /// avaliados, com fotos e comentário de cada cliente. Suporta paginação
  /// simples (o app carrega a primeira página; "carregar mais" fica para
  /// uma etapa futura caso o portfólio cresça muito).
  ///
  /// `comAutenticacao: true` (o padrão) de propósito, mesmo a rota sendo
  /// pública: se a pessoa estiver logada, o token vai junto e o backend
  /// (via `autenticacaoOpcional`) devolve `curtido_por_mim` correto para
  /// ela. Sem login, o token simplesmente não existe e a rota funciona do
  /// mesmo jeito -- só que com `curtido_por_mim` sempre `false`.
  Future<List<ItemPortfolio>> buscarPortfolio(
    String profissionalId, {
    int pagina = 1,
    int limite = 20,
  }) async {
    final resposta = await _api.get(
      '/profissionais/$profissionalId/portfolio',
      query: {'pagina': pagina, 'limite': limite},
    );

    final dados = (resposta as Map<String, dynamic>)['dados'] as List<dynamic>;
    return dados
        .map((item) => ItemPortfolio.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// POST /avaliacoes/:avaliacaoId/curtir -- alterna a curtida ("Útil") de
  /// uma avaliação do portfólio. Exige login (qualquer papel). Devolve o
  /// novo estado pronto para atualizar o card sem recarregar a lista
  /// inteira: `{curtido: true/false, totalCurtidas: N}`.
  Future<({bool curtido, int totalCurtidas})> curtirAvaliacao(String avaliacaoId) async {
    final resposta = await _api.post('/avaliacoes/$avaliacaoId/curtir') as Map<String, dynamic>;
    return (
      curtido: resposta['curtido'] as bool,
      totalCurtidas: resposta['total_curtidas'] as int,
    );
  }

  /// PATCH /profissionais/me -- o PRÓPRIO profissional logado edita seu
  /// perfil público (descrição, CEP e/ou foto). Todos opcionais -- mas ao
  /// menos um precisa vir, senão o backend recusa com 400 (não faz sentido
  /// um PATCH que não muda nada).
  ///
  /// `cep` (8 dígitos) é geocodificado NO BACKEND: o servidor define
  /// latitude/longitude e o endereço de atuação a partir dele -- o app não
  /// calcula nem envia coordenada nenhuma aqui, só o CEP.
  ///
  /// `foto` é `XFile?` (image_picker), igual ao padrão já usado em
  /// `AvaliacoesService.avaliarProfissional` -- funciona em mobile e web.
  ///
  /// `categoriaId`/`subcategoriaId` só existem JUNTOS -- vêm do
  /// `SeletorCategoriaCascata` reaberto na tela de edição. A tela chamando
  /// isto é responsável por só passar os dois ou nenhum (o backend recusa
  /// um par incompleto -- ver PATCH /profissionais/me).
  Future<PerfilProfissional> atualizarMeuPerfil({
    String? descricao,
    String? cep,
    int? categoriaId,
    int? subcategoriaId,
    XFile? foto,
  }) async {
    final resposta = await _api.patchMultipart(
      '/profissionais/me',
      campos: {
        if (descricao != null) 'descricao': descricao,
        if (cep != null) 'cep': cep,
        if (categoriaId != null) 'categoria_id': categoriaId.toString(),
        if (subcategoriaId != null) 'subcategoria_id': subcategoriaId.toString(),
      },
      bytesArquivo: foto != null ? await foto.readAsBytes() : null,
      nomeArquivo: foto?.name,
    );
    return PerfilProfissional.fromJson(resposta as Map<String, dynamic>);
  }

  /// POST /profissionais/me/subcategorias -- adiciona UMA tag de
  /// especialidade nova ao profissional logado (migração 11 no backend).
  /// Idempotente: adicionar uma que já existe não dá erro. Devolve a lista
  /// ATUALIZADA de tags -- é o que a tela usa para redesenhar os "boxes"
  /// sem precisar buscar o perfil inteiro de novo.
  Future<List<TagSubcategoria>> adicionarTag(int subcategoriaId) async {
    final resposta = await _api.post(
      '/profissionais/me/subcategorias',
      corpo: {'subcategoria_id': subcategoriaId},
    ) as Map<String, dynamic>;
    final dados = resposta['dados'] as List<dynamic>;
    return dados
        .map((item) => TagSubcategoria.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// DELETE /profissionais/me/subcategorias/:subcategoriaId -- remove UMA
  /// tag. O backend recusa (400 -- vira [ApiException]) se for a última que
  /// sobrou: um profissional precisa manter ao menos uma especialidade.
  Future<List<TagSubcategoria>> removerTag(int subcategoriaId) async {
    final resposta = await _api.delete(
      '/profissionais/me/subcategorias/$subcategoriaId',
    ) as Map<String, dynamic>;
    final dados = resposta['dados'] as List<dynamic>;
    return dados
        .map((item) => TagSubcategoria.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
