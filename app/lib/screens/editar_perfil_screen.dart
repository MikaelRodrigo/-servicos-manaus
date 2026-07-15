import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/config/api_config.dart';
import '../data/models/categoria.dart';
import '../data/models/endereco_cep.dart';
import '../data/models/perfil_profissional.dart';
import '../data/services/api_client.dart';
import '../data/services/categorias_service.dart';
import '../data/services/cep_service.dart';
import '../data/services/profissionais_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/selecao_foto_perfil.dart';
import '../widgets/selecao_tags_subcategorias.dart';

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

  // Autofill em tempo real do CEP: dispara ~500ms depois que o usuário
  // termina de digitar os 8 dígitos (debounce -- evita bater na API a cada
  // tecla). `_enderecoPreview` é o endereço RECÉM-CONSULTADO (ainda não
  // salvo, só uma prévia); é um conceito diferente de `_enderecoAtualExibicao`
  // acima, que é o endereço já GRAVADO no perfil.
  Timer? _debounceCep;
  EnderecoPorCep? _enderecoPreview;
  bool _consultandoCep = false;
  String? _erroCep;

  // Especialidades (tags de subcategoria, migração 11 no backend) -- lista
  // fixa (`_categorias`) alimenta a busca do `SelecaoTagsSubcategorias`;
  // `_tags` são as especialidades que o profissional JÁ TEM agora.
  // Diferente do CEP/descrição acima, tags não fazem parte do "Salvar
  // perfil" em lote -- cada adição/remoção chama a API na hora (ver
  // `_adicionarTag`/`_removerTag`), então o estado aqui já reflete sempre o
  // que está gravado no banco.
  List<Categoria> _categorias = [];
  bool _carregandoCategorias = true;
  List<TagSubcategoria> _tags = [];

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
        _tags = perfil.subcategorias;
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

  /// Chamado pelo `SelecaoTagsSubcategorias` quando o profissional confirma
  /// uma especialidade nova (Enter ou toque no dropdown). Deixa
  /// `ApiException` escapar de propósito -- é o próprio widget quem mostra
  /// o `SnackBar` de erro (ver `_confirmarAdicao` lá).
  Future<void> _adicionarTag(Subcategoria subcategoria) async {
    final tags = await ProfissionaisService.instancia.adicionarTag(subcategoria.id);
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  /// Idem, para remoção -- inclusive o erro de "não pode remover a última",
  /// que o backend recusa com 400 (vira `ApiException`, mostrado pelo
  /// widget).
  Future<void> _removerTag(TagSubcategoria tag) async {
    final tags = await ProfissionaisService.instancia.removerTag(tag.id);
    if (!mounted) return;
    setState(() => _tags = tags);
  }

  @override
  void dispose() {
    _debounceCep?.cancel();
    _descricaoController.dispose();
    _cepController.dispose();
    super.dispose();
  }

  /// Chamado a cada tecla no campo de CEP. Só dispara a consulta de verdade
  /// quando: (1) já tem os 8 dígitos completos, e (2) passou meio segundo
  /// sem nova tecla (debounce -- evita uma chamada de API por dígito
  /// enquanto a pessoa ainda está digitando). Apagar/editar o CEP depois de
  /// já ter um preview limpa o preview na hora, sem esperar debounce nenhum.
  void _aoDigitarCep(String valor) {
    _debounceCep?.cancel();

    if (valor.length != 8) {
      setState(() {
        _enderecoPreview = null;
        _erroCep = null;
        _consultandoCep = false;
      });
      return;
    }

    setState(() {
      _consultandoCep = true;
      _erroCep = null;
    });

    _debounceCep = Timer(const Duration(milliseconds: 500), () async {
      try {
        final endereco = await CepService.instancia.buscarEndereco(valor);
        if (!mounted || _cepController.text.trim() != valor) return;
        setState(() {
          _enderecoPreview = endereco;
          _consultandoCep = false;
        });
      } on ApiException catch (erro) {
        if (!mounted || _cepController.text.trim() != valor) return;
        setState(() {
          _enderecoPreview = null;
          _erroCep = erro.mensagem;
          _consultandoCep = false;
        });
      }
    });
  }

  // Escolher origem + selecionar + RECORTAR (1:1) moram todos em
  // `escolherEEditarFotoDePerfil` (widgets/selecao_foto_perfil.dart) --
  // compartilhado com `perfil_cliente_screen.dart`, para as duas telas
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
    final descricao = _descricaoController.text.trim();
    final cep = _cepController.text.trim();

    if (descricao.isEmpty && cep.isEmpty && _fotoEscolhida == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Altere a descrição, informe um CEP ou escolha uma foto antes de salvar.'),
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

    setState(() => _salvando = true);
    try {
      final perfilAtualizado = await ProfissionaisService.instancia.atualizarMeuPerfil(
        descricao: descricao.isNotEmpty ? descricao : null,
        cep: cep.isNotEmpty ? cep : null,
        foto: _fotoEscolhida,
      );
      if (!mounted) return;
      setState(() {
        _enderecoAtualExibicao = perfilAtualizado.enderecoAtuacao;
        _cepController.clear();
        _enderecoPreview = null;
        _erroCep = null;
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
                child: AvatarFotoPerfil(
                  bytesFotoEscolhida: _bytesFotoEscolhida,
                  urlFotoAtual: urlFotoAtual,
                  onTocar: _trocarFoto,
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
                onChanged: _aoDigitarCep,
                decoration: InputDecoration(
                  labelText: 'CEP',
                  hintText: 'Ex.: 69010030',
                  helperText: 'Define onde você aparece no mapa para os clientes.',
                  suffixIcon: _consultandoCep
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              // Preview do endereço encontrado para o CEP recém-digitado --
              // aparece ANTES de salvar, como confirmação visual imediata
              // (autofill em tempo real). Erro (CEP inexistente, por
              // exemplo) some sozinho assim que a pessoa edita o campo de
              // novo (ver `_aoDigitarCep`).
              if (_erroCep != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _erroCep!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  ],
                ),
              ] else if (_enderecoPreview != null && _enderecoPreview!.textoFormatado.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _enderecoPreview!.textoFormatado,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
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

              // Especialidades -- cada box é uma tag adicionada/removida NA
              // HORA (não faz parte do "Salvar perfil" em lote abaixo, ver
              // `_adicionarTag`/`_removerTag`). Sem "categoria única" mais
              // nesta tela: o profissional pode ter quantas especialidades
              // quiser, e aparece na busca de QUALQUER uma delas.
              Text('Especialidades', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _carregandoCategorias
                  ? const Center(child: CircularProgressIndicator())
                  : SelecaoTagsSubcategorias(
                      categorias: _categorias,
                      tagsAtuais: _tags,
                      aoAdicionar: _adicionarTag,
                      aoRemover: _removerTag,
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
