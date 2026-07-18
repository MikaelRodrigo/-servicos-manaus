import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../data/models/servico.dart';
import '../data/models/transacao.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/pagamentos_service.dart';
import '../data/services/servicos_service.dart';
import '../providers/auth_provider.dart';

/// Um serviço + a transação mais recente dele, já pareados -- só entram
/// aqui serviços cujo profissional chegou a PROPOR um valor (ver
/// `_carregar`, que descarta serviços sem nenhuma transação).
class _LinhaRendimento {
  final Servico servico;
  final Transacao transacao;
  const _LinhaRendimento({required this.servico, required this.transacao});
}

/// Aba "Rendimentos" da barra de navegação (ver `home_shell.dart`) --
/// resumo financeiro do modelo de intermediação (migração 15): para o
/// PROFISSIONAL, quanto já foi liberado para ele e quanto ainda está
/// congelado; para o CLIENTE, quanto ele já pagou em serviços.
///
/// Sem endpoint de agregação dedicado no backend -- monta o resumo aqui
/// mesmo, buscando `GET /servicos/meus` e, para cada serviço, a transação
/// mais recente (`GET /pagamentos/servico/:id`, já protegida por
/// ownership). Funciona bem para o volume de serviços de uma pessoa; se um
/// dia isso ficar lento, o próximo passo é um endpoint de resumo dedicado
/// no backend (mesmo padrão de `buscarResumoFinanceiroAdmin`, só que por
/// usuário em vez de global).
class RendimentosScreen extends StatefulWidget {
  const RendimentosScreen({super.key});

  @override
  State<RendimentosScreen> createState() => _RendimentosScreenState();
}

class _RendimentosScreenState extends State<RendimentosScreen> {
  bool _carregando = true;
  String? _erro;
  List<_LinhaRendimento> _linhas = const [];

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
      final servicos = await ServicosService.instancia.listarMeus();

      final linhas = <_LinhaRendimento>[];
      for (final servico in servicos) {
        // SOLICITADO/RECUSADO nunca tiveram proposta de valor -- pula sem
        // nem chamar a API de pagamentos, economiza uma requisição.
        if (servico.status == StatusServico.solicitado || servico.status == StatusServico.recusado) {
          continue;
        }

        final transacoes = await PagamentosService.instancia.listarDoServico(servico.id);
        if (transacoes.isEmpty) continue;

        final maisRecente = transacoes.first;
        // Só entram no resumo transações em que dinheiro de fato existe ou
        // vai existir -- uma proposta recusada/cancelada não é "rendimento"
        // nenhum, é só uma tentativa que não foi adiante.
        const statusRelevantes = [
          StatusTransacao.aguardandoPagamento,
          StatusTransacao.retida,
          StatusTransacao.liberada,
        ];
        if (!statusRelevantes.contains(maisRecente.status)) continue;

        linhas.add(_LinhaRendimento(servico: servico, transacao: maisRecente));
      }

      // Mais recente primeiro -- mesmo critério de `GET /servicos/meus`.
      linhas.sort((a, b) => b.servico.data.compareTo(a.servico.data));

      if (!mounted) return;
      setState(() {
        _linhas = linhas;
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

  @override
  Widget build(BuildContext context) {
    final papel = context.watch<AuthProvider>().usuario?.papel;
    final ehProfissional = papel == Papel.profissional;

    return Scaffold(
      appBar: AppBar(title: const Text('Rendimentos')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: _linhas.isEmpty
                      ? _estadoVazio(ehProfissional)
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _cartaoResumo(ehProfissional),
                            const SizedBox(height: 16),
                            Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            for (final linha in _linhas) _cartaoLinha(linha, ehProfissional),
                          ],
                        ),
                ),
    );
  }

  Widget _estadoVazio(bool ehProfissional) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.assessment_outlined, size: 48, color: AppColors.textoSecundario),
                  const SizedBox(height: 12),
                  Text(
                    ehProfissional
                        ? 'Nenhum valor recebido ainda. Assim que você propuser um preço e o cliente pagar, o histórico aparece aqui.'
                        : 'Nenhum pagamento ainda. Assim que você confirmar um valor proposto, o histórico aparece aqui.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cartaoResumo(bool ehProfissional) {
    if (ehProfissional) {
      final liberado = _somar(_linhas
          .where((l) => l.transacao.status == StatusTransacao.liberada)
          .map((l) => l.transacao.valorRepasse));
      final congelado = _somar(_linhas
          .where((l) => l.transacao.status == StatusTransacao.retida)
          .map((l) => l.transacao.valorTotal));

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(child: _blocoResumo('Recebido', liberado, const Color(0xFF12A594))),
              Container(width: 1, height: 40, color: AppColors.bordaSutil),
              Expanded(child: _blocoResumo('Congelado', congelado, const Color(0xFFB8860B))),
            ],
          ),
        ),
      );
    }

    final totalPago = _somar(_linhas
        .where((l) =>
            l.transacao.status == StatusTransacao.retida || l.transacao.status == StatusTransacao.liberada)
        .map((l) => l.transacao.valorTotal));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: _blocoResumo('Total pago em serviços', totalPago, AppColors.destaque),
      ),
    );
  }

  Widget _blocoResumo(String rotulo, double valor, Color cor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(
          formatarReais(valor.toStringAsFixed(2)),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: cor),
        ),
      ],
    );
  }

  double _somar(Iterable<String> valoresDecimais) {
    var total = 0.0;
    for (final v in valoresDecimais) {
      total += double.tryParse(v) ?? 0;
    }
    return total;
  }

  Widget _cartaoLinha(_LinhaRendimento linha, bool ehProfissional) {
    final outraParte = ehProfissional ? linha.servico.clienteNome : linha.servico.profissionalNome;
    final valorExibido =
        ehProfissional && linha.transacao.status == StatusTransacao.liberada
            ? linha.transacao.valorRepasse
            : linha.transacao.valorTotal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(outraParte, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    linha.servico.subcategoriaNome ?? linha.servico.descricao ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatarReais(valorExibido), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                _rotuloStatus(linha.transacao.status),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rotuloStatus(StatusTransacao status) {
    final (texto, cor) = switch (status) {
      StatusTransacao.aguardandoPagamento => ('Aguardando', AppColors.textoSecundario),
      StatusTransacao.retida => ('Congelado', Color(0xFFB8860B)),
      StatusTransacao.liberada => ('Recebido', Color(0xFF12A594)),
      _ => ('', AppColors.textoSecundario),
    };
    return Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor));
  }
}
