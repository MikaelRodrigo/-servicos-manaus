/// Espelha o ENUM `status_servico_enum` do banco e o `StatusServico` do
/// backend (validacao.ts). Se um status novo for adicionado lá, precisa ser
/// adicionado aqui também -- Dart não lê o schema do Postgres sozinho,
/// assim como o TypeScript do backend também não lê.
enum StatusServico {
  solicitado,
  aceito,
  emAndamento,
  concluido,
  cancelado,
  recusado;

  String get valorApi {
    switch (this) {
      case StatusServico.solicitado:
        return 'SOLICITADO';
      case StatusServico.aceito:
        return 'ACEITO';
      case StatusServico.emAndamento:
        return 'EM_ANDAMENTO';
      case StatusServico.concluido:
        return 'CONCLUIDO';
      case StatusServico.cancelado:
        return 'CANCELADO';
      case StatusServico.recusado:
        return 'RECUSADO';
    }
  }

  /// Texto amigável para mostrar na tela -- nunca mostre o valor cru da API
  /// (tipo "EM_ANDAMENTO") direto para o usuário final.
  String get rotulo {
    switch (this) {
      case StatusServico.solicitado:
        return 'Solicitado';
      case StatusServico.aceito:
        return 'Aceito';
      case StatusServico.emAndamento:
        return 'Em andamento';
      case StatusServico.concluido:
        return 'Concluído';
      case StatusServico.cancelado:
        return 'Cancelado';
      case StatusServico.recusado:
        return 'Recusado';
    }
  }

  static StatusServico fromApi(String valor) {
    switch (valor) {
      case 'SOLICITADO':
        return StatusServico.solicitado;
      case 'ACEITO':
        return StatusServico.aceito;
      case 'EM_ANDAMENTO':
        return StatusServico.emAndamento;
      case 'CONCLUIDO':
        return StatusServico.concluido;
      case 'CANCELADO':
        return StatusServico.cancelado;
      case 'RECUSADO':
        return StatusServico.recusado;
      default:
        throw FormatException('Status de serviço desconhecido: "$valor"');
    }
  }
}

/// Espelha `Servico` de servicos.repository.ts -- o que volta de
/// POST /servicos, GET /servicos/meus e GET /servicos/:id.
class Servico {
  final String id;
  final String clienteId;
  final String profissionalId;
  final StatusServico status;
  final String? descricao;
  final DateTime data;
  final DateTime? dataConclusao;
  final String clienteNome;
  final String profissionalNome;

  const Servico({
    required this.id,
    required this.clienteId,
    required this.profissionalId,
    required this.status,
    required this.descricao,
    required this.data,
    required this.dataConclusao,
    required this.clienteNome,
    required this.profissionalNome,
  });

  factory Servico.fromJson(Map<String, dynamic> json) {
    return Servico(
      id: json['id_servico'] as String,
      clienteId: json['cliente_id'] as String,
      profissionalId: json['profissional_id'] as String,
      status: StatusServico.fromApi(json['status'] as String),
      descricao: json['descricao'] as String?,
      data: DateTime.parse(json['data'] as String),
      dataConclusao: json['data_conclusao'] != null
          ? DateTime.parse(json['data_conclusao'] as String)
          : null,
      clienteNome: json['cliente_nome'] as String,
      profissionalNome: json['profissional_nome'] as String,
    );
  }
}
