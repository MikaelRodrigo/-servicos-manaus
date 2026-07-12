import '../models/usuario.dart';
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
  /// senha, e os campos PF ou PJ). Devolve o id criado.
  Future<String> cadastrarCliente(Map<String, dynamic> corpo) async {
    final resposta = await _api.post(
      '/auth/cadastro/cliente',
      comAutenticacao: false,
      corpo: corpo,
    );
    return (resposta as Map<String, dynamic>)['cliente_id'] as String;
  }

  Future<String> cadastrarProfissional(Map<String, dynamic> corpo) async {
    final resposta = await _api.post(
      '/auth/cadastro/profissional',
      comAutenticacao: false,
      corpo: corpo,
    );
    return (resposta as Map<String, dynamic>)['profissional_id'] as String;
  }
}
