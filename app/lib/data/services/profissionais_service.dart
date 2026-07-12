import 'package:image_picker/image_picker.dart';
import '../models/perfil_profissional.dart';
import '../models/profissional.dart';
import 'api_client.dart';

/// Camada de transporte para /profissionais/*. É a rota PÚBLICA -- não
/// exige login, é o que alimenta o mapa antes mesmo da pessoa criar conta.
class ProfissionaisService {
  ProfissionaisService._();
  static final ProfissionaisService instancia = ProfissionaisService._();

  final _api = ApiClient.instancia;

  Future<List<Profissional>> buscarProximos({
    required double latitude,
    required double longitude,
    double raioKm = 5,
    String? profissao,
  }) async {
    final resposta = await _api.get(
      '/profissionais/proximos',
      comAutenticacao: false,
      query: {
        'latitude': latitude,
        'longitude': longitude,
        'raio_km': raioKm,
        if (profissao != null && profissao.isNotEmpty) 'profissao': profissao,
      },
    );

    final dados = (resposta as Map<String, dynamic>)['dados'] as List<dynamic>;
    return dados
        .map((item) => Profissional.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// GET /profissionais/:id -- perfil público completo (foto, descrição,
  /// atuação, contato). Alimenta o topo da tela de perfil.
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
  /// avaliados, com foto e comentário de cada cliente. Suporta paginação
  /// simples (o app carrega a primeira página; "carregar mais" fica para
  /// uma etapa futura caso o portfólio cresça muito).
  Future<List<ItemPortfolio>> buscarPortfolio(
    String profissionalId, {
    int pagina = 1,
    int limite = 20,
  }) async {
    final resposta = await _api.get(
      '/profissionais/$profissionalId/portfolio',
      comAutenticacao: false,
      query: {'pagina': pagina, 'limite': limite},
    );

    final dados = (resposta as Map<String, dynamic>)['dados'] as List<dynamic>;
    return dados
        .map((item) => ItemPortfolio.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// PATCH /profissionais/me -- o PRÓPRIO profissional logado edita seu
  /// perfil público (descrição e/ou foto). `descricao` e `foto` são os
  /// dois opcionais -- mas ao menos um precisa vir, senão o backend recusa
  /// com 400 (não faz sentido um PATCH que não muda nada).
  ///
  /// `foto` é `XFile?` (image_picker), igual ao padrão já usado em
  /// `AvaliacoesService.avaliarProfissional` -- funciona em mobile e web.
  Future<PerfilProfissional> atualizarMeuPerfil({
    String? descricao,
    XFile? foto,
  }) async {
    final resposta = await _api.patchMultipart(
      '/profissionais/me',
      campos: {
        if (descricao != null) 'descricao': descricao,
      },
      bytesArquivo: foto != null ? await foto.readAsBytes() : null,
      nomeArquivo: foto?.name,
    );
    return PerfilProfissional.fromJson(resposta as Map<String, dynamic>);
  }
}
