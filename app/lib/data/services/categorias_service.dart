import '../models/categoria.dart';
import 'api_client.dart';

/// Camada de transporte para /categorias -- rota PÚBLICA (sem login), a
/// mesma lista fixa que alimenta o `SeletorCategoriaCascata` na tela de
/// cadastro do profissional.
class CategoriasService {
  CategoriasService._();
  static final CategoriasService instancia = CategoriasService._();

  final _api = ApiClient.instancia;

  /// GET /categorias -- árvore completa (categoria + subcategorias), na
  /// ordem que o backend já devolve (alfabética nos dois níveis). Sem
  /// paginação: são só ~7 categorias e ~60 subcategorias, cabe tudo numa
  /// resposta só.
  Future<List<Categoria>> listarCategorias() async {
    final resposta = await _api.get('/categorias', comAutenticacao: false);
    final dados = (resposta as Map<String, dynamic>)['dados'] as List<dynamic>;
    return dados.map((item) => Categoria.fromJson(item as Map<String, dynamic>)).toList();
  }
}
