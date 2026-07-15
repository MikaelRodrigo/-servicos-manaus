import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models/usuario.dart';
import '../providers/auth_provider.dart';
import '../widgets/logo_app.dart';
import 'cadastro_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  Papel _papel = Papel.cliente;
  bool _senhaVisivel = false;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    // Some a mensagem de erro anterior antes de tentar de novo, senão o
    // usuário pode achar que o erro velho ainda se aplica.
    context.read<AuthProvider>().limparErro();

    if (!_formKey.currentState!.validate()) return;

    final sucesso = await context.read<AuthProvider>().login(
          papel: _papel,
          email: _emailController.text.trim(),
          senha: _senhaController.text,
        );

    // Não precisamos navegar manualmente para a próxima tela: main.dart
    // observa AuthProvider.status e troca de tela sozinho quando o login
    // muda o status para `autenticado`. Isso evita "esquecer" de navegar
    // em algum outro lugar que também chame login().
    if (!sucesso && mounted) {
      final erro = context.read<AuthProvider>().erro;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro ?? 'Não foi possível entrar.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final enviando = context.watch<AuthProvider>().enviando;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LogoApp(tamanho: 84),
                  const SizedBox(height: 12),
                  Text(
                    'Serviços Manaus',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 32),

                  // Alterna entre logar como CLIENTE ou como PROFISSIONAL.
                  // É obrigatório mandar isso para a API (POST /auth/login
                  // exige o campo "papel") porque a mesma pessoa pode ter
                  // conta nas duas tabelas com o mesmo e-mail.
                  SegmentedButton<Papel>(
                    segments: const [
                      ButtonSegment(
                        value: Papel.cliente,
                        label: Text('Sou cliente'),
                        icon: Icon(Icons.person_outline),
                      ),
                      ButtonSegment(
                        value: Papel.profissional,
                        label: Text('Sou profissional'),
                        icon: Icon(Icons.engineering_outlined),
                      ),
                    ],
                    selected: {_papel},
                    onSelectionChanged: (novoValor) {
                      setState(() => _papel = novoValor.first);
                    },
                  ),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return 'Informe seu e-mail.';
                      }
                      if (!valor.contains('@')) {
                        return 'E-mail inválido.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _senhaController,
                    obscureText: !_senhaVisivel,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_senhaVisivel ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
                      ),
                    ),
                    validator: (valor) {
                      if (valor == null || valor.isEmpty) {
                        return 'Informe sua senha.';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _entrar(),
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: enviando ? null : _entrar,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: enviando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: 12),

                  TextButton(
                    onPressed: enviando
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const CadastroScreen()),
                            ),
                    child: const Text('Não tem conta? Cadastre-se'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
