import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import 'mapa_screen.dart';
import 'perfil_cliente_screen.dart';
import 'servicos_screen.dart';

/// Casca de navegação da área logada: uma barra inferior alternando entre
/// "Mapa", "Meus Serviços" e (só para clientes) "Perfil". Sem isto, o app
/// só tinha uma tela depois do login e não havia como chegar no
/// histórico/ações de serviço -- por isso este widget existe.
///
/// A aba "Perfil" só aparece para quem está logado como CLIENTE: o
/// profissional já tem sua própria tela de edição de perfil acessível a
/// partir do mapa/perfil público (`editar_perfil_screen.dart`), então
/// duplicar uma aba "Perfil" para ele aqui seria redundante.
///
/// Usa `IndexedStack` (não troca de widget, só de VISIBILIDADE) para que
/// trocar de aba não jogue fora o estado de cada tela -- ex.: se você
/// rolou o mapa ou já buscou profissionais, isso continua lá ao voltar
/// da aba "Meus Serviços", em vez de recarregar do zero.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _indiceAtual = 0;

  @override
  Widget build(BuildContext context) {
    final papel = context.watch<AuthProvider>().usuario?.papel;
    final ehCliente = papel == Papel.cliente;

    final telas = [
      const MapaScreen(),
      const ServicosScreen(),
      if (ehCliente) const PerfilClienteScreen(),
    ];

    // Se a aba "Perfil" desaparecer (ex.: sessão trocou de papel) e o
    // índice atual ficasse fora da lista, voltamos para a primeira aba em
    // vez de deixar o IndexedStack apontar para um índice inexistente.
    final indiceSeguro = _indiceAtual < telas.length ? _indiceAtual : 0;

    return Scaffold(
      body: IndexedStack(index: indiceSeguro, children: telas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: indiceSeguro,
        onDestinationSelected: (indice) => setState(() => _indiceAtual = indice),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          const NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Meus Serviços',
          ),
          if (ehCliente)
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Perfil',
            ),
        ],
      ),
    );
  }
}
