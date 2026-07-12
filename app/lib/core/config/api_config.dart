import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Endereço base da nossa API (o backend Node/Express das etapas anteriores).
///
/// ============================================================================
/// A PEGADINHA Nº 1 DE QUEM COMEÇA COM FLUTTER + BACKEND LOCAL
///
/// "localhost" dentro do EMULADOR Android não é o mesmo "localhost" do seu
/// computador -- é o localhost DENTRO DA MÁQUINA VIRTUAL do emulador. O
/// Android define um endereço especial, `10.0.2.2`, que é um "apelido" para
/// "a máquina que está rodando o emulador" (o seu PC).
///
/// Resumindo:
///   - Emulador Android  -> 10.0.2.2
///   - Simulador iOS     -> 127.0.0.1 (o simulador iOS RODA na mesma máquina,
///                          compartilha a rede, não precisa de truque)
///   - Chrome / Windows desktop -> localhost mesmo, sem truque
///   - Celular FÍSICO (não emulador) -> nenhum dos dois funciona! Você
///     precisa do IP da sua máquina NA REDE LOCAL (ex.: 192.168.0.15), e o
///     celular e o PC precisam estar no mesmo Wi-Fi. Ache o seu IP com
///     `ipconfig` no PowerShell (campo "Endereço IPv4"). Quando chegar
///     nessa etapa, troque o valor abaixo manualmente.
/// ============================================================================
class ApiConfig {
  ApiConfig._(); // Classe estática -- ninguém deveria instanciar isto.

  static const int _porta = 3333;

  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:$_porta';
    }
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:$_porta';
    }
    // iOS, Windows, macOS, Linux desktop.
    return 'http://localhost:$_porta';
  }

  /// Transforma um caminho relativo salvo pelo backend (ex.:
  /// "/uploads/avaliacoes/xxx.jpg", vindo de `url_foto_servico` ou
  /// `url_foto_perfil`) numa URL absoluta que `Image.network` consegue
  /// carregar. Devolve `null` se não houver caminho (profissional sem foto).
  static String? urlAbsoluta(String? caminhoRelativo) {
    if (caminhoRelativo == null || caminhoRelativo.isEmpty) return null;
    if (caminhoRelativo.startsWith('http')) return caminhoRelativo;
    return '$baseUrl$caminhoRelativo';
  }
}
