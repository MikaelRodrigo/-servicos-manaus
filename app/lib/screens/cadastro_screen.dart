import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/models/categoria.dart';
import '../data/models/usuario.dart';
import '../data/services/api_client.dart';
import '../data/services/auth_service.dart';
import '../data/services/categorias_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/seletor_categoria_cascata.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key});

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _formKey = GlobalKey<FormState>();

  Papel _tipoConta = Papel.cliente;
  String _tipoPessoa = 'PF';
  DateTime? _dataNascimento;
  bool _enviando = false;

  // Campos comuns.
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirmarSenha = TextEditingController();
  final _contato = TextEditingController();

  // Campos PF.
  final _nome = TextEditingController();
  final _cpf = TextEditingController();

  // Campos PJ.
  final _razaoSocial = TextEditingController();
  final _cnpj = TextEditingController();

  // Categoria de atuação -- só profissional (PF ou PJ, o seletor é o
  // mesmo para os dois). Substitui os antigos campos de texto livre
  // "profissão"/"categoria de atuação" (ver migração 09 no backend).
  List<Categoria> _categorias = [];
  bool _carregandoCategorias = true;
  Categoria? _categoriaSelecionada;
  Subcategoria? _subcategoriaSelecionada;
  String? _erroCategoria;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
  }

  Future<void> _carregarCategorias() async {
    try {
      final categorias = await CategoriasService.instancia.listarCategorias();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _carregandoCategorias = false;
      });
    } on ApiException catch (erro) {
      if (!mounted) return;
      setState(() => _carregandoCategorias = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível carregar as categorias: ${erro.mensagem}')),
      );
    }
  }

  @override
  void dispose() {
    for (final c in [
      _email,
      _senha,
      _confirmarSenha,
      _contato,
      _nome,
      _cpf,
      _razaoSocial,
      _cnpj,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "AAAA-MM-DD" -- o único formato que `dataObrigatoria` (validacao.ts)
  /// aceita no backend. Não uso `intl` só para isso, um `padLeft` resolve.
  String _formatarData(DateTime data) {
    final ano = data.year.toString().padLeft(4, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final dia = data.day.toString().padLeft(2, '0');
    return '$ano-$mes-$dia';
  }

  /// Remove tudo que não é dígito. O backend faz o mesmo (`apenasDigitos`
  /// em validacao.ts) -- fazer aqui também é só para o usuário poder digitar
  /// com pontuação ("123.456.789-00") sem se preocupar.
  String _apenasDigitos(String valor) => valor.replaceAll(RegExp(r'\D'), '');

  Future<void> _selecionarDataNascimento() async {
    final selecionada = await showDatePicker(
      context: context,
      initialDate: DateTime(1995),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Data de nascimento',
    );
    if (selecionada != null) {
      setState(() => _dataNascimento = selecionada);
    }
  }

  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_senha.text != _confirmarSenha.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('As senhas não coincidem.')),
      );
      return;
    }

    if (_tipoConta == Papel.profissional && _tipoPessoa == 'PF' && _dataNascimento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione a data de nascimento.')),
      );
      return;
    }

    // Categoria/subcategoria são obrigatórias para QUALQUER profissional
    // (PF ou PJ) -- é o dado que alimenta a busca por proximidade e o
    // perfil público. Sem seleção completa, nem chega a bater no backend
    // (que também recusaria, já que os dois campos são obrigatórios lá).
    if (_tipoConta == Papel.profissional &&
        (_categoriaSelecionada == null || _subcategoriaSelecionada == null)) {
      setState(() => _erroCategoria = 'Selecione a categoria e a especialidade.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione a categoria e a especialidade de atuação.')),
      );
      return;
    }
    setState(() => _erroCategoria = null);

    setState(() => _enviando = true);

    try {
      final corpo = <String, dynamic>{
        'tipo_pessoa': _tipoPessoa,
        'email': _email.text.trim(),
        'senha': _senha.text,
        'contato': _apenasDigitos(_contato.text),
      };

      if (_tipoConta == Papel.profissional) {
        corpo['categoria_id'] = _categoriaSelecionada!.id;
        corpo['subcategoria_id'] = _subcategoriaSelecionada!.id;
      }

      if (_tipoPessoa == 'PF') {
        corpo['nome'] = _nome.text.trim();
        corpo['cpf'] = _apenasDigitos(_cpf.text);
        if (_tipoConta == Papel.profissional) {
          corpo['data_nascimento'] = _formatarData(_dataNascimento!);
        }
      } else {
        corpo['razao_social'] = _razaoSocial.text.trim();
        corpo['cnpj'] = _apenasDigitos(_cnpj.text);
      }

      if (_tipoConta == Papel.cliente) {
        await AuthService.instancia.cadastrarCliente(corpo);
      } else {
        await AuthService.instancia.cadastrarProfissional(corpo);
      }

      if (!mounted) return;

      // UX: depois de cadastrar, já loga a pessoa direto -- ninguém gosta
      // de preencher formulário e ainda ter que digitar e-mail/senha de
      // novo na sequência.
      final logado = await context.read<AuthProvider>().login(
            papel: _tipoConta,
            email: _email.text.trim(),
            senha: _senha.text,
          );

      if (logado && mounted) {
        // Fecha esta tela. O widget raiz (main.dart) já vai estar
        // mostrando o mapa por trás, porque ele reage ao AuthProvider.
        Navigator.of(context).pop();
      }
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ehProfissional = _tipoConta == Papel.profissional;
    final ehPF = _tipoPessoa == 'PF';

    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<Papel>(
                  segments: const [
                    ButtonSegment(value: Papel.cliente, label: Text('Cliente')),
                    ButtonSegment(value: Papel.profissional, label: Text('Profissional')),
                  ],
                  selected: {_tipoConta},
                  onSelectionChanged: (v) => setState(() => _tipoConta = v.first),
                ),
                const SizedBox(height: 12),

                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'PF', label: Text('Pessoa Física')),
                    ButtonSegment(value: 'PJ', label: Text('Pessoa Jurídica')),
                  ],
                  selected: {_tipoPessoa},
                  onSelectionChanged: (v) => setState(() => _tipoPessoa = v.first),
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'E-mail inválido.' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _senha,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha',
                    helperText: 'Mínimo 8 caracteres, com letras e números.',
                  ),
                  validator: (v) => (v == null || v.length < 8) ? 'Senha muito curta.' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _confirmarSenha,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirmar senha'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Confirme a senha.' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _contato,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp / telefone',
                    hintText: '92988887777',
                  ),
                  validator: (v) =>
                      (v == null || _apenasDigitos(v).length < 10) ? 'Telefone inválido.' : null,
                ),
                const SizedBox(height: 12),

                if (ehPF) ...[
                  TextFormField(
                    controller: _nome,
                    decoration: const InputDecoration(labelText: 'Nome completo'),
                    validator: (v) => (v == null || v.trim().length < 3) ? 'Informe seu nome.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cpf,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CPF'),
                    validator: (v) =>
                        (v == null || _apenasDigitos(v).length != 11) ? 'CPF deve ter 11 dígitos.' : null,
                  ),
                  if (ehProfissional) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _selecionarDataNascimento,
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(
                        _dataNascimento == null
                            ? 'Selecionar data de nascimento'
                            : 'Nascimento: ${_formatarData(_dataNascimento!)}',
                      ),
                    ),
                  ],
                ] else ...[
                  TextFormField(
                    controller: _razaoSocial,
                    decoration: const InputDecoration(labelText: 'Razão social'),
                    validator: (v) =>
                        (v == null || v.trim().length < 2) ? 'Informe a razão social.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cnpj,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'CNPJ'),
                    validator: (v) =>
                        (v == null || _apenasDigitos(v).length != 14) ? 'CNPJ deve ter 14 dígitos.' : null,
                  ),
                ],

                // Categoria de atuação -- comum a PF e PJ, por isso mora
                // FORA do if/else acima. Único seletor em cascata, sem
                // texto livre (ver widgets/seletor_categoria_cascata.dart).
                if (ehProfissional) ...[
                  const SizedBox(height: 12),
                  _carregandoCategorias
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : SeletorCategoriaCascata(
                          categorias: _categorias,
                          categoriaSelecionada: _categoriaSelecionada,
                          subcategoriaSelecionada: _subcategoriaSelecionada,
                          errorText: _erroCategoria,
                          onCategoriaAlterada: (categoria) {
                            setState(() {
                              _categoriaSelecionada = categoria;
                              _erroCategoria = null;
                            });
                          },
                          onSubcategoriaAlterada: (subcategoria) {
                            setState(() {
                              _subcategoriaSelecionada = subcategoria;
                              _erroCategoria = null;
                            });
                          },
                        ),
                ],

                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _enviando ? null : _cadastrar,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: _enviando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Criar conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
