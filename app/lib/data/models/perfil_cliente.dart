/// Espelha GET /clientes/me (ver `PerfilCliente`/`buscarMeuPerfil` no
/// backend) -- é o perfil PRIVADO do cliente, só visível para ele mesmo
/// (a rota exige login + papel "cliente" e sempre usa `req.usuario.sub`,
/// nunca um `:id` de outra pessoa). Por isso, diferente do
/// `PerfilProfissional` (público), aqui `email` aparece sem problema.
class PerfilCliente {
  final String id;
  final String tipoPessoa; // 'PF' ou 'PJ'
  final String nomeExibicao;
  final String email;
  final String contato;
  final String? endereco;
  final String? urlFotoPerfil;
  final double? latitude;
  final double? longitude;

  const PerfilCliente({
    required this.id,
    required this.tipoPessoa,
    required this.nomeExibicao,
    required this.email,
    required this.contato,
    required this.endereco,
    required this.urlFotoPerfil,
    required this.latitude,
    required this.longitude,
  });

  factory PerfilCliente.fromJson(Map<String, dynamic> json) {
    return PerfilCliente(
      id: json['cliente_id'] as String,
      tipoPessoa: json['tipo_pessoa'] as String,
      nomeExibicao: json['nome_exibicao'] as String,
      email: json['email'] as String,
      contato: json['contato'] as String,
      endereco: json['endereco'] as String?,
      urlFotoPerfil: json['url_foto_perfil'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}
