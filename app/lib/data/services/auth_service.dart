import '../models/usuario.dart';
import '../models/verificacao_telefone.dart';
import 'api_client.dart';

/// Camada de transporte para /auth/*. Só sabe montar a chamada HTTP e
/// devolver o model já pronto -- quem decide QUAIS campos mandar (PF ou PJ,
/// cliente ou profissional) é a TELA de cadastro, porque isso é decisão de
/// formulário/UI, não de "como falar com a API".
class AuthService {
  AuthService._();
  static final AuthService instancia = AuthService._();

  final _api = ApiClient.instancia;

  Future<SessaoAutenticada> login({
    required Papel papel,
    required String email,
    required String senha,
  }) async {
    final resposta = await _api.post(
      '/auth/login',
      comAutenticacao: false, // óbvio: pra logar você ainda não tem token.
      corpo: {
        'papel': papel.valorApi,
        'email': email,
        'senha': senha,
      },
    );
    return SessaoAutenticada.fromJson(resposta as Map<String, dynamic>);
  }

  /// `corpo` já vem pronto da tela de cadastro (com tipo_pessoa, email,
  /// senha, e os campos PF ou PJ). Devolve o id criado E o resultado do
  /// primeiro envio de código SMS (migração 17 -- o backend já dispara o
  /// código automaticamente dentro do próprio cadastro, não é uma chamada
  /// separada).
  Future<({String id, ResultadoEnvioCodigo verificacao})> cadastrarCliente(
    Map<String, dynamic> corpo,
  ) async {
    final resposta = await _api.post(
      '/auth/cadastro/cliente',
      comAutenticacao: false,
      corpo: corpo,
    ) as Map<String, dynamic>;
    return (
      id: resposta['cliente_id'] as String,
      verificacao: ResultadoEnvioCodigo.fromJson(resposta['verificacao'] as Map<String, dynamic>),
    );
  }

  Future<({String id, ResultadoEnvioCodigo verificacao})> cadastrarProfissional(
    Map<String, dynamic> corpo,
  ) async {
    final resposta = await _api.post(
      '/auth/cadastro/profissional',
      comAutenticacao: false,
      corpo: corpo,
    ) as Map<String, dynamic>;
    return (
      id: resposta['profissional_id'] as String,
      verificacao: ResultadoEnvioCodigo.fromJson(resposta['verificacao'] as Map<String, dynamic>),
    );
  }

  /// POST /auth/verificar-telefone/reenviar -- pede um código NOVO (o
  /// anterior expirou em 10 minutos, ou nunca chegou). `usuarioId` é o
  /// `cliente_id`/`profissional_id` devolvido pelo cadastro (ou pelo corpo
  /// do erro 403 de login, ver `AuthProvider.login`).
  Future<ResultadoEnvioCodigo> reenviarCodigoVerificacao({
    required Papel papel,
    required String usuarioId,
  }) async {
    final resposta = await _api.post(
      '/auth/verificar-telefone/reenviar',
      comAutenticacao: false,
      corpo: {'papel': papel.valorApi, 'usuario_id': usuarioId},
    ) as Map<String, dynamic>;
    return ResultadoEnvioCodigo.fromJson(resposta['verificacao'] as Map<String, dynamic>);
  }

  /// POST /auth/verificar-telefone/confirmar -- confirma o código digitado.
  /// Lança `ApiException` (código errado/expirado/muitas tentativas) --
  /// quem chama mostra a mensagem, o texto já vem pronto do backend.
  Future<void> confirmarCodigoVerificacao({
    required Papel papel,
    required String usuarioId,
    required String codigo,
  }) async {
    await _api.post(
      '/auth/verificar-telefone/confirmar',
      comAutenticacao: false,
      corpo: {'papel': papel.valorApi, 'usuario_id': usuarioId, 'codigo': codigo},
    );
  }
}
