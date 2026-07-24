/// Espelha o `status` de `documentos_antecedentes` (migração 18 no
/// backend) -- ver `GET /profissionais/me/documento-antecedentes`.
/// `naoEnviado` é um estado só do APP (o backend devolve
/// `{status: "NAO_ENVIADO"}` quando o profissional nunca enviou nada
/// ainda -- não existe linha nenhuma na tabela pra esse caso).
enum StatusDocumentoAntecedentes { naoEnviado, pendente, aprovado, rejeitado }

extension StatusDocumentoAntecedentesJson on StatusDocumentoAntecedentes {
  static StatusDocumentoAntecedentes fromApi(String valor) {
    switch (valor) {
      case 'NAO_ENVIADO':
        return StatusDocumentoAntecedentes.naoEnviado;
      case 'PENDENTE':
        return StatusDocumentoAntecedentes.pendente;
      case 'APROVADO':
        return StatusDocumentoAntecedentes.aprovado;
      case 'REJEITADO':
        return StatusDocumentoAntecedentes.rejeitado;
      default:
        throw FormatException('Status de documento de antecedentes desconhecido: "$valor"');
    }
  }
}

/// Certidão de antecedentes criminais do profissional (migração 18) --
/// nunca carrega o ARQUIVO em si (o backend não devolve URL nenhuma pra
/// este documento, ver comentário em `services/uploadService.ts` no
/// backend: é um documento sensível, só transmitido por rota autenticada).
/// Só o STATUS e o resultado da checagem automática, que é puramente
/// informativo -- a aprovação de verdade é sempre manual, de um admin.
class DocumentoAntecedentes {
  final StatusDocumentoAntecedentes status;
  final List<String> palavrasChaveEncontradas;
  final bool? nomeEncontrado;
  final bool? cpfEncontrado;
  final String? motivoRejeicao;
  final DateTime? createdAt;

  const DocumentoAntecedentes({
    required this.status,
    required this.palavrasChaveEncontradas,
    required this.nomeEncontrado,
    required this.cpfEncontrado,
    required this.motivoRejeicao,
    required this.createdAt,
  });

  factory DocumentoAntecedentes.fromJson(Map<String, dynamic> json) {
    return DocumentoAntecedentes(
      status: StatusDocumentoAntecedentesJson.fromApi(json['status'] as String),
      palavrasChaveEncontradas: (json['palavras_chave_encontradas'] as List<dynamic>? ?? const [])
          .map((item) => item as String)
          .toList(),
      nomeEncontrado: json['nome_encontrado'] as bool?,
      cpfEncontrado: json['cpf_encontrado'] as bool?,
      motivoRejeicao: json['motivo_rejeicao'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
    );
  }
}
