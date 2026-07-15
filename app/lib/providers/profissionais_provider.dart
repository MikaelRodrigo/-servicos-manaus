import 'package:flutter/foundation.dart';
import '../data/models/profissional.dart';
import '../data/services/api_client.dart';
import '../data/services/profissionais_service.dart';

/// Estado da busca que alimenta os pinos no mapa (tela principal).
class ProfissionaisProvider extends ChangeNotifier {
  List<Profissional> _resultados = [];
  bool _carregando = false;
  String? _erro;
  // true assim que a PRIMEIRA busca terminar (sucesso ou erro) -- é o que
  // distingue "ainda não buscamos nada" (ex.: esperando o GPS responder, tela
  // recém-aberta) de "buscamos e não achamos ninguém". Sem isso, o mapa não
  // teria como saber quando é seguro mostrar um estado vazio ("nenhum
  // profissional encontrado") em vez de simplesmente não mostrar nada ainda.
  bool _jaBuscou = false;

  List<Profissional> get resultados => _resultados;
  bool get carregando => _carregando;
  String? get erro => _erro;
  bool get jaBuscou => _jaBuscou;

  Future<void> buscarProximos({
    required double latitude,
    required double longitude,
    /// `null` = nenhum raio "ativo" (toggle desligado) -- ver comentário em
    /// `ProfissionaisService.buscarProximos`.
    double? raioKm,
    String? profissao,
    int? subcategoriaId,
    String? ordenarPor,
    int? limite,
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
        ordenarPor: ordenarPor,
        limite: limite,
      );
    } on ApiException catch (erro) {
      _erro = erro.mensagem;
    } finally {
      _carregando = false;
      _jaBuscou = true;
      notifyListeners();
    }
  }
}
