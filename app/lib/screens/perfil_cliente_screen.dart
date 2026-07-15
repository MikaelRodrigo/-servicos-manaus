import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../data/models/perfil_cliente.dart';
import '../data/services/api_client.dart';
import '../data/services/clientes_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/selecao_foto_perfil.dart';

/// Tela de perfil do PRÓPRIO cliente: mostra foto, nome, e-mail (dados
/// vindos do cadastro, não editáveis aqui) e permite editar contato,
/// endereço fixo e foto de perfil -- visualização e edição na MESMA tela
/// (diferente do profissional, que tem `perfil_profissional_screen.dart`
/// para visualização pública + `editar_perfil_screen.dart` separada para
/// edição; o cliente não tem perfil público, então uma tela só já basta).
class PerfilClienteScreen extends StatefulWidget {
  const PerfilClienteScreen({super.key});

  @override
  State<PerfilClienteScreen> createState() => _PerfilClienteScreenState();
}

class _PerfilClienteScreenState extends State<PerfilClienteScreen> {
  final _contatoController = TextEditingController();
  final _enderecoController = TextEditingController();
  late Future<PerfilCliente> _futuroPerfilAtual;

  PerfilCliente? _perfilCarregado;
  XFile? _fotoEscolhida;
  Uint8List? _bytesFotoEscolhida;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _futuroPerfilAtual = ClientesService.instancia.buscarMeuPerfil();
    _futuroPerfilAtual.then((perfil) {
      if (!mounted) return;
      setState(() {
        _perfilCarregado = perfil;
        _contatoController.text = perfil.contato;
        _enderecoController.text = perfil.endereco ?? '';
      });
    });
  }

  @override
  void dispose() {
    _contatoController.dispose();
    _enderecoController.dispose();
    super.dispose();
  }

  // Escolher origem + selecionar + RECORTAR (1:1) moram todos em
  // `escolherEEditarFotoDePerfil` (widgets/selecao_foto_perfil.dart) --
  // compartilhado com `editar_perfil_screen.dart`, para as duas telas
  // nunca divergirem no fluxo de troca de foto.
  Future<void> _trocarFoto() async {
    final resultado = await escolherEEditarFotoDePerfil(context);
    if (resultado == null || !mounted) return;
    setState(() {
      _fotoEscolhida = resultado.arquivo;
      _bytesFotoEscolhida = resultado.bytes;
    });
  }

  Future<void> _salvar() async {
    final perfilAtual = _perfilCarregado;
    if (perfilAtual == null) return;

    final contato = _contatoController.text.trim();
    final endereco = _enderecoController.text.trim();

    // Só manda o que de fato mudou -- evita um PATCH desnecessário quando
    // a pessoa só abriu a tela e apertou "Salvar" sem alterar nada.
    final contatoMudou = contato.isNotEmpty && contato != perfilAtual.contato;
    final enderecoMudou = endereco != (perfilAtual.endereco ?? '');

    if (!contatoMudou && !enderecoMudou && _fotoEscolhida == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Altere o contato, o endereço ou escolha uma foto antes de salvar.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final perfilAtualizado = await ClientesService.instancia.atualizarMeuPerfil(
        contato: contatoMudou ? contato : null,
        endereco: enderecoMudou ? endereco : null,
        foto: _fotoEscolhida,
      );
      if (!mounted) return;
      final fotoMudou = _fotoEscolhida != null;
      setState(() {
        _perfilCarregado = perfilAtualizado;
        _fotoEscolhida = null;
        _bytesFotoEscolhida = null;
      });
      // Reflete a foto nova no avatar do cabeçalho do mapa na hora, sem
      // precisar deslogar/logar de novo -- ver comentário em
      // `AuthProvider.atualizarFotoPerfil`.
      if (fotoMudou) {
        await context.read<AuthProvider>().atualizarFotoPerfil(perfilAtualizado.urlFotoPerfil);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado!')),
      );
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meu perfil')),
      body: FutureBuilder<PerfilCliente>(
        future: _futuroPerfilAtual,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final mensagem = snapshot.error is ApiException
                ? (snapshot.error as ApiException).mensagem
                : 'Não foi possível carregar seu perfil.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(mensagem, textAlign: TextAlign.center),
              ),
            );
          }

          final perfil = _perfilCarregado ?? snapshot.data!;
          final urlFotoAtual = ApiConfig.urlAbsoluta(perfil.urlFotoPerfil);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: AvatarFotoPerfil(
                  bytesFotoEscolhida: _bytesFotoEscolhida,
                  urlFotoAtual: urlFotoAtual,
                  onTocar: _trocarFoto,
                ),
              ),
              const SizedBox(height: 20),

              Center(
                child: Text(
                  perfil.nomeExibicao,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  perfil.email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                ),
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _contatoController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contato (telefone/WhatsApp)',
                  hintText: '92988887777',
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _enderecoController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Endereço fixo',
                  hintText: 'Rua, número, bairro...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),

              FilledButton.icon(
                onPressed: _salvando ? null : _salvar,
                icon: _salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_salvando ? 'Salvando...' : 'Salvar perfil'),
              ),
            ],
          );
        },
      ),
    );
  }
}
