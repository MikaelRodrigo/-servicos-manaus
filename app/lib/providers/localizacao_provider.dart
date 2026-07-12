import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Cuida de UMA coisa: descobrir onde o usuário está, tratando os três
/// jeitos de dar errado (GPS desligado, permissão negada, permissão negada
/// "para sempre") com mensagens que fazem sentido para quem não programa.
///
/// Coordenada errada ou ausente aqui derruba a Etapa 1 inteira lá do
/// backend -- lembra da regra de ouro do PostGIS
/// (ST_MakePoint(longitude, latitude), nessa ordem)? Ela some se o app
/// mandar `latitude: 0, longitude: 0` por engano. Por isso nunca chamamos
/// a API de busca sem antes confirmar que `posicao` não é nula.
class LocalizacaoProvider extends ChangeNotifier {
  Position? _posicao;
  String? _erro;
  bool _carregando = false;

  Position? get posicao => _posicao;
  String? get erro => _erro;
  bool get carregando => _carregando;
  bool get temPosicao => _posicao != null;

  Future<void> obterLocalizacaoAtual() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      // 1) O GPS do aparelho está ligado?
      final servicoHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!servicoHabilitado) {
        throw Exception('Ative a localização (GPS) do aparelho para ver o mapa.');
      }

      // 2) Temos permissão? Se nunca foi perguntado, `requestPermission`
      // dispara o dialogo nativo do Android/iOS.
      LocationPermission permissao = await Geolocator.checkPermission();
      if (permissao == LocationPermission.denied) {
        permissao = await Geolocator.requestPermission();
        if (permissao == LocationPermission.denied) {
          throw Exception('Permissão de localização negada.');
        }
      }
      if (permissao == LocationPermission.deniedForever) {
        // Nesse estado, pedir de novo pelo app não adianta -- o SO bloqueou.
        // A única saída é a pessoa ir manualmente nas configurações do
        // aparelho e liberar. A mensagem já avisa isso.
        throw Exception(
          'Permissão de localização bloqueada. Ative manualmente nas configurações do aparelho.',
        );
      }

      // 3) Finalmente, a posição.
      _posicao = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (erro) {
      _erro = erro.toString().replaceFirst('Exception: ', '');
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }
}
