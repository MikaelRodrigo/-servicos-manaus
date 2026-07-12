import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda a sessão (token JWT + dados do usuário) no dispositivo de forma
/// CRIPTOGRAFADA (Keystore no Android, Keychain no iOS). Por isso
/// `flutter_secure_storage` e não `shared_preferences` -- SharedPreferences
/// grava em texto puro num arquivo XML/plist; qualquer app com acesso root,
/// ou um backup mal configurado, consegue ler o token de outro app. Não é
/// aceitável para um token que dá acesso à conta da pessoa.
///
/// Guardamos DUAS coisas separadas:
///   - o token puro, sob a chave `token_jwt` -- é só isso que o ApiClient
///     lê a cada requisição, para montar o header Authorization.
///   - o JSON do usuário (id/email/nome/papel), sob `usuario_json` -- serve
///     só para o app "lembrar quem era você" ao reabrir, sem precisar
///     decodificar o JWT no cliente nem bater na API de novo. Se o token
///     tiver expirado nesse meio tempo, a primeira chamada autenticada
///     falha com 401 e o AuthProvider desloga (ver auth_provider.dart).
class ArmazenamentoToken {
  ArmazenamentoToken._();
  static final ArmazenamentoToken instancia = ArmazenamentoToken._();

  final _storage = const FlutterSecureStorage();
  static const _chaveToken = 'token_jwt';
  static const _chaveUsuario = 'usuario_json';

  Future<void> salvar(String token) => _storage.write(key: _chaveToken, value: token);

  Future<String?> ler() => _storage.read(key: _chaveToken);

  Future<void> salvarUsuario(Map<String, dynamic> usuarioJson) =>
      _storage.write(key: _chaveUsuario, value: jsonEncode(usuarioJson));

  Future<Map<String, dynamic>?> lerUsuario() async {
    final bruto = await _storage.read(key: _chaveUsuario);
    if (bruto == null) return null;
    return jsonDecode(bruto) as Map<String, dynamic>;
  }

  Future<void> limpar() async {
    await _storage.delete(key: _chaveToken);
    await _storage.delete(key: _chaveUsuario);
  }
}
