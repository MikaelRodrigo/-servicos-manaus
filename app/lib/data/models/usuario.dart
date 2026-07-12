/// Espelha o campo `papel` do token JWT (ver `jwt.ts` no backend). Não é uma
/// coluna no banco -- é decidido por QUAL TABELA a pessoa está cadastrada
/// (clientes ou profissionais). Aqui no app, esse enum decide qual fluxo de
/// telas a pessoa vê depois do login.
enum Papel { cliente, profissional }

extension PapelJson on Papel {
  /// Converte para o texto que a API espera ("cliente" / "profissional").
  String get valorApi => this == Papel.cliente ? 'cliente' : 'profissional';

  static Papel fromApi(String valor) {
    switch (valor) {
      case 'cliente':
        return Papel.cliente;
      case 'profissional':
        return Papel.profissional;
      default:
        // Nunca deveria acontecer -- se a API mandar um papel desconhecido,
        // é melhor quebrar aqui, alto e claro, do que silenciosamente tratar
        // um profissional como cliente (ou vice-versa).
        throw FormatException('Papel desconhecido vindo da API: "$valor"');
    }
  }
}

/// Os dados da pessoa logada -- o que volta em `usuario` na resposta de
/// POST /auth/login (ver auth.routes.ts).
class Usuario {
  final String id;
  final String email;
  final String nome;
  final Papel papel;

  const Usuario({
    required this.id,
    required this.email,
    required this.nome,
    required this.papel,
  });

  factory Usuario.fromJson(Map<String, dynamic> json, Papel papel) {
    return Usuario(
      id: json['id'] as String,
      email: json['email'] as String,
      nome: json['nome'] as String,
      papel: papel,
    );
  }

  /// Diferente de `fromJson` acima (que recebe o papel de um campo IRMÃO na
  /// resposta de login), este espera o papel DENTRO do próprio mapa -- é o
  /// formato que a gente mesmo escolhe para salvar/reler do
  /// flutter_secure_storage (ver ArmazenamentoToken).
  factory Usuario.fromJsonCompleto(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as String,
      email: json['email'] as String,
      nome: json['nome'] as String,
      papel: PapelJson.fromApi(json['papel'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'nome': nome,
        'papel': papel.valorApi,
      };
}

/// A resposta INTEIRA de POST /auth/login: `{ token, papel, usuario }`.
/// É isto que o AuthProvider guarda em memória (e o token, de forma segura,
/// no flutter_secure_storage) enquanto o app está aberto.
class SessaoAutenticada {
  final String token;
  final Usuario usuario;

  const SessaoAutenticada({required this.token, required this.usuario});

  factory SessaoAutenticada.fromJson(Map<String, dynamic> json) {
    final papel = PapelJson.fromApi(json['papel'] as String);
    return SessaoAutenticada(
      token: json['token'] as String,
      usuario: Usuario.fromJson(json['usuario'] as Map<String, dynamic>, papel),
    );
  }
}
