/// Espelha cada item do array `dados` de GET /profissionais/proximos
/// (ver profissionais.repository.ts -> `ProfissionalProximo`).
///
/// Repare que `latitude`/`longitude` chegam como `num` no JSON (podem vir
/// como int OU double dependendo do valor) -- por isso o cast é
/// `(json['latitude'] as num).toDouble()`, não `as double` direto. Um valor
/// tipo `-3.0` pode chegar como inteiro no JSON e o `as double` quebraria.
class Profissional {
  final String id;
  final String tipoPessoa; // 'PF' ou 'PJ'
  final String nomeExibicao;
  final String? atuacao;
  final String email;
  final String contato;
  final double latitude;
  final double longitude;
  final double distanciaMetros;
  final String? urlFotoPerfil;

  const Profissional({
    required this.id,
    required this.tipoPessoa,
    required this.nomeExibicao,
    required this.atuacao,
    required this.email,
    required this.contato,
    required this.latitude,
    required this.longitude,
    required this.distanciaMetros,
    this.urlFotoPerfil,
  });

  factory Profissional.fromJson(Map<String, dynamic> json) {
    return Profissional(
      id: json['profissional_id'] as String,
      tipoPessoa: json['tipo_pessoa'] as String,
      nomeExibicao: json['nome_exibicao'] as String,
      atuacao: json['atuacao'] as String?,
      email: json['email'] as String,
      contato: json['contato'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distanciaMetros: (json['distancia_metros'] as num).toDouble(),
      urlFotoPerfil: json['url_foto_perfil'] as String?,
    );
  }

  /// Distância formatada para exibir na tela -- em metros se for perto,
  /// em km se for longe. Regra de UI, por isso mora no model de
  /// apresentação e não no backend.
  String get distanciaFormatada {
    if (distanciaMetros < 1000) {
      return '${distanciaMetros.round()} m';
    }
    return '${(distanciaMetros / 1000).toStringAsFixed(1)} km';
  }
}
