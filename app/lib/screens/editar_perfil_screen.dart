import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../data/models/categoria.dart';
import '../data/models/perfil_profissional.dart';
import '../data/services/api_client.dart';
import '../data/services/categorias_service.dart';
import '../data/services/profissionais_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/seletor_categoria_cascata.dart';

/// Tela em que o PRÓPRIO profissional edita seu perfil público: foto,
/// descrição ("sobre mim") e CEP. É o que alimenta os campos que antes
/// ficavam sempre `null` -- sem esta tela, ninguém teria como preencher
/// `descricao`/`url_foto_perfil` depois do cadastro, nem aparecer na busca
/// por proximidade do mapa (que depende de latitude/longitude).
class EditarPerfilScreen extends StatefulWidget {
  const EditarPerfilScreen({super.key});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  final _descricaoController = TextEditingController();
  final _cepController = TextEditingController();
  late Future<PerfilProfissional> _futuroPerfilAtual;

  XFile? _fotoEscolhida;
  Uint8List? _bytesFotoEscolhida;
  String? _urlFotoAtual;

  // Localização/endereço JÁ GRAVADOS -- mostrados como texto informativo
  // ("Localização atual: ..."), nunca pré-preenchidos no campo de CEP. O
  // campo de CEP é só de ENTRADA (mesmo espírito do seletor de foto: ele
  // não mostra a foto atual dentro do próprio botão de escolher foto nova,
  // mostra ao lado). Evita reenviar sempre o mesmo CEP sem querer.
  String? _enderecoAtualExibicao;
  bool _salvando = false;

  // Categoria/subcategoria -- mesmo espírito do CEP acima: o seletor começa
  // sempre VAZIO (nunca pré-selecionado com a categoria atual), e o valor
  // atual só aparece como texto informativo ao lado. Só troca de verdade
  // quando a pessoa escolhe os dois níveis de novo -- ver `_salvar`.
  List<Categoria> _categorias = [];
  bool _carregandoCategorias = true;
  Categoria? _categoriaSelecionada;
  Subcategoria? _subcategoriaSelecionada;
  String? _erroCategoria;
  String? _categoriaAtualExibicao;

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
        _enderecoAtualExibicao = perfil.enderecoAtuacao;
        _categoriaAtualExibicao = perfil.atuacao != null
            ? (perfil.categoria != null ? '${perfil.atuacao} (em: ${perfil.categoria})' : perfil.atuacao)
            : null;
      });
    });
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
    _descricaoController.dispose();
    _cepController.dispose();
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
    final cep = _cepController.text.trim();
    final categoria = _categoriaSelecionada;
    final subcategoria = _subcategoriaSelecionada;

    if (descricao.isEmpty && cep.isEmpty && _fotoEscolhida == null && categoria == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Altere a descrição, informe um CEP, escolha uma foto ou uma categoria antes de salvar.',
          ),
        ),
      );
      return;
    }

    // Confere 8 dígitos ANTES de bater no backend -- feedback imediato em
    // vez de esperar a resposta de um CEP obviamente incompleto/errado.
    if (cep.isNotEmpty && cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O CEP precisa ter 8 dígitos.')),
      );
      return;
    }

    // Categoria/subcategoria só existem JUNTAS -- o seletor já força isso na
    // UI (não dá pra "salvar" categoria sem escolher a especialidade), mas
    // confere de novo aqui, mesmo espírito da validação de CEP acima.
    if (categoria != null && subcategoria == null) {
      setState(() => _erroCategoria = 'Escolha também a especialidade.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha também a especialidade dentro da categoria.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final perfilAtualizado = await ProfissionaisService.instancia.atualizarMeuPerfil(
        descricao: descricao.isNotEmpty ? descricao : null,
        cep: cep.isNotEmpty ? cep : null,
        categoriaId: categoria?.id,
        subcategoriaId: subcategoria?.id,
        foto: _fotoEscolhida,
      );
      if (!mounted) return;
      setState(() {
        _enderecoAtualExibicao = perfilAtualizado.enderecoAtuacao;
        _cepController.clear();
        _categoriaAtualExibicao = perfilAtualizado.atuacao != null
            ? (perfilAtualizado.categoria != null
                ? '${perfilAtualizado.atuacao} (em: ${perfilAtualizado.categoria})'
                : perfilAtualizado.atuacao)
            : null;
        _categoriaSelecionada = null;
        _subcategoriaSelecionada = null;
        _erroCategoria = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cep.isNotEmpty && perfilAtualizado.enderecoAtuacao != null
                ? 'Perfil atualizado! Localização: ${perfilAtualizado.enderecoAtuacao}'
                : 'Perfil atualizado!',
          ),
        ),
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
              const SizedBox(height: 16),

              // CEP define onde o profissional aparece na busca por
              // proximidade do mapa -- ver PATCH /profissionais/me no
              // backend, que geocodifica o CEP em latitude/longitude.
              TextField(
                controller: _cepController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'CEP',
                  hintText: 'Ex.: 69010030',
                  helperText: 'Define onde você aparece no mapa para os clientes.',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_enderecoAtualExibicao != null && _enderecoAtualExibicao!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Localização atual: $_enderecoAtualExibicao',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // Categoria/subcategoria -- mesmo espírito do CEP acima: o
              // seletor abaixo começa sempre VAZIO; a categoria/especialidade
              // atual aparece só como texto informativo. Só troca de verdade
              // escolhendo os dois níveis de novo (ver `_salvar`).
              _carregandoCategorias
                  ? const Center(child: CircularProgressIndicator())
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
              if (_categoriaAtualExibicao != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.category_outlined, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Categoria atual: $_categoriaAtualExibicao',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              ],
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
