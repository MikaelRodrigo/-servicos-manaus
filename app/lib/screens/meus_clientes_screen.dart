import 'package:flutter/material.dart';
import '../data/models/servico.dart';
import '../data/services/api_client.dart';
import '../data/services/servicos_service.dart';
import '../widgets/avatar_iniciais.dart';
import 'servicos_screen.dart';

/// Resumo de UM cliente do profissional -- construído inteiramente a partir
/// do histórico de serviços já pedidos a ele (nunca de uma tabela/rota
/// própria de "clientes", que não existe no backend).
class _ResumoCliente {
  final String clienteId;
  final String nome;
  int total = 0;
  int concluidos = 0;
  DateTime ultimaAtividade;

  _ResumoCliente({
    required this.clienteId,
    required this.nome,
    required this.ultimaAtividade,
  });
}

/// "Meus Clientes" -- tela exclusiva do profissional, aberta pela navegação
/// inferior. Não existe uma rota "lista de clientes" no backend; a tela
/// nasce 100% no app, AGRUPANDO o mesmo `GET /servicos/meus` que já
/// alimenta "Solicitações" -- zero chamada de rede extra, zero dado
/// inventado: só uma forma diferente de olhar para dados que o app já tem.
///
/// Tocar num cliente abre `ServicosScreen` filtrada só pelos serviços
/// pedidos por ELE (ver `filtroClienteId`), reaproveitando 100% da tela de
/// lista já existente em vez de duplicar a renderização de cards.
class MeusClientesScreen extends StatefulWidget {
  const MeusClientesScreen({super.key});

  @override
  State<MeusClientesScreen> createState() => _MeusClientesScreenState();
}

class _MeusClientesScreenState extends State<MeusClientesScreen> {
  late Future<List<_ResumoCliente>> _futuroClientes;

  @override
  void initState() {
    super.initState();
    _futuroClientes = _carregarClientes();
  }

  Future<List<_ResumoCliente>> _carregarClientes() async {
    final servicos = await ServicosService.instancia.listarMeus();

    final porCliente = <String, _ResumoCliente>{};
    for (final servico in servicos) {
      final resumo = porCliente.putIfAbsent(
        servico.clienteId,
        () => _ResumoCliente(
          clienteId: servico.clienteId,
          nome: servico.clienteNome,
          ultimaAtividade: servico.data,
        ),
      );
      resumo.total += 1;
      if (servico.status == StatusServico.concluido) {
        resumo.concluidos += 1;
      }
      if (servico.data.isAfter(resumo.ultimaAtividade)) {
        resumo.ultimaAtividade = servico.data;
      }
    }

    // Cliente mais recente primeiro -- é o que mais provavelmente a pessoa
    // quer revisitar (acompanhar um pedido em andamento, por exemplo), não
    // ordem alfabética.
    final lista = porCliente.values.toList()
      ..sort((a, b) => b.ultimaAtividade.compareTo(a.ultimaAtividade));
    return lista;
  }

  Future<void> _recarregar() async {
    setState(() => _futuroClientes = _carregarClientes());
    await _futuroClientes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meus clientes')),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<List<_ResumoCliente>>(
          future: _futuroClientes,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              final mensagem = snapshot.error is ApiException
                  ? (snapshot.error as ApiException).mensagem
                  : 'Não foi possível carregar seus clientes.';
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(mensagem, textAlign: TextAlign.center)),
                  ),
                ],
              );
            }

            final clientes = snapshot.data ?? [];
            if (clientes.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Você ainda não tem clientes.\nAssim que alguém solicitar um serviço, ele aparece aqui.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: clientes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, indice) {
                final cliente = clientes[indice];
                return Card(
                  child: ListTile(
                    leading: AvatarIniciais(nome: cliente.nome),
                    title: Text(cliente.nome),
                    subtitle: Text(
                      '${cliente.total} serviço(s) · ${cliente.concluidos} concluído(s)',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ServicosScreen(
                            filtroClienteId: cliente.clienteId,
                            tituloPersonalizado: cliente.nome,
                          ),
                        ),
                      );
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
