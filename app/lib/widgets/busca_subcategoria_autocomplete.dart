import 'package:flutter/material.dart';
import '../data/models/categoria.dart';

/// Par (subcategoria, categoria-pai) -- é o item que efetivamente aparece
/// no dropdown de busca. Guardar os dois juntos é o que permite mostrar
/// "Eletricista (em: Manutenção e Reforma)" sem precisar procurar a
/// categoria de novo toda vez que uma opção é exibida.
class _ResultadoBusca {
  final Subcategoria subcategoria;
  final Categoria categoria;

  const _ResultadoBusca({required this.subcategoria, required this.categoria});
}

/// Campo de busca ÚNICO que filtra em TEMPO REAL todas as subcategorias de
/// TODAS as categorias ao mesmo tempo -- sem precisar escolher a categoria
/// pai primeiro. Diferente do `SeletorCategoriaCascata` (usado no cadastro
/// do profissional, em duas etapas): este é o componente de busca da tela
/// do CLIENTE (mapa) -- ele já sabe o que procura ("eletricista"), não quer
/// navegar categoria por categoria.
///
/// Sem texto livre: a digitação só FILTRA a lista já carregada (`categorias`,
/// buscada uma única vez do backend -- ver `CategoriasService`/`mapa_screen.dart`).
/// O valor que de fato é usado para buscar no mapa só existe depois que a
/// pessoa TOCA numa opção do dropdown -- nunca a partir do texto digitado.
///
/// Performance: a lista "achatada" (toda subcategoria + sua categoria-pai
/// juntas, prontas para exibir e comparar) é montada UMA VEZ (`initState`/
/// `didUpdateWidget`, não a cada tecla) a partir dos dados já carregados em
/// memória -- cada letra digitada só filtra um array pequeno (~60 itens),
/// sem nenhuma chamada de rede.
class BuscaSubcategoriaAutocomplete extends StatefulWidget {
  final List<Categoria> categorias;
  final Subcategoria? subcategoriaSelecionada;
  final ValueChanged<Subcategoria?> onSelecionada;
  final String hintText;

  const BuscaSubcategoriaAutocomplete({
    super.key,
    required this.categorias,
    required this.subcategoriaSelecionada,
    required this.onSelecionada,
    this.hintText = 'Buscar especialidade (ex: eletricista)',
  });

  @override
  State<BuscaSubcategoriaAutocomplete> createState() => _BuscaSubcategoriaAutocompleteState();
}

class _BuscaSubcategoriaAutocompleteState extends State<BuscaSubcategoriaAutocomplete> {
  late List<_ResultadoBusca> _todasSubcategorias = _achatar(widget.categorias);

  static List<_ResultadoBusca> _achatar(List<Categoria> categorias) {
    return [
      for (final categoria in categorias)
        for (final subcategoria in categoria.subcategorias)
          _ResultadoBusca(subcategoria: subcategoria, categoria: categoria),
    ];
  }

  @override
  void didUpdateWidget(covariant BuscaSubcategoriaAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Só reprocessa se a LISTA em si mudou (ex.: categorias recarregadas) --
    // não a cada rebuild por causa de outro estado do widget pai.
    if (!identical(oldWidget.categorias, widget.categorias)) {
      _todasSubcategorias = _achatar(widget.categorias);
    }
  }

  static const _comAcento = 'áàâãäéèêëíìîïóòôõöúùûüç';
  static const _semAcento = 'aaaaaeeeeiiiiooooouuuuc';

  /// Minúsculo e sem acento -- assim "ele" acha "Eletricista" e também
  /// "Depiladora" bate buscando "depilad" sem se importar com maiúscula.
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

  /// Requisito 1 e 2: busca GLOBAL (percorre todos os arrays de subcategorias
  /// de todas as categorias, mesmo sem categoria pai escolhida) + resultado
  /// em tempo real para quem CONTÉM ou COMEÇA com o termo digitado.
  Iterable<_ResultadoBusca> _buscar(String termo) {
    final termoNormalizado = _normalizar(termo.trim());
    if (termoNormalizado.isEmpty) return const Iterable.empty();

    final comecaCom = <_ResultadoBusca>[];
    final contem = <_ResultadoBusca>[];

    for (final resultado in _todasSubcategorias) {
      final nomeNormalizado = _normalizar(resultado.subcategoria.nome);
      if (nomeNormalizado.startsWith(termoNormalizado)) {
        comecaCom.add(resultado);
      } else if (nomeNormalizado.contains(termoNormalizado)) {
        contem.add(resultado);
      }
    }

    // Prioriza quem COMEÇA com o termo (mais relevante) antes de quem só
    // CONTÉM -- ex.: digitar "ele" mostra "Eletricista" antes de "Design de
    // Sobrancelhas" (que só contém "ele" no meio da palavra).
    return [...comecaCom, ...contem];
  }

  @override
  Widget build(BuildContext context) {
    // Requisito 4: escolha "congelada" em Chip -- e some o campo de busca
    // enquanto ela existir. Tocar no "x" volta ao modo de busca.
    if (widget.subcategoriaSelecionada != null) {
      return InputChip(
        avatar: const Icon(Icons.search, size: 18),
        label: Text(widget.subcategoriaSelecionada!.nome),
        onDeleted: () => widget.onSelecionada(null),
      );
    }

    // `LayoutBuilder` para o dropdown nascer com a MESMA largura do campo,
    // em vez de um tamanho fixo -- é o que torna o componente responsivo em
    // telas estreitas (celular) e largas (tablet/web) sem cálculo manual.
    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraDoCampo = constraints.maxWidth;

        return Autocomplete<_ResultadoBusca>(
          displayStringForOption: (resultado) => resultado.subcategoria.nome,
          optionsBuilder: (textEditingValue) => _buscar(textEditingValue.text),
          // Requisito 5: só existe seleção quando a pessoa TOCA numa opção
          // do dropdown -- nunca a partir do texto que ela digitou.
          onSelected: (resultado) => widget.onSelecionada(resultado.subcategoria),
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Icon(Icons.search),
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
                          // Requisito 3: hierarquia contextual -- mostra a
                          // categoria pai junto do resultado.
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
    );
  }
}
