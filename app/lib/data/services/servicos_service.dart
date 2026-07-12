import '../models/servico.dart';
import 'api_client.dart';

/// Camada de transporte para /servicos/*. Todas as chamadas aqui exigem
/// login (o ApiClient já anexa o token sozinho, `comAutenticacao: true` é
/// o padrão -- por isso nem aparece explícito nos métodos abaixo).
class ServicosService {
  ServicosService._();
  static final ServicosService instancia = ServicosService._();

  final _api = ApiClient.instancia;

  Future<Servico> solicitar({required String profissionalId, String? descricao}) async {
    final resposta = await _api.post(
      '/servicos',
      corpo: {
        'profissional_id': profissionalId,
        if (descricao != null && descricao.isNotEmpty) 'descricao': descricao,
      },
    );
    return Servico.fromJson(resposta as Map<String, dynamic>);
  }

  Future<List<Servico>> listarMeus({StatusServico? status}) async {
    final resposta = await _api.get(
      '/servicos/meus',
      query: {
        if (status != null) 'status': status.valorApi,
      },
    );
    final dados = (resposta as Map<String, dynamic>)['dados'] as List<dynamic>;
    return dados.map((item) => Servico.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<Servico> buscarPorId(String id) async {
    final resposta = await _api.get('/servicos/$id');
    return Servico.fromJson(resposta as Map<String, dynamic>);
  }

  // As cinco transições da máquina de estados (servicos.repository.ts,
  // lado a lado com o backend -- os nomes aqui foram escolhidos para bater
  // 1-para-1 com as rotas PATCH /servicos/:id/<acao>).
  Future<Servico> aceitar(String id) => _transicao(id, 'aceitar');
  Future<Servico> recusar(String id) => _transicao(id, 'recusar');
  Future<Servico> iniciar(String id) => _transicao(id, 'iniciar');
  Future<Servico> concluir(String id) => _transicao(id, 'concluir');
  Future<Servico> cancelar(String id) => _transicao(id, 'cancelar');

  Future<Servico> _transicao(String id, String acao) async {
    final resposta = await _api.patch('/servicos/$id/$acao');
    return Servico.fromJson(resposta as Map<String, dynamic>);
  }
}
