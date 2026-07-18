/// Espelha `status_transacao_enum` (migração 15 -- modelo de intermediação,
/// substitui por completo o antigo checkout via Pagar.me). Se um status novo
/// for adicionado no banco, adicione aqui também -- Dart não lê o schema do
/// Postgres sozinho.
enum StatusTransacao {
  aguardandoConfirmacaoCliente,
  recusada,
  aguardandoPagamento,
  retida,
  liberada,
  cancelada;

  String get valorApi {
    switch (this) {
      case StatusTransacao.aguardandoConfirmacaoCliente:
        return 'AGUARDANDO_CONFIRMACAO_CLIENTE';
      case StatusTransacao.recusada:
        return 'RECUSADA';
      case StatusTransacao.aguardandoPagamento:
        return 'AGUARDANDO_PAGAMENTO';
      case StatusTransacao.retida:
        return 'RETIDA';
      case StatusTransacao.liberada:
        return 'LIBERADA';
      case StatusTransacao.cancelada:
        return 'CANCELADA';
    }
  }

  static StatusTransacao fromApi(String valor) {
    switch (valor) {
      case 'AGUARDANDO_CONFIRMACAO_CLIENTE':
        return StatusTransacao.aguardandoConfirmacaoCliente;
      case 'RECUSADA':
        return StatusTransacao.recusada;
      case 'AGUARDANDO_PAGAMENTO':
        return StatusTransacao.aguardandoPagamento;
      case 'RETIDA':
        return StatusTransacao.retida;
      case 'LIBERADA':
        return StatusTransacao.liberada;
      case 'CANCELADA':
        return StatusTransacao.cancelada;
      default:
        throw FormatException('Status de transação desconhecido: "$valor"');
    }
  }
}

enum MetodoPagamento {
  pix,
  boleto,
  outro;

  String get valorApi {
    switch (this) {
      case MetodoPagamento.pix:
        return 'PIX';
      case MetodoPagamento.boleto:
        return 'BOLETO';
      case MetodoPagamento.outro:
        return 'OUTRO';
    }
  }

  String get rotulo {
    switch (this) {
      case MetodoPagamento.pix:
        return 'Pix';
      case MetodoPagamento.boleto:
        return 'Boleto';
      case MetodoPagamento.outro:
        return 'Outro';
    }
  }

  static MetodoPagamento fromApi(String valor) {
    switch (valor) {
      case 'PIX':
        return MetodoPagamento.pix;
      case 'BOLETO':
        return MetodoPagamento.boleto;
      case 'OUTRO':
        return MetodoPagamento.outro;
      default:
        throw FormatException('Método de pagamento desconhecido: "$valor"');
    }
  }
}

/// Espelha `Transacao` de transacoes.repository.ts -- uma proposta de valor
/// (e, se confirmada, a cobrança/retenção/liberação correspondente) de um
/// serviço. Um serviço pode ter VÁRIAS transações ao longo do tempo (cada
/// recusa gera uma nova tentativa) -- ver `PagamentosService.listarDoServico`,
/// que devolve todas ordenadas da mais recente para a mais antiga.
class Transacao {
  final String id;
  final String idServico;
  final StatusTransacao status;

  /// Strings decimais (ex. "150.00"), nunca double -- mesmo motivo de
  /// sempre neste projeto: aritmética de ponto flutuante não representa
  /// centavos com exatidão. Ver `utils/dinheiro.ts` no backend.
  final String valorTotal;
  final String taxaComissao;
  final String valorRepasse;

  final MetodoPagamento? metodoPagamento;
  final String? chaveCobranca;

  final DateTime propostoEm;
  final DateTime? respondidoEm;
  final DateTime? pagoEm;
  final DateTime? liberadoEm;

  const Transacao({
    required this.id,
    required this.idServico,
    required this.status,
    required this.valorTotal,
    required this.taxaComissao,
    required this.valorRepasse,
    required this.metodoPagamento,
    required this.chaveCobranca,
    required this.propostoEm,
    required this.respondidoEm,
    required this.pagoEm,
    required this.liberadoEm,
  });

  factory Transacao.fromJson(Map<String, dynamic> json) {
    return Transacao(
      id: json['id_transacao'] as String,
      idServico: json['id_servico'] as String,
      status: StatusTransacao.fromApi(json['status'] as String),
      valorTotal: json['valor_total'] as String,
      taxaComissao: json['taxa_comissao'] as String,
      valorRepasse: json['valor_repasse'] as String,
      metodoPagamento: json['metodo_pagamento'] != null
          ? MetodoPagamento.fromApi(json['metodo_pagamento'] as String)
          : null,
      chaveCobranca: json['chave_cobranca'] as String?,
      propostoEm: DateTime.parse(json['proposto_em'] as String),
      respondidoEm:
          json['respondido_em'] != null ? DateTime.parse(json['respondido_em'] as String) : null,
      pagoEm: json['pago_em'] != null ? DateTime.parse(json['pago_em'] as String) : null,
      liberadoEm: json['liberado_em'] != null ? DateTime.parse(json['liberado_em'] as String) : null,
    );
  }
}

/// Formata uma string decimal ("150.00" ou "150.5") como "R$ 150,00" --
/// formatação simples sem depender do pacote `intl` (o app não usa ele hoje
/// em nenhum outro lugar de dinheiro). Sempre 2 casas decimais, separador
/// de milhar "." e decimal ",", padrão brasileiro.
String formatarReais(String valorDecimal) {
  final valor = double.tryParse(valorDecimal) ?? 0;
  final centavosTotal = (valor * 100).round();
  final inteiro = centavosTotal ~/ 100;
  final centavos = (centavosTotal % 100).abs();

  final inteiroTexto = inteiro.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < inteiroTexto.length; i++) {
    if (i > 0 && (inteiroTexto.length - i) % 3 == 0) buffer.write('.');
    buffer.write(inteiroTexto[i]);
  }

  final sinal = valor < 0 ? '-' : '';
  return 'R\$ $sinal${buffer.toString()},${centavos.toString().padLeft(2, '0')}';
}
