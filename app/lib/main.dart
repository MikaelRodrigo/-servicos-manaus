import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/localizacao_provider.dart';
import 'providers/profissionais_provider.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'widgets/logo_app.dart';

void main() {
  runApp(const ServicosManausApp());
}

class ServicosManausApp extends StatelessWidget {
  const ServicosManausApp({super.key});

  @override
  Widget build(BuildContext context) {
    // `MultiProvider` cria os três "cérebros" de estado do app UMA VEZ, no
    // topo da árvore de widgets, para que QUALQUER tela em qualquer nível
    // consiga acessá-los com `context.watch<X>()` (reconstrói a tela quando
    // X muda) ou `context.read<X>()` (só lê, sem se inscrever para
    // atualizações -- usado dentro de `onPressed`, por exemplo).
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocalizacaoProvider()),
        ChangeNotifierProvider(create: (_) => ProfissionaisProvider()),
      ],
      child: MaterialApp(
        title: 'Serviços Manaus',
        debugShowCheckedModeBanner: false,
        // Todo o visual (cores, raios, sombras, tipografia) vem de um único
        // lugar -- `core/theme/app_theme.dart` -- para que o app inteiro
        // fique consistente sem precisar repetir estilo tela por tela.
        theme: construirTemaClaro(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('pt', 'BR')],
        locale: const Locale('pt', 'BR'),
        home: const _PortaDeEntrada(),
      ),
    );
  }
}

/// Widget raiz que decide QUAL TELA mostrar de acordo com o estado de
/// autenticação -- não usamos rotas nomeadas/Navigator para essa troca de
/// propósito. Login/logout mudam `AuthProvider.status`, e como este widget
/// está inscrito nele (`context.watch`), ele reconstrói sozinho e troca de
/// tela. É mais simples que gerenciar rotas manualmente para um app deste
/// tamanho, e evita a tela de login "vazar" de volta com o botão
/// voltar do sistema depois que a pessoa já está logada.
class _PortaDeEntrada extends StatelessWidget {
  const _PortaDeEntrada();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;

    switch (status) {
      case StatusAuth.carregando:
        // Splash de verdade em vez de um spinner sozinho no branco -- é a
        // PRIMEIRA coisa que qualquer pessoa vê ao abrir o app, antes até de
        // saber se ela vai cair no login ou já direto na área logada. Usa a
        // mesma marca (`LogoApp`) da tela de login, pra não ter dois visuais
        // diferentes de "abertura" no mesmo app.
        return Scaffold(
          backgroundColor: AppColors.fundo,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LogoApp(),
                const SizedBox(height: 20),
                Text('Serviços Manaus', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        );
      case StatusAuth.autenticado:
        return const HomeShell();
      case StatusAuth.naoAutenticado:
        return const LoginScreen();
    }
  }
}
