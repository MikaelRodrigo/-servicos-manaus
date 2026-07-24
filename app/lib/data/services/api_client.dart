import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import '../../core/config/api_config.dart';
import 'armazenamento_token.dart';

/// Decide o Content-Type do arquivo a partir da EXTENSÃO do nome.
///
/// Sem isto, `http.MultipartFile.fromBytes` manda o arquivo como
/// `application/octet-stream` (tipo genérico) quando `contentType` não é
/// informado -- e o backend rejeita, porque o `fileFilter` do multer
/// (upload.ts) só aceita `image/jpeg`, `image/png` e `image/webp`
/// EXPLICITAMENTE no cabeçalho HTTP, não pela extensão do arquivo.
MediaType? _tipoDeConteudoPorExtensao(String? nomeArquivo) {
  if (nomeArquivo == null) return null;
  final partes = nomeArquivo.split('.');
  if (partes.length < 2) return null;

  switch (partes.last.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    default:
      return null; // extensão desconhecida -- deixa o backend recusar com mensagem clara.
  }
}

/// Erro de API já "traduzido": pega a mensagem que o backend mandou em
/// `{ "erro": "..." }` (todo erro do nosso Express segue esse formato,
/// veja o middleware de erro em app.ts) e expõe pronta para mostrar na tela.
class ApiException implements Exception {
  final int statusCode;
  final String mensagem;
  /// Corpo JSON completo do erro (quando é um Map) -- além de "erro", o
  /// backend às vezes manda campos extras (ex.: `motivo`/`papel`/
  /// `usuario_id` em `ErroTelefoneNaoVerificado`, ver auth.routes.ts/
  /// app.ts). `null` quando o corpo não é um Map (ou não veio nenhum).
  final Map<String, dynamic>? corpo;

  ApiException(this.statusCode, this.mensagem, {this.corpo});

  @override
  String toString() => mensagem;
}

/// Camada única de acesso HTTP. Nenhuma tela ou provider chama `http.get`
/// diretamente -- todo mundo passa por aqui. Isso centraliza três coisas
/// que, se espalhadas pelo app, viram um pesadelo de manter: (1) montar a
/// URL certa por plataforma, (2) anexar o header Authorization, (3)
/// traduzir erro HTTP em algo que a tela consegue mostrar.
class ApiClient {
  ApiClient._();
  static final ApiClient instancia = ApiClient._();

  Future<Map<String, String>> _cabecalhos({required bool comAutenticacao}) async {
    final cabecalhos = {'Content-Type': 'application/json'};
    if (comAutenticacao) {
      final token = await ArmazenamentoToken.instancia.ler();
      if (token != null) {
        cabecalhos['Authorization'] = 'Bearer $token';
      }
    }
    return cabecalhos;
  }

  Uri _uri(String caminho, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$caminho');
    if (query == null || query.isEmpty) return uri;
    // Query params sempre viram string na URL -- ?raio_km=5, nunca ?raio_km=5.0
    // sem necessidade. O `.toString()` cuida disso para número, bool, etc.
    final queryString = query.map((chave, valor) => MapEntry(chave, valor.toString()));
    return uri.replace(queryParameters: queryString);
  }

  Future<dynamic> get(String caminho, {Map<String, dynamic>? query, bool comAutenticacao = true}) async {
    final resposta = await http.get(
      _uri(caminho, query),
      headers: await _cabecalhos(comAutenticacao: comAutenticacao),
    );
    return _tratarResposta(resposta);
  }

  Future<dynamic> post(String caminho, {Object? corpo, bool comAutenticacao = true}) async {
    final resposta = await http.post(
      _uri(caminho),
      headers: await _cabecalhos(comAutenticacao: comAutenticacao),
      body: corpo != null ? jsonEncode(corpo) : null,
    );
    return _tratarResposta(resposta);
  }

  Future<dynamic> patch(String caminho, {Object? corpo, bool comAutenticacao = true}) async {
    final resposta = await http.patch(
      _uri(caminho),
      headers: await _cabecalhos(comAutenticacao: comAutenticacao),
      body: corpo != null ? jsonEncode(corpo) : null,
    );
    return _tratarResposta(resposta);
  }

  /// DELETE -- usado hoje só para remover uma tag de especialidade
  /// (DELETE /profissionais/me/subcategorias/:subcategoriaId). Sem corpo:
  /// o que remover já está no próprio caminho da URL.
  Future<dynamic> delete(String caminho, {bool comAutenticacao = true}) async {
    final resposta = await http.delete(
      _uri(caminho),
      headers: await _cabecalhos(comAutenticacao: comAutenticacao),
    );
    return _tratarResposta(resposta);
  }

  /// POST ou PATCH multipart/form-data -- usado em toda tela que manda
  /// arquivo (avaliação com fotos, edição de perfil com foto). Campos de
  /// texto vão em `campos`; cada item de `arquivos` é anexado com o MESMO
  /// nome de campo `nomeCampoArquivo` -- é assim que multipart representa
  /// "vários arquivos no mesmo campo", e tem que bater EXATAMENTE com o que
  /// o multer espera no backend (veja upload.ts, `.array('...')`/`.single('...')`).
  ///
  /// Recebe BYTES (`Uint8List`), não um `dart:io File`, de propósito: a
  /// classe `File` do `dart:io` simplesmente NÃO EXISTE quando o app roda
  /// no navegador (Flutter Web não tem sistema de arquivos). Como estamos
  /// testando o app tanto no emulador quanto no Chrome, usar bytes crus
  /// funciona nos dois -- é o `image_picker` (via `XFile.readAsBytes()`)
  /// quem faz essa ponte de forma portátil, na tela que chama isto.
  Future<dynamic> _enviarMultipart(
    String metodo,
    String caminho, {
    required Map<String, String> campos,
    required String nomeCampoArquivo,
    List<Uint8List> arquivos = const [],
    List<String> nomesArquivos = const [],
  }) async {
    final requisicao = http.MultipartRequest(metodo, _uri(caminho));

    final token = await ArmazenamentoToken.instancia.ler();
    if (token != null) {
      requisicao.headers['Authorization'] = 'Bearer $token';
    }

    requisicao.fields.addAll(campos);

    for (var i = 0; i < arquivos.length; i++) {
      final nome = i < nomesArquivos.length ? nomesArquivos[i] : 'foto_$i.jpg';
      requisicao.files.add(
        http.MultipartFile.fromBytes(
          nomeCampoArquivo,
          arquivos[i],
          filename: nome,
          contentType: _tipoDeConteudoPorExtensao(nome),
        ),
      );
    }

    final respostaStream = await requisicao.send();
    final resposta = await http.Response.fromStream(respostaStream);
    return _tratarResposta(resposta);
  }

  /// POST multipart -- usado na avaliação com fotos (até 5)
  /// (POST /servicos/:id/avaliacoes/profissional, campo "fotos_servico").
  Future<dynamic> postMultipart(
    String caminho, {
    required Map<String, String> campos,
    List<Uint8List> arquivos = const [],
    List<String> nomesArquivos = const [],
  }) {
    return _enviarMultipart(
      'POST',
      caminho,
      campos: campos,
      nomeCampoArquivo: 'fotos_servico',
      arquivos: arquivos,
      nomesArquivos: nomesArquivos,
    );
  }

  /// POST multipart -- usado para subir fotos no portfólio visual do
  /// profissional (POST /profissionais/me/portfolio-fotos, campo
  /// "fotos_portfolio", migração 16). Mesmo espírito de [postMultipart],
  /// campo de arquivo diferente porque é uma coleção separada no backend
  /// (ver comentário em upload.ts sobre prefixos distintos no S3).
  Future<dynamic> postMultipartPortfolio(
    String caminho, {
    required List<Uint8List> arquivos,
    required List<String> nomesArquivos,
  }) {
    return _enviarMultipart(
      'POST',
      caminho,
      campos: const {},
      nomeCampoArquivo: 'fotos_portfolio',
      arquivos: arquivos,
      nomesArquivos: nomesArquivos,
    );
  }

  /// PATCH multipart -- usado na edição de perfil do profissional
  /// (PATCH /profissionais/me, campo "foto_perfil"). PATCH porque estamos
  /// atualizando um recurso que já existe, não criando um novo. Continua
  /// sendo UMA foto só -- perfil não tem galeria.
  Future<dynamic> patchMultipart(
    String caminho, {
    required Map<String, String> campos,
    Uint8List? bytesArquivo,
    String? nomeArquivo,
  }) {
    return _enviarMultipart(
      'PATCH',
      caminho,
      campos: campos,
      nomeCampoArquivo: 'foto_perfil',
      arquivos: bytesArquivo != null ? [bytesArquivo] : const [],
      nomesArquivos: nomeArquivo != null ? [nomeArquivo] : const [],
    );
  }

  dynamic _tratarResposta(http.Response resposta) {
    final corpo = resposta.body.isNotEmpty ? jsonDecode(resposta.body) : null;

    if (resposta.statusCode >= 200 && resposta.statusCode < 300) {
      return corpo;
    }

    // Todo erro do backend segue o formato `{ "erro": "mensagem" }"
    // (ver app.ts, o middleware de erro central). Se por algum motivo essa
    // forma não bater (ex.: erro 502 de um proxy, sem JSON nenhum), caímos
    // numa mensagem genérica em vez de deixar o jsonDecode explodir.
    final mensagem = (corpo is Map<String, dynamic> && corpo['erro'] is String)
        ? corpo['erro'] as String
        : 'Erro inesperado (código ${resposta.statusCode}).';

    throw ApiException(
      resposta.statusCode,
      mensagem,
      corpo: corpo is Map<String, dynamic> ? corpo : null,
    );
  }
}
