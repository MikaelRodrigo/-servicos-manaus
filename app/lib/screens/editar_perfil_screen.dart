import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../data/models/perfil_profissional.dart';
import '../data/services/api_client.dart';
import '../data/services/profissionais_service.dart';
import '../providers/auth_provider.dart';

/// Tela em que o PRÓPRIO profissional edita seu perfil público: foto e
/// descrição ("sobre mim"). É o que alimenta os campos que antes ficavam
/// sempre `null` -- sem esta tela, ninguém teria como preencher
/// `descricao`/`url_foto_perfil` depois do cadastro.
class EditarPerfilScreen extends StatefulWidget {
  const EditarPerfilScreen({super.key});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  final _descricaoController = TextEditingController();
  late Future<PerfilProfissional> _futuroPerfilAtual;

  XFile? _fotoEscolhida;
  Uint8List? _bytesFotoEscolhida;
  String? _urlFotoAtual;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final meuId = context.read<AuthProvider>().usuario!.id;
    _futuroPerfilAtual = ProfissionaisService.instancia.buscarPerfilPublico(meuId);
    _futuroPerfilAtual.then((perfil) {
      if (!mounted) return;
      setState(() {
        _descricaoController.text = perfil.descricao ?? '';
        _urlFotoAtual = perfil.urlFotoPerfil;
      });
    });
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (contextoFolha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(contextoFolha).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(contextoFolha).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (origem == null) return;

    final arquivo = await ImagePicker().pickImage(source: origem, imageQuality: 85);
    if (arquivo == null) return;

    final bytes = await arquivo.readAsBytes();
    if (!mounted) return;
    setState(() {
      _fotoEscolhida = arquivo;
      _bytesFotoEscolhida = bytes;
    });
  }

  Future<void> _salvar() async {
    final descricao = _descricaoController.text.trim();

    if (descricao.isEmpty && _fotoEscolhida == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Altere a descrição ou escolha uma foto antes de salvar.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final perfilAtualizado = await ProfissionaisService.instancia.atualizarMeuPerfil(
        descricao: descricao.isNotEmpty ? descricao : null,
        foto: _fotoEscolhida,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil atualizado!')),
      );
      Navigator.of(context).pop(perfilAtualizado);
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
      appBar: AppBar(title: const Text('Editar meu perfil')),
      body: FutureBuilder<PerfilProfissional>(
        future: _futuroPerfilAtual,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final urlFotoAtual = ApiConfig.urlAbsoluta(_urlFotoAtual);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _escolherFoto,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 56,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage: _bytesFotoEscolhida != null
                            ? MemoryImage(_bytesFotoEscolhida!)
                            : (urlFotoAtual != null ? NetworkImage(urlFotoAtual) : null)
                                as ImageProvider?,
                        child: _bytesFotoEscolhida == null && urlFotoAtual == null
                            ? const Icon(Icons.person, size: 56, color: Colors.white)
                            : null,
                      ),
                      const CircleAvatar(
                        radius: 18,
                        child: Icon(Icons.camera_alt, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _escolherFoto,
                  child: const Text('Trocar foto de perfil'),
                ),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _descricaoController,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Sobre mim',
                  hintText: 'Conte um pouco sobre sua experiência e seus serviços...',
                  border: OutlineInputBorder(),
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
