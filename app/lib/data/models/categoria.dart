/// Uma subcategoria (o "filho") -- ex.: "Barbeiro", sempre presa a UMA
/// categoria. Espelha uma linha da tabela `subcategorias` (migração 09).
class Subcategoria {
  final int id;
  final String nome;

  /// Quantos profissionais têm essa subcategoria agora -- já vem pronto do
  /// backend (`categorias.repository.ts`, um `COUNT` agregado numa query só)
  /// junto com o resto da árvore de categorias, buscada UMA vez por tela.
  /// Usado no autocomplete de busca do mapa para mostrar "Encanador (9)".
  final int totalProfissionais;

  const Subcategoria({required this.id, required this.nome, this.totalProfissionais = 0});

  factory Subcategoria.fromJson(Map<String, dynamic> json) {
    return Subcategoria(
      id: json['id'] as int,
      nome: json['nome'] as String,
      totalProfissionais: json['totalProfissionais'] as int? ?? 0,
    );
  }
}

/// Uma categoria (o "pai") -- ex.: "Beleza e Bem-Estar" -- já vem com a
/// lista completa de subcategorias dela dentro. É a árvore inteira que
/// `GET /categorias` devolve de uma vez (ver categorias.repository.ts no
/// backend); o app busca isso UMA vez e usa em memória para alimentar as
/// duas etapas do `SeletorCategoriaCascata`.
class Categoria {
  final int id;
  final String nome;
  final List<Subcategoria> subcategorias;

  const Categoria({required this.id, required this.nome, required this.subcategorias});

  factory Categoria.fromJson(Map<String, dynamic> json) {
    final listaSubcategorias = json['subcategorias'] as List<dynamic>? ?? const [];
    return Categoria(
      id: json['id'] as int,
      nome: json['nome'] as String,
      subcategorias: listaSubcategorias
          .map((item) => Subcategoria.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
