import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../data/models/servico.dart';
import '../data/models/transacao.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/avaliacoes_service.dart';
import '../data/services/pagamentos_service.dart';
import '../data/services/servicos_service.dart';
import '../providers/auth_provider.dart';
import 'avaliacao_screen.dart';

/// Detalhe de UM serviço + os botões da máquina de estados (ver
/// servicos.repository.ts no backend) + o fluxo de proposta/pagamento
/// (ver pagamentos.routes.ts, migração 15 -- modelo de intermediação: o
/// profissional avalia o serviço presencialmente e propõe um valor, o
/// cliente confirma e paga direto na conta do profissional, o valor fica
/// retido/congelado até o cliente confirmar o término do serviço).
///
/// Recebe só o ID e busca os dados na hora de abrir -- não recebe o
/// `Servico` pronto por navegação. Isso garante que o status mostrado é
/// sempre o mais atual (o serviço pode ter sido alterado por outra pessoa,
/// ou em outra aba, desde que a lista foi carregada).
class ServicoDetalheScreen extends StatefulWidget {
  final String servicoId;
  const ServicoDetalheScreen({super.key, required this.servicoId});

  @override
  State<ServicoDetalheScreen> createState() => _ServicoDetalheScreenState();
}

class _ServicoDetalheScreenState extends State<ServicoDetalheScreen> {
  Servico? _servico;
  Transacao? _transacao;
  Map<String, dynamic>? _avaliacoes;
  bool _carregando = true;
  bool _processando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      final servico = await ServicosService.instancia.buscarPorId(widget.servicoId);

      // Só faz sentido buscar transação a partir de "ACEITO" em diante --
      // antes disso (SOLICITADO) o profissional nem pôde propor um valor
      // ainda. Ignora silenciosamente se não houver nenhuma (ex.: serviço
      // ACEITO mas o profissional ainda não abriu a tela de propor valor).
      Transacao? transacao;
      if (servico.status != StatusServico.solicitado) {
        final transacoes = await PagamentosService.instancia.listarDoServico(widget.servicoId);
        if (transacoes.isNotEmpty) transacao = transacoes.first;
      }

      // Só faz sentido perguntar pelas avaliações se o serviço já terminou
      // -- antes disso, o backend nem deixaria elas existirem (trigger
      // fn_valida_servico_concluido).
      Map<String, dynamic>? avaliacoes;
      if (servico.status == StatusServico.concluido) {
        avaliacoes = await AvaliacoesService.instancia.buscarAvaliacoes(widget.servicoId);
      }

      if (!mounted) return;
      setState(() {
        _servico = servico;
        _transacao = transacao;
        _avaliacoes = avaliacoes;
        _carregando = false;
      });
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = erro.mensagem;
        _carregando = false;
      });
    }
  }

  Future<void> _executarAcao(
    Future<Servico> Function(String id) acao, {
    String? confirmacaoTitulo,
    String? confirmacaoMensagem,
  }) async {
    if (confirmacaoMensagem != null) {
      final confirmou = await _confirmar(confirmacaoTitulo ?? 'Confirmar ação', confirmacaoMensagem);
      if (!confirmou) return;
    }

    setState(() => _processando = true);
    try {
      final atualizado = await acao(widget.servicoId);
      if (!mounted) return;
      setState(() {
        _servico = atualizado;
        _processando = false;
      });
      if (atualizado.status == StatusServico.concluido) {
        _carregar(); // busca as avaliações agora que liberou.
      }
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
    }
  }

  /// Mesma ideia de `_executarAcao`, mas para as ações do módulo de
  /// pagamentos (que sempre operam sobre a TRANSAÇÃO, não o serviço) --
  /// sempre recarrega tudo no final (`_carregar`), porque uma ação de
  /// pagamento quase sempre muda o status do SERVIÇO também (ex.: confirmar
  /// vira EM_ANDAMENTO, confirmar-término vira CONCLUIDO).
  Future<void> _executarAcaoPagamento(
    Future<void> Function() acao, {
    String? confirmacaoTitulo,
    String? confirmacaoMensagem,
  }) async {
    if (confirmacaoMensagem != null) {
      final confirmou = await _confirmar(confirmacaoTitulo ?? 'Confirmar ação', confirmacaoMensagem);
      if (!confirmou) return;
    }

    setState(() => _processando = true);
    try {
      await acao();
      if (!mounted) return;
      setState(() => _processando = false);
      await _carregar();
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
    }
  }

  Future<bool> _confirmar(String titulo, String mensagem) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contextoDialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contextoDialogo).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return confirmou == true;
  }

  @override
  Widget build(BuildContext context) {
    final papel = context.watch<AuthProvider>().usuario?.papel;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do serviço')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : _corpo(papel),
    );
  }

  Widget _corpo(Papel? papel) {
    final servico = _servico!;
    final ehCliente = papel == Papel.cliente;

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ehCliente ? servico.profissionalNome : servico.clienteNome,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Chip(label: Text(servico.status.rotulo)),
                  const SizedBox(height: 12),
                  Text('Descrição', style: Theme.of(context).textTheme.labelLarge),
                  Text(servico.descricao?.isNotEmpty == true ? servico.descricao! : '(nenhuma)'),
                  const SizedBox(height: 12),
                  Text('Solicitado em', style: Theme.of(context).textTheme.labelLarge),
                  Text(_formatarDataHora(servico.data)),
                  if (servico.dataConclusao != null) ...[
                    const SizedBox(height: 12),
                    Text('Concluído em', style: Theme.of(context).textTheme.labelLarge),
                    Text(_formatarDataHora(servico.dataConclusao!)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._cartoesDePagamento(servico, papel),
          ..._botoesDeAcao(servico, papel),
        ],
      ),
    );
  }

  /* ==========================================================================
     MÓDULO DE PAGAMENTOS (migração 15) -- cartões informativos que aparecem
     ACIMA dos botões de ação normais, sempre que existir uma transação
     relevante para o status atual do serviço.
     ========================================================================= */
  List<Widget> _cartoesDePagamento(Servico servico, Papel? papel) {
    final transacao = _transacao;
    if (transacao == null) return const [];

    switch (transacao.status) {
      case StatusTransacao.aguardandoConfirmacaoCliente:
        return [_cartaoPropostaAguardando(transacao, papel), const SizedBox(height: 16)];
      case StatusTransacao.aguardandoPagamento:
        return [_cartaoAguardandoPagamento(transacao), const SizedBox(height: 16)];
      case StatusTransacao.retida:
        return [_cartaoValorRetido(transacao, papel), const SizedBox(height: 16)];
      case StatusTransacao.liberada:
        if (servico.status != StatusServico.concluido) return const [];
        return [_cartaoValorLiberado(transacao), const SizedBox(height: 16)];
      case StatusTransacao.recusada:
      case StatusTransacao.cancelada:
        return const []; // sem cartão -- os botões de ação abaixo cuidam de "propor de novo".
    }
  }

  Widget _cartaoPropostaAguardando(Transacao transacao, Papel? papel) {
    final ehCliente = papel == Papel.cliente;
    return Card(
      color: AppColors.superficieSecundaria,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Valor proposto', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(formatarReais(transacao.valorTotal), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (ehCliente) ...[
              Text(
                'O profissional avaliou o serviço e propôs este valor. Confirme para gerar a cobrança, ou recuse para que ele proponha outro.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _processando ? null : () => _recusarProposta(transacao),
                      child: const Text('Recusar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _processando ? null : () => _abrirDialogoConfirmarProposta(transacao),
                      child: const Text('Confirmar'),
                    ),
                  ),
                ],
              ),
            ] else
              Text(
                'Aguardando o cliente confirmar ou recusar este valor.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoAguardandoPagamento(Transacao transacao) {
    return Card(
      color: AppColors.superficieSecundaria,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_top, color: AppColors.destaque),
                const SizedBox(width: 8),
                Text('Aguardando pagamento', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${formatarReais(transacao.valorTotal)} via ${transacao.metodoPagamento?.rotulo ?? ''}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Chave de pagamento (gerada na conta do profissional)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            _campoChaveCopiavel(transacao.chaveCobranca ?? ''),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _processando ? null : () => _simularPagamentoRecebido(transacao),
              icon: const Icon(Icons.science_outlined),
              label: const Text('Já paguei (simular -- modo de testes)'),
            ),
            const SizedBox(height: 4),
            Text(
              'Este botão só funciona enquanto a API Pix própria não estiver configurada -- ele existe só para testar o app antes dela existir.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoValorRetido(Transacao transacao, Papel? papel) {
    final ehProfissional = papel == Papel.profissional;
    return Card(
      color: const Color(0xFFFFF7E6),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.ac_unit, color: Color(0xFFB8860B)),
                const SizedBox(width: 8),
                Text(
                  ehProfissional ? 'Valor congelado' : 'Pagamento recebido',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(formatarReais(transacao.valorTotal), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              ehProfissional
                  ? 'O pagamento já está na sua conta, mas retido até o cliente confirmar o término do serviço.'
                  : 'O pagamento ficará retido até você confirmar que o serviço terminou.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!ehProfissional) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _processando
                    ? null
                    : () => _executarAcaoPagamento(
                          () => PagamentosService.instancia.confirmarTermino(transacao.id),
                          confirmacaoTitulo: 'Confirmar término do serviço?',
                          confirmacaoMensagem:
                              'Confirme só depois que o serviço estiver realmente terminado -- isso libera o pagamento para o profissional.',
                        ),
                icon: const Icon(Icons.done_all),
                label: const Text('Confirmar término do serviço'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cartaoValorLiberado(Transacao transacao) {
    return Card(
      color: const Color(0xFFF0F9F6),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF12A594)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Pagamento de ${formatarReais(transacao.valorTotal)} liberado.'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoChaveCopiavel(String chave) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.superficie,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.bordaSutil),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              chave,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copiar',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: chave));
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Chave copiada.')));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _recusarProposta(Transacao transacao) => _executarAcaoPagamento(
        () => PagamentosService.instancia.recusar(transacao.id),
        confirmacaoTitulo: 'Recusar valor proposto?',
        confirmacaoMensagem: 'O profissional será avisado e poderá propor outro valor.',
      );

  Future<void> _simularPagamentoRecebido(Transacao transacao) => _executarAcaoPagamento(
        () => PagamentosService.instancia.simularPagamentoRecebido(transacao.id),
      );

  Future<void> _abrirDialogoConfirmarProposta(Transacao transacao) async {
    final metodo = await showDialog<MetodoPagamento>(
      context: context,
      builder: (contextoDialogo) => SimpleDialog(
        title: const Text('Como você vai pagar?'),
        children: MetodoPagamento.values
            .map(
              (m) => SimpleDialogOption(
                onPressed: () => Navigator.of(contextoDialogo).pop(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(m.rotulo),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (metodo == null || !mounted) return;

    await _executarAcaoPagamento(
      () async {
        await PagamentosService.instancia.confirmar(idTransacao: transacao.id, metodoPagamento: metodo);
      },
    );
  }

  /* ==========================================================================
     BOTÕES DE AÇÃO -- máquina de estados do serviço + a entrada para "propor
     valor" (profissional, status ACEITO, sem proposta em aberto).
     ========================================================================= */
  List<Widget> _botoesDeAcao(Servico servico, Papel? papel) {
    if (_processando) {
      return [const Center(child: CircularProgressIndicator())];
    }

    final botoes = <Widget>[];
    final transacao = _transacao;
    // Uma proposta está "em aberto" enquanto ainda pode virar pagamento --
    // se a última tentativa foi recusada/cancelada, o profissional pode
    // (e deve) propor de novo.
    final semPropostaEmAberto = transacao == null ||
        transacao.status == StatusTransacao.recusada ||
        transacao.status == StatusTransacao.cancelada;

    if (papel == Papel.profissional) {
      switch (servico.status) {
        case StatusServico.solicitado:
          botoes.add(FilledButton.icon(
            onPressed: () => _executarAcao(ServicosService.instancia.aceitar),
            icon: const Icon(Icons.check),
            label: const Text('Aceitar'),
          ));
          botoes.add(const SizedBox(height: 8));
          botoes.add(OutlinedButton.icon(
            onPressed: () => _executarAcao(
              ServicosService.instancia.recusar,
              confirmacaoTitulo: 'Recusar serviço?',
              confirmacaoMensagem: 'O cliente será avisado que você recusou.',
            ),
            icon: const Icon(Icons.close),
            label: const Text('Recusar'),
          ));
          break;
        case StatusServico.aceito:
          // A transição para "Em andamento" agora acontece quando o CLIENTE
          // confirma o valor proposto (ver pagamentos.routes.ts) -- aqui só
          // resta ao profissional AVALIAR o serviço e propor um valor.
          if (semPropostaEmAberto) {
            botoes.add(FilledButton.icon(
              onPressed: _abrirDialogoPropostaValor,
              icon: const Icon(Icons.request_quote_outlined),
              label: const Text('Propor valor do serviço'),
            ));
          }
          break;
        case StatusServico.emAndamento:
          // Sem botão de "Concluir" aqui -- quem confirma o término agora é
          // o CLIENTE (ver _cartaoValorRetido acima), não o profissional.
          break;
        case StatusServico.concluido:
          final jaAvaliou = _avaliacoes?['avaliacao_do_cliente'] != null;
          botoes.add(_botaoAvaliar(jaAvaliou: jaAvaliou, servico: servico));
          break;
        case StatusServico.cancelado:
        case StatusServico.recusado:
          break;
      }
    } else if (papel == Papel.cliente) {
      switch (servico.status) {
        case StatusServico.concluido:
          final jaAvaliou = _avaliacoes?['avaliacao_do_profissional'] != null;
          botoes.add(_botaoAvaliar(jaAvaliou: jaAvaliou, servico: servico));
          break;
        case StatusServico.cancelado:
        case StatusServico.recusado:
        case StatusServico.solicitado:
        case StatusServico.aceito:
        case StatusServico.emAndamento:
          break; // sem ação especial de cliente aqui além de cancelar, abaixo -- os cartões de pagamento já cobrem confirmar/recusar/confirmar-término.
      }
    }

    // Cancelar: os dois lados podem, enquanto o serviço não terminou.
    const cancelavel = [
      StatusServico.solicitado,
      StatusServico.aceito,
      StatusServico.emAndamento,
    ];
    if (cancelavel.contains(servico.status)) {
      botoes.add(const SizedBox(height: 8));
      botoes.add(TextButton.icon(
        onPressed: () => _executarAcao(
          ServicosService.instancia.cancelar,
          confirmacaoTitulo: 'Cancelar serviço?',
          confirmacaoMensagem: 'Esta ação não pode ser desfeita.',
        ),
        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
        label: const Text('Cancelar', style: TextStyle(color: Colors.red)),
      ));
    }

    return botoes;
  }

  Future<void> _abrirDialogoPropostaValor() async {
    final controlador = TextEditingController();
    final chaveFormulario = GlobalKey<FormState>();

    final valor = await showDialog<String>(
      context: context,
      builder: (contextoDialogo) => AlertDialog(
        title: const Text('Propor valor do serviço'),
        content: Form(
          key: chaveFormulario,
          child: TextFormField(
            controller: controlador,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            decoration: const InputDecoration(
              labelText: 'Valor combinado com o cliente',
              prefixText: 'R\$ ',
              hintText: '150,00',
            ),
            validator: (texto) {
              final decimal = _converterParaDecimalApi(texto ?? '');
              if (decimal == null) return 'Informe um valor válido (ex.: 150,00).';
              if (double.parse(decimal) <= 0) return 'O valor precisa ser maior que zero.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contextoDialogo).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!(chaveFormulario.currentState?.validate() ?? false)) return;
              Navigator.of(contextoDialogo).pop(_converterParaDecimalApi(controlador.text));
            },
            child: const Text('Propor'),
          ),
        ],
      ),
    );

    if (valor == null || !mounted) return;

    await _executarAcaoPagamento(
      () async {
        await PagamentosService.instancia.propor(idServico: widget.servicoId, valorTotal: valor);
      },
    );
  }

  /// Converte o que o usuário digitou (formato BR, vírgula decimal -- ex.
  /// "150,00" ou "150") para o formato que a API espera (ponto decimal --
  /// ex. "150.00"), com no máximo 2 casas. `null` se o texto não for um
  /// valor monetário válido -- mesma regra de `valorMonetarioObrigatorio`
  /// no backend (utils/validacao.ts).
  String? _converterParaDecimalApi(String textoDigitado) {
    final texto = textoDigitado.trim().replaceAll('.', '').replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(texto)) return null;
    return double.parse(texto).toStringAsFixed(2);
  }

  Widget _botaoAvaliar({required bool jaAvaliou, required Servico servico}) {
    if (jaAvaliou) {
      return const Card(
        color: Color(0xFFF0F9F6),
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF12A594)),
              SizedBox(width: 10),
              Expanded(child: Text('Você já avaliou este serviço. Obrigado!')),
            ],
          ),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AvaliacaoScreen(servico: servico)),
        );
        _carregar(); // volta da avaliação -> atualiza "já avaliou".
      },
      icon: const Icon(Icons.star_outline),
      label: const Text('Avaliar'),
    );
  }

  String _formatarDataHora(DateTime data) {
    final local = data.toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(local.day)}/${dois(local.month)}/${local.year} às ${dois(local.hour)}:${dois(local.minute)}';
  }
}
