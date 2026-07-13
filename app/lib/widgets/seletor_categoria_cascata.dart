import 'package:flutter/material.dart';
import '../data/models/categoria.dart';

/// Campo ÚNICO que funciona como um seletor em cascata categoria ->
/// subcategoria, com as duas escolhas "congeladas" dentro do próprio campo
/// em formato de Chip. Não existe campo de texto livre neste widget -- a
/// pessoa só termina uma seleção tocando num item de uma lista fechada (a
/// busca dentro da folha de baixo só FILTRA essa lista, nunca vira um valor
/// digitado à mão). É o que garante a integridade dos dados no banco: todo
/// valor salvo é sempre um `categoria_id`/`subcategoria_id` que já existe
/// nas tabelas `categorias`/`subcategorias` (migração 09 do backend).
///
/// Comportamento:
///   1. Campo vazio -> toque abre uma folha de baixo com busca + lista das
///      CATEGORIAS (nível 1, ex.: "Beleza e Bem-Estar").
///   2. Categoria escolhida -> vira um Chip dentro do campo. Aparece um
///      segundo Chip de ação ("Escolher especialidade") que abre a MESMA
///      folha, agora com busca + lista das SUBCATEGORIAS daquela categoria
///      (nível 2, ex.: "Barbeiro", "Manicure/Pedicure"...).
///   3. Subcategoria escolhida -> o Chip de ação vira um Chip "congelado"
///      igual ao da categoria, lado a lado dentro do mesmo campo.
///
/// Tocar no "x" de um Chip remove aquela escolha. Remover a categoria
/// remove a subcategoria junto (ela deixou de fazer sentido sem o pai).
/// Tocar no CORPO de um Chip já escolhido (não no "x") reabre a folha
/// daquele nível, para trocar a escolha sem precisar recomeçar do zero.
///
/// É um widget "controlado": quem usa (`cadastro_screen.dart`) guarda
/// `categoriaSelecionada`/`subcategoriaSelecionada` no próprio State e
/// repassa aqui -- o mesmo padrão de um `TextFormField` com `controller`.
class SeletorCategoriaCascata extends StatelessWidget {
  final List<Categoria> categorias;
  final Categoria? categoriaSelecionada;
  final Subcategoria? subcategoriaSelecionada;
  final ValueChanged<Categoria?> onCategoriaAlterada;
  final ValueChanged<Subcategoria?> onSubcategoriaAlterada;
  final String labelText;
  final String? errorText;

  const SeletorCategoriaCascata({
    super.key,
    required this.categorias,
    required this.categoriaSelecionada,
    required this.subcategoriaSelecionada,
    required this.onCategoriaAlterada,
    required this.onSubcategoriaAlterada,
    this.labelText = 'Categoria de atuação',
    this.errorText,
  });

  Future<void> _abrirSelecaoDeCategoria(BuildContext context) async {
    final escolhida = await _FolhaDeBusca.abrir<Categoria>(
      context,
      titulo: 'Escolha sua categoria',
      itens: categorias,
      rotuloDoItem: (categoria) => categoria.nome,
    );
    if (escolhida == null) return;

    onCategoriaAlterada(escolhida);
    // A subcategoria antiga pode pertencer a uma categoria diferente da
    // nova escolhida -- sempre reinicia, força escolher de novo.
    onSubcategoriaAlterada(null);
  }

  Future<void> _abrirSelecaoDeSubcategoria(BuildContext context) async {
    final categoria = categoriaSelecionada;
    if (categoria == null) return;

    final escolhida = await _FolhaDeBusca.abrir<Subcategoria>(
      context,
      titulo: 'Escolha a especialidade em "${categoria.nome}"',
      itens: categoria.subcategorias,
      rotuloDoItem: (subcategoria) => subcategoria.nome,
    );
    if (escolhida == null) return;

    onSubcategoriaAlterada(escolhida);
  }

  @override
  Widget build(BuildContext context) {
    final temCategoria = categoriaSelecionada != null;
    final temSubcategoria = subcategoriaSelecionada != null;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: labelText,
        errorText: errorText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      child: !temCategoria
          ? InkWell(
              onTap: () => _abrirSelecaoDeCategoria(context),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: Theme.of(context).hintColor),
                  const SizedBox(width: 8),
                  Text(
                    'Toque para selecionar a categoria',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Chip "congelado" da categoria (nível 1). Tocar no corpo
                // reabre a escolha; tocar no "x" remove os dois níveis.
                InputChip(
                  label: Text(categoriaSelecionada!.nome),
                  onPressed: () => _abrirSelecaoDeCategoria(context),
                  onDeleted: () {
                    onCategoriaAlterada(null);
                    onSubcategoriaAlterada(null);
                  },
                ),
                if (temSubcategoria)
                  // Chip "congelado" da subcategoria (nível 2).
                  InputChip(
                    label: Text(subcategoriaSelecionada!.nome),
                    onPressed: () => _abrirSelecaoDeSubcategoria(context),
                    onDeleted: () => onSubcategoriaAlterada(null),
                  )
                else
                  // Etapa 2 ainda não concluída -- convite para escolher.
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Escolher especialidade'),
                    onPressed: () => _abrirSelecaoDeSubcategoria(context),
                  ),
              ],
            ),
    );
  }
}

/// Folha de baixo reutilizável: busca (só FILTRA a lista já carregada) +
/// lista de itens tocáveis. Genérica em `T` porque serve tanto para
/// categorias quanto para subcategorias -- o comportamento é idêntico, só
/// muda de onde vem a lista.
class _FolhaDeBusca<T> extends StatefulWidget {
  final String titulo;
  final List<T> itens;
  final String Function(T) rotuloDoItem;

  const _FolhaDeBusca({
    required this.titulo,
    required this.itens,
    required this.rotuloDoItem,
  });

  /// Abre a folha e devolve o item escolhido, ou `null` se a pessoa fechar
  /// sem escolher nada (arrastar para baixo, tocar fora, botão voltar).
  static Future<T?> abrir<T>(
    BuildContext context, {
    required String titulo,
    required List<T> itens,
    required String Function(T) rotuloDoItem,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FolhaDeBusca<T>(titulo: titulo, itens: itens, rotuloDoItem: rotuloDoItem),
    );
  }

  @override
  State<_FolhaDeBusca<T>> createState() => _FolhaDeBuscaState<T>();
}

class _FolhaDeBuscaState<T> extends State<_FolhaDeBusca<T>> {
  final _buscaController = TextEditingController();
  late List<T> _itensFiltrados;

  @override
  void initState() {
    super.initState();
    _itensFiltrados = widget.itens;
    _buscaController.addListener(_filtrar);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  /// A busca só decide QUAIS itens aparecem na lista -- o valor final
  /// sempre vem de um toque num `ListTile`, nunca do texto digitado aqui.
  /// É essa a diferença entre "campo de busca" (o que o usuário pediu) e
  /// "campo de texto livre" (o que ele explicitamente NÃO quer).
  void _filtrar() {
    final termo = _buscaController.text.trim().toLowerCase();
    setState(() {
      _itensFiltrados = termo.isEmpty
          ? widget.itens
          : widget.itens
              .where((item) => widget.rotuloDoItem(item).toLowerCase().contains(termo))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, controladorDeScroll) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.titulo, style: Theme.of(context).textTheme.titleMedium),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _buscaController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Buscar...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _itensFiltrados.isEmpty
                    ? const Center(child: Text('Nenhum resultado.'))
                    : ListView.builder(
                        controller: controladorDeScroll,
                        itemCount: _itensFiltrados.length,
                        itemBuilder: (context, indice) {
                          final item = _itensFiltrados[indice];
                          return ListTile(
                            title: Text(widget.rotuloDoItem(item)),
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
