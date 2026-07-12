import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models/servico.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/avaliacoes_service.dart';
import '../data/services/servicos_service.dart';
import '../providers/auth_provider.dart';
import 'avaliacao_screen.dart';

/// Detalhe de UM serviço + os botões da máquina de estados (ver
/// servicos.repository.ts no backend -- este arquivo é o espelho visual
/// daquele diagrama de transições).
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
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (contextoDialogo) => AlertDialog(
          title: Text(confirmacaoTitulo ?? 'Confirmar ação'),
          content: Text(confirmacaoMensagem),
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
      if (confirmou != true) return;
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
          ..._botoesDeAcao(servico, papel),
        ],
      ),
    );
  }

  List<Widget> _botoesDeAcao(Servico servico, Papel? papel) {
    if (_processando) {
      return [const Center(child: CircularProgressIndicator())];
    }

    final botoes = <Widget>[];

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
          botoes.add(FilledButton.icon(
            onPressed: () => _executarAcao(ServicosService.instancia.iniciar),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar atendimento'),
          ));
          break;
        case StatusServico.emAndamento:
          botoes.add(FilledButton.icon(
            onPressed: () => _executarAcao(
              ServicosService.instancia.concluir,
              confirmacaoTitulo: 'Concluir serviço?',
              confirmacaoMensagem: 'Confirme só depois que o serviço estiver realmente terminado.',
            ),
            icon: const Icon(Icons.done_all),
            label: const Text('Concluir'),
          ));
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
          break; // sem ação especial de cliente aqui além de cancelar, abaixo.
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

  Widget _botaoAvaliar({required bool jaAvaliou, required Servico servico}) {
    if (jaAvaliou) {
      return const Card(
        color: Color(0xFFE8F5E9),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
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
