import 'package:flutter/material.dart';
import '../data/models/categoria.dart';
import '../data/services/api_client.dart' show ApiException;

/// Par (subcategoria, categoria-pai) que aparece no dropdown de busca --
/// mesma ideia de `_ResultadoBusca` em `busca_subcategoria_autocomplete.dart`,
/// mas privada desta classe: as duas telas não precisam compartilhar o tipo,
/// só o "jeito" da busca (normalizar, começa-com antes de contém).
class _ResultadoBusca {
  final Subcategoria subcategoria;
  final Categoria categoria;

  const _ResultadoBusca({required this.subcategoria, required this.categoria});
}

/// Widget de "Adicionar Categoria": mostra as tags de especialidade ATUAIS
/// do profissional como boxes removíveis (com um fade-in suave quando um box
/// novo aparece), seguido de um campo de busca que fica SEMPRE visível --
/// diferente do `BuscaSubcategoriaAutocomplete` (que "congela" num Chip
/// único e some o campo), aqui o campo nunca desaparece: o profissional
/// pode ter várias especialidades, então depois de adicionar uma, o campo
/// limpa e continua ali, pronto para a próxima.
///
/// Este widget não fala com a API diretamente -- quem chama decide isso via
/// `aoAdicionar`/`aoRemover` (ambos `Future<void> Function(...)`, chamados
/// pela tela que already tem acesso ao `ProfissionaisService` e sabe
/// atualizar o estado dela mesma). Se a chamada lançar `ApiException`
/// (ex.: "última especialidade não pode ser removida"), este widget mostra
/// a mensagem num `SnackBar` e desfaz o estado de carregamento -- a tela
/// não precisa se preocupar com isso.
class SelecaoTagsSubcategorias extends StatefulWidget {
  /// Árvore completa categoria -> subcategorias (o mesmo `GET /categorias`
  /// já usado pelo `SeletorCategoriaCascata`/`BuscaSubcategoriaAutocomplete`)
  /// -- é dela que a busca filtra as opções.
  final List<Categoria> categorias;

  /// Tags que o profissional JÁ TEM agora -- vem do perfil (`buscarPerfilPublico`)
  /// ou da resposta das próprias chamadas de adicionar/remover.
  final List<TagSubcategoria> tagsAtuais;

  final Future<void> Function(Subcategoria subcategoria) aoAdicionar;
  final Future<void> Function(TagSubcategoria tag) aoRemover;

  final String hintText;

  const SelecaoTagsSubcategorias({
    super.key,
    required this.categorias,
    required this.tagsAtuais,
    required this.aoAdicionar,
    required this.aoRemover,
    this.hintText = 'Adicionar categoria (ex: eletricista)',
  });

  @override
  State<SelecaoTagsSubcategorias> createState() => _SelecaoTagsSubcategoriasState();
}

class _SelecaoTagsSubcategoriasState extends State<SelecaoTagsSubcategorias> {
  late List<_ResultadoBusca> _todasSubcategorias = _achatar(widget.categorias);

  /// `true` enquanto uma chamada de ADICIONAR está em voo -- desabilita o
  /// campo pra evitar dois cliques mandando a mesma tag duas vezes.
  bool _adicionando = false;

  /// Qual tag está sendo REMOVIDA agora (o id dela) -- só essa mostra o
  /// spinner no lugar do "x"; as outras continuam clicáveis normalmente.
  int? _removendoId;

  /// O `TextEditingController` que o `Autocomplete` cria e gerencia
  /// internamente (capturado dentro de `fieldViewBuilder`, que roda a cada
  /// build -- mas a INSTÂNCIA do controller é sempre a mesma, então guardar
  /// a referência aqui é seguro). É o que permite limpar o campo depois de
  /// cada seleção, em `_confirmarAdicao`, sem precisar de um controller
  /// próprio desta classe.
  TextEditingController? _campoController;

  static List<_ResultadoBusca> _achatar(List<Categoria> categorias) {
    return [
      for (final categoria in categorias)
        for (final subcategoria in categoria.subcategorias)
          _ResultadoBusca(subcategoria: subcategoria, categoria: categoria),
    ];
  }

  @override
  void didUpdateWidget(covariant SelecaoTagsSubcategorias oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.categorias, widget.categorias)) {
      _todasSubcategorias = _achatar(widget.categorias);
    }
  }

  static const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüç';
  static const _semAcento = 'aaaaaeeeeiiiiooooouuuuc';

  static String _normalizar(String texto) {
    final minusculo = texto.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in minusculo.runes) {
      final caractere = String.fromCharCode(rune);
      final indice = _comAcento.indexOf(caractere);
      buffer.write(indice == -1 ? caractere : _semAcento[indice]);
    }
    return buffer.toString();
  }

  /// Busca GLOBAL (todas as categorias) igual ao `BuscaSubcategoriaAutocomplete`
  /// -- só que aqui, além disso, EXCLUI as subcategorias que o profissional
  /// já tem como tag (não faz sentido oferecer de novo algo que já virou box).
  Iterable<_ResultadoBusca> _buscar(String termo) {
    final termoNormalizado = _normalizar(termo.trim());
    if (termoNormalizado.isEmpty) return const Iterable.empty();

    final idsJaAdicionados = widget.tagsAtuais.map((tag) => tag.id).toSet();

    final comecaCom = <_ResultadoBusca>[];
    final contem = <_ResultadoBusca>[];

    for (final resultado in _todasSubcategorias) {
      if (idsJaAdicionados.contains(resultado.subcategoria.id)) continue;

      final nomeNormalizado = _normalizar(resultado.subcategoria.nome);
      if (nomeNormalizado.startsWith(termoNormalizado)) {
        comecaCom.add(resultado);
      } else if (nomeNormalizado.contains(termoNormalizado)) {
        contem.add(resultado);
      }
    }

    return [...comecaCom, ...contem];
  }

  Future<void> _confirmarAdicao(Subcategoria subcategoria) async {
    _campoController?.clear();
    setState(() => _adicionando = true);
    try {
      await widget.aoAdicionar(subcategoria);
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _adicionando = false);
    }
  }

  /// Enter no campo: confirma a PRIMEIRA sugestão que bate com o texto
  /// digitado (o "topo" da mesma ordenação usada no dropdown -- começa-com
  /// antes de contém). Sem sugestão nenhuma, não faz nada -- não existe
  /// "criar categoria nova digitando", a lista é sempre fechada.
  void _aoSubmeterCampo(String valor) {
    final sugestoes = _buscar(valor).toList();
    if (sugestoes.isEmpty) return;
    _confirmarAdicao(sugestoes.first.subcategoria);
  }

  Future<void> _remover(TagSubcategoria tag) async {
    setState(() => _removendoId = tag.id);
    try {
      await widget.aoRemover(tag);
    } on ApiException catch (erro) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro.mensagem)));
      }
    } finally {
      if (mounted) setState(() => _removendoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tagsAtuais.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in widget.tagsAtuais)
                // `ValueKey` por tag.id: quando uma tag NOVA entra na lista,
                // o Flutter cria uma instância de widget nova para ela (uma
                // key que ele nunca viu) -- é isso que faz o
                // `TweenAnimationBuilder` rodar a animação de entrada só na
                // tag recém-adicionada, nunca nas que já estavam lá.
                TweenAnimationBuilder<double>(
                  key: ValueKey(tag.id),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  builder: (context, valor, filho) => Opacity(
                    opacity: valor,
                    child: Transform.scale(scale: 0.85 + (0.15 * valor), child: filho),
                  ),
                  child: InputChip(
                    label: Text(tag.nome),
                    avatar: const Icon(Icons.category_outlined, size: 18),
                    deleteIcon: _removendoId == tag.id
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close, size: 18),
                    onDeleted: _removendoId == null ? () => _remover(tag) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],

        // Campo SEMPRE visível -- diferente do BuscaSubcategoriaAutocomplete,
        // aqui não existe "estado congelado": depois de adicionar, o campo
        // limpa e continua pronto para a próxima especialidade.
        LayoutBuilder(
          builder: (context, constraints) {
            final larguraDoCampo = constraints.maxWidth;

            return Autocomplete<_ResultadoBusca>(
              displayStringForOption: (resultado) => resultado.subcategoria.nome,
              optionsBuilder: (textEditingValue) => _buscar(textEditingValue.text),
              onSelected: (resultado) => _confirmarAdicao(resultado.subcategoria),
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                // Guarda a referência: é o MESMO controller a cada rebuild
                // (o Autocomplete o mantém internamente), então isto deixa
                // `_confirmarAdicao` limpar o campo depois de cada seleção
                // sem precisar de um controller próprio desta classe.
                _campoController = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_adicionando,
                  onSubmitted: (valor) {
                    _aoSubmeterCampo(valor);
                    controller.clear();
                  },
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    prefixIcon: const Icon(Icons.add_circle_outline),
                    suffixIcon: _adicionando
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    isDense: true,
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final opcoes = options.toList();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: SizedBox(
                        width: larguraDoCampo,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: opcoes.length,
                          itemBuilder: (context, indice) {
                            final resultado = opcoes[indice];
                            return ListTile(
                              dense: true,
                              title: Text(resultado.subcategoria.nome),
                              subtitle: Text('em: ${resultado.categoria.nome}'),
                              onTap: () => onSelected(resultado),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
