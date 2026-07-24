import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:provider/provider.dart';
import '../data/models/usuario.dart';
import '../data/models/verificacao_telefone.dart';
import '../data/services/api_client.dart';
import '../data/services/auth_service.dart';
import '../providers/auth_provider.dart';

/// Segundos de espera entre um envio de código e o próximo -- espelha
/// `SEGUNDOS_ENTRE_ENVIOS` em `verificacao-telefone.repository.ts` no
/// backend. Usado só para desenhar o botão "Reenviar" desabilitado com uma
/// contagem regressiva -- o backend recusaria de qualquer forma um reenvio
/// antes disso, mas mostrar isso na tela evita um toque que só ia gerar
/// erro.
const _segundosEntreEnvios = 20;

/// Tela de confirmação do código SMS (migração 17) -- aberta em DOIS
/// momentos diferentes:
///
///   1. Logo depois de um cadastro bem-sucedido (`CadastroScreen`) -- nesse
///      caso `verificacaoInicial` já vem preenchido (o próprio cadastro
///      dispara o primeiro código, ver `AuthService.cadastrarCliente/
///      Profissional`), então a tela não precisa pedir nada, só mostrar o
///      código de teste (modo simulado) se houver.
///
///   2. Quando um login é recusado por telefone não verificado
///      (`LoginScreen`, erro 403 "TELEFONE_NAO_VERIFICADO") -- nesse caso
///      `verificacaoInicial` é `null`: o backend já reenviou um código
///      fresco no MOMENTO do login recusado (ver `auth.routes.ts`), mas a
///      resposta de erro não carrega o resultado desse envio (só
///      `papel`/`usuario_id`) -- a tela simplesmente confia que um SMS
///      já está a caminho.
///
/// Nos dois casos, ao confirmar o código com sucesso, esta tela chama
/// `AuthProvider.login` ela mesma (por isso recebe `email`/`senha`) -- o
/// widget raiz (`main.dart`) reage à mudança de status e troca de tela
/// sozinho, sem navegação manual nenhuma daqui.
class VerificarTelefoneScreen extends StatefulWidget {
  final Papel papel;
  final String usuarioId;
  final String email;
  final String senha;
  final ResultadoEnvioCodigo? verificacaoInicial;

  const VerificarTelefoneScreen({
    super.key,
    required this.papel,
    required this.usuarioId,
    required this.email,
    required this.senha,
    this.verificacaoInicial,
  });

  @override
  State<VerificarTelefoneScreen> createState() => _VerificarTelefoneScreenState();
}

class _VerificarTelefoneScreenState extends State<VerificarTelefoneScreen> {
  final _codigoController = TextEditingController();
  bool _confirmando = false;
  bool _reenviando = false;

  // Código de teste (modo simulado) MAIS RECENTE -- começa com o que veio
  // do cadastro (se veio) e é substituído a cada "Reenviar" bem-sucedido.
  ResultadoEnvioCodigo? _ultimoEnvio;

  Timer? _timerCooldown;
  int _segundosRestantes = _segundosEntreEnvios;

  @override
  void initState() {
    super.initState();
    _ultimoEnvio = widget.verificacaoInicial;
    _iniciarCooldown();
  }

  @override
  void dispose() {
    _timerCooldown?.cancel();
    _codigoController.dispose();
    super.dispose();
  }

  /// Um SMS já foi disparado (pelo cadastro, ou pelo login recusado) antes
  /// desta tela sequer abrir -- o cooldown começa contando na hora, sem
  /// esperar nenhuma ação da pessoa.
  void _iniciarCooldown() {
    _timerCooldown?.cancel();
    setState(() => _segundosRestantes = _segundosEntreEnvios);
    _timerCooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _segundosRestantes--;
        if (_segundosRestantes <= 0) timer.cancel();
      });
    });
  }

  Future<void> _reenviar() async {
    setState(() => _reenviando = true);
    try {
      final resultado = await AuthService.instancia.reenviarCodigoVerificacao(
        papel: widget.papel,
        usuarioId: widget.usuarioId,
      );
      if (!mounted) return;
      setState(() => _ultimoEnvio = resultado);
      _iniciarCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Novo código enviado por SMS.')),
      );
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  Future<void> _confirmar() async {
    final codigo = _codigoController.text.trim();
    if (codigo.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite os 6 dígitos do código.')),
      );
      return;
    }

    setState(() => _confirmando = true);
    try {
      await AuthService.instancia.confirmarCodigoVerificacao(
        papel: widget.papel,
        usuarioId: widget.usuarioId,
        codigo: codigo,
      );
      if (!mounted) return;

      // Telefone confirmado -- agora sim faz login de verdade. Sucesso
      // muda `AuthProvider.status` para `autenticado`, e `main.dart` troca
      // de tela sozinho (ver comentário da classe). Não precisamos fazer
      // nada além de chamar isto.
      final logado = await context.read<AuthProvider>().login(
            papel: widget.papel,
            email: widget.email,
            senha: widget.senha,
          );

      if (!logado && mounted) {
        final erro = context.read<AuthProvider>().erro;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(erro ?? 'Telefone confirmado, mas não foi possível entrar. Tente fazer login de novo.')),
        );
        Navigator.of(context).pop();
      }
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final simulado = _ultimoEnvio?.simulado ?? false;
    final codigoDeTeste = _ultimoEnvio?.codigo;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirme seu telefone')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.sms_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Enviamos um código de 6 dígitos por SMS para o telefone cadastrado.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Digite o código abaixo para confirmar seu número.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),

                // Modo simulado (nenhum provedor de SMS configurado ainda no
                // backend, ver services/sms.ts) -- mostra o código de teste
                // direto na tela, pra dar pra confirmar sem SMS de verdade.
                if (simulado && codigoDeTeste != null) ...[
                  const SizedBox(height: 20),
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
                              const SizedBox(width: 6),
                              Text(
                                'Modo simulado -- sem provedor de SMS configurado',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Código de teste: $codigoDeTeste',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                TextField(
                  controller: _codigoController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                  decoration: const InputDecoration(counterText: ''),
                  onSubmitted: (_) => _confirmar(),
                ),

                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _confirmando ? null : _confirmar,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: _confirmando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirmar'),
                ),

                const SizedBox(height: 12),
                TextButton(
                  onPressed: (_reenviando || _segundosRestantes > 0) ? null : _reenviar,
                  child: _reenviando
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _segundosRestantes > 0
                              ? 'Reenviar código em ${_segundosRestantes}s'
                              : 'Reenviar código',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
