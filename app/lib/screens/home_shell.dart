import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import 'editar_perfil_screen.dart';
import 'mapa_screen.dart';
import 'meus_clientes_screen.dart';
import 'perfil_cliente_screen.dart';
import 'servicos_screen.dart';

/// Casca de navegação da área logada -- uma barra inferior alternando entre
/// as áreas reais do app, adaptada por papel:
///   Cliente:      Home · Solicitações · Meus dados
///   Profissional: Home · Solicitações · Clientes · Meus dados
///
/// "Meus dados" é a MESMA ideia nos dois papéis (a própria conta), só que
/// aponta pra telas diferentes -- `PerfilClienteScreen` (cliente) ou
/// `EditarPerfilScreen` (profissional, que antes só era alcançável por um
/// ícone de lápis escondido no AppBar do mapa; agora tem um lugar fixo e
/// óbvio, igual ao "Perfil" que o cliente já tinha). "Clientes" só existe
/// pro profissional -- é uma visão nova (ver `MeusClientesScreen`), sem
/// equivalente pro lado do cliente.
///
/// Usa `IndexedStack` (não troca de widget, só de VISIBILIDADE) para que
/// trocar de aba não jogue fora o estado de cada tela -- ex.: se você
/// rolou o mapa ou já buscou profissionais, isso continua lá ao voltar
/// da aba "Solicitações", em vez de recarregar do zero.
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
    final ehProfissional = papel == Papel.profissional;

    final telas = [
      const MapaScreen(),
      const ServicosScreen(),
      if (ehProfissional) const MeusClientesScreen(),
      ehProfissional ? const EditarPerfilScreen() : const PerfilClienteScreen(),
    ];

    // Se o número de abas mudar (ex.: sessão trocou de papel) e o índice
    // atual ficasse fora da lista, voltamos para a primeira aba em vez de
    // deixar o IndexedStack apontar para um índice inexistente.
    final indiceSeguro = _indiceAtual < telas.length ? _indiceAtual : 0;

    return Scaffold(
      body: IndexedStack(index: indiceSeguro, children: telas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: indiceSeguro,
        onDestinationSelected: (indice) => setState(() => _indiceAtual = indice),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Solicitações',
          ),
          if (ehProfissional)
            const NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Clientes',
            ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Meus dados',
          ),
        ],
      ),
    );
  }
}
