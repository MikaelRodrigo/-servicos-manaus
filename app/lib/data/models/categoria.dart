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

/// Uma TAG de especialidade de um profissional (migração 11 no backend --
/// tabela `profissional_subcategorias`, N:N). Diferente de [Subcategoria]
/// (que é um item da árvore fixa de `GET /categorias`), esta classe espelha
/// um item do array `subcategorias` que vem DENTRO do perfil de um
/// profissional (`GET /profissionais/:id`, `GET /profissionais/me/subcategorias`,
/// etc.) -- por isso já carrega o nome da categoria-mãe junto
/// (`categoriaNome`), sem precisar cruzar com a árvore completa para exibir
/// "Eletricista (em: Manutenção e Reforma)".
class TagSubcategoria {
  final int id;
  final String nome;
  final int categoriaId;
  final String categoriaNome;

  const TagSubcategoria({
    required this.id,
    required this.nome,
    required this.categoriaId,
    required this.categoriaNome,
  });

  factory TagSubcategoria.fromJson(Map<String, dynamic> json) {
    return TagSubcategoria(
      id: json['id'] as int,
      nome: json['nome'] as String,
      categoriaId: json['categoriaId'] as int,
      categoriaNome: json['categoriaNome'] as String,
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
