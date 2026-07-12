import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models/servico.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/servicos_service.dart';
import '../providers/auth_provider.dart';
import 'servico_detalhe_screen.dart';

/// Lista "Meus Serviços" -- o mesmo endpoint (GET /servicos/meus) devolve
/// coisas diferentes dependendo de quem está logado (ver
/// servicos.routes.ts: cliente vê onde é cliente_id, profissional vê onde
/// é profissional_id). A tela nem precisa saber disso -- só pede "meus
/// serviços" e mostra o que vier.
class ServicosScreen extends StatefulWidget {
  const ServicosScreen({super.key});

  @override
  State<ServicosScreen> createState() => _ServicosScreenState();
}

class _ServicosScreenState extends State<ServicosScreen> {
  late Future<List<Servico>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = ServicosService.instancia.listarMeus();
  }

  Future<void> _recarregar() async {
    setState(() {
      _futuro = ServicosService.instancia.listarMeus();
    });
    await _futuro;
  }

  Color _corDoStatus(StatusServico status) {
    switch (status) {
      case StatusServico.solicitado:
        return Colors.orange;
      case StatusServico.aceito:
        return Colors.blue;
      case StatusServico.emAndamento:
        return Colors.purple;
      case StatusServico.concluido:
        return Colors.green;
      case StatusServico.cancelado:
      case StatusServico.recusado:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final papel = context.watch<AuthProvider>().usuario?.papel;

    return Scaffold(
      appBar: AppBar(title: const Text('Meus Serviços')),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<List<Servico>>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              final mensagem = snapshot.error is ApiException
                  ? (snapshot.error as ApiException).mensagem
                  : 'Erro ao carregar serviços.';
              // ListView dentro do erro para o RefreshIndicator continuar
              // funcionando mesmo quando a lista falha (senão o puxar-para-
              // atualizar fica sem efeito nenhum).
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(mensagem)),
                  ),
                ],
              );
            }

            final servicos = snapshot.data ?? [];
            if (servicos.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        papel == Papel.cliente
                            ? 'Você ainda não solicitou nenhum serviço.\nVá até o mapa para encontrar um profissional.'
                            : 'Nenhum serviço solicitado a você ainda.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: servicos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, indice) {
                final servico = servicos[indice];
                final outroNome =
                    papel == Papel.cliente ? servico.profissionalNome : servico.clienteNome;

                return Card(
                  child: ListTile(
                    title: Text(outroNome),
                    subtitle: Text(servico.descricao?.isNotEmpty == true
                        ? servico.descricao!
                        : 'Sem descrição'),
                    trailing: Chip(
                      label: Text(
                        servico.status.rotulo,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      backgroundColor: _corDoStatus(servico.status),
                      padding: EdgeInsets.zero,
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServicoDetalheScreen(servicoId: servico.id),
                        ),
                      );
                      // Ao voltar do detalhe (pode ter mudado o status lá
                      // dentro -- aceitar, cancelar, etc.), recarrega a
                      // lista para refletir o estado mais recente.
                      _recarregar();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
