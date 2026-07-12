import 'package:flutter/foundation.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/armazenamento_token.dart';
import '../data/services/auth_service.dart';

enum StatusAuth {
  /// Ainda checando se já existe uma sessão salva no aparelho (splash).
  carregando,
  autenticado,
  naoAutenticado,
}

/// O "cérebro" de autenticação do app -- todo widget que precisa saber
/// "quem está logado" ou "chame login/logout" fala com este Provider, nunca
/// direto com AuthService ou ArmazenamentoToken. É o padrão que separa
/// ESTADO DE TELA (o Provider, um ChangeNotifier) de TRANSPORTE (o
/// service, que só sabe HTTP) -- o mesmo espírito de repository/route que
/// usamos no backend.
class AuthProvider extends ChangeNotifier {
  StatusAuth _status = StatusAuth.carregando;
  Usuario? _usuario;
  String? _erro;
  bool _enviando = false;

  StatusAuth get status => _status;
  Usuario? get usuario => _usuario;
  String? get erro => _erro;
  bool get enviando => _enviando;
  bool get autenticado => _status == StatusAuth.autenticado;

  AuthProvider() {
    _restaurarSessao();
  }

  /// Roda uma vez, na inicialização do app (chamado pelo construtor).
  /// Se tiver token + usuário salvos, pula direto para "autenticado" sem
  /// pedir login de novo. Não validamos o token contra a API aqui de
  /// propósito -- isso deixaria o app lento para abrir. Se o token tiver
  /// expirado, a primeira chamada autenticada bate 401 (ver ApiException)
  /// e é ali que tratamos o logout forçado.
  Future<void> _restaurarSessao() async {
    final token = await ArmazenamentoToken.instancia.ler();
    final usuarioJson = await ArmazenamentoToken.instancia.lerUsuario();

    if (token != null && usuarioJson != null) {
      _usuario = Usuario.fromJsonCompleto(usuarioJson);
      _status = StatusAuth.autenticado;
    } else {
      _status = StatusAuth.naoAutenticado;
    }
    notifyListeners();
  }

  Future<bool> login({
    required Papel papel,
    required String email,
    required String senha,
  }) async {
    _enviando = true;
    _erro = null;
    notifyListeners();

    try {
      final sessao = await AuthService.instancia.login(papel: papel, email: email, senha: senha);

      await ArmazenamentoToken.instancia.salvar(sessao.token);
      await ArmazenamentoToken.instancia.salvarUsuario(sessao.usuario.toJson());

      _usuario = sessao.usuario;
      _status = StatusAuth.autenticado;
      return true;
    } on ApiException catch (erro) {
      _erro = erro.mensagem;
      return false;
    } finally {
      _enviando = false;
      notifyListeners();
    }
  }

  /// Desloga tanto por ação do usuário (botão "Sair") quanto forçado por
  /// um 401 vindo de qualquer chamada autenticada -- as telas que chamam a
  /// API devem capturar `ApiException` com `statusCode == 401` e chamar
  /// isto, mandando a pessoa de volta pro login.
  Future<void> logout() async {
    await ArmazenamentoToken.instancia.limpar();
    _usuario = null;
    _erro = null;
    _status = StatusAuth.naoAutenticado;
    notifyListeners();
  }

  void limparErro() {
    _erro = null;
    notifyListeners();
  }
}
