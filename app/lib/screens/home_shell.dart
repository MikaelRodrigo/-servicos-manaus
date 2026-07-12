import 'package:flutter/material.dart';
import 'mapa_screen.dart';
import 'servicos_screen.dart';

/// Casca de navegação da área logada: uma barra inferior alternando entre
/// "Mapa" e "Meus Serviços". Sem isto, o app só tinha uma tela depois do
/// login e não havia como chegar no histórico/ações de serviço -- por
/// isso este widget existe.
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

  final _telas = const [
    MapaScreen(),
    ServicosScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _indiceAtual, children: _telas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indiceAtual,
        onDestinationSelected: (indice) => setState(() => _indiceAtual = indice),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Meus Serviços',
          ),
        ],
      ),
    );
  }
}
