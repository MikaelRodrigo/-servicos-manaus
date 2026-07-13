import 'package:flutter/foundation.dart';
import '../data/models/profissional.dart';
import '../data/services/api_client.dart';
import '../data/services/profissionais_service.dart';

/// Estado da busca que alimenta os pinos no mapa (tela principal).
class ProfissionaisProvider extends ChangeNotifier {
  List<Profissional> _resultados = [];
  bool _carregando = false;
  String? _erro;

  List<Profissional> get resultados => _resultados;
  bool get carregando => _carregando;
  String? get erro => _erro;

  Future<void> buscarProximos({
    required double latitude,
    required double longitude,
    double raioKm = 5,
    String? profissao,
    int? subcategoriaId,
  }) async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _resultados = await ProfissionaisService.instancia.buscarProximos(
        latitude: latitude,
        longitude: longitude,
        raioKm: raioKm,
        profissao: profissao,
        subcategoriaId: subcategoriaId,
      );
    } on ApiException catch (erro) {
      _erro = erro.mensagem;
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }
}
