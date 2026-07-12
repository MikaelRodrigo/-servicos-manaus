import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'api_client.dart';

/// Camada de transporte para /servicos/:id/avaliacoes/*.
class AvaliacoesService {
  AvaliacoesService._();
  static final AvaliacoesService instancia = AvaliacoesService._();

  final _api = ApiClient.instancia;

  /// O CLIENTE avalia o PROFISSIONAL. `fotos` é opcional (pode vir vazia) e
  /// aceita ATÉ 5 imagens -- por isso sempre mandamos como multipart/
  /// form-data (via `postMultipart`), com ou sem arquivos anexados. O
  /// backend (multer, `.array('fotos_servico', 5)`) lida com os dois casos
  /// igual.
  ///
  /// `fotos` é uma lista de `XFile` (do image_picker), não `dart:io File`
  /// -- é o tipo que funciona igual em mobile, desktop E web.
  /// `readAsBytes()` nele funciona nas três plataformas.
  Future<Map<String, dynamic>> avaliarProfissional({
    required String idServico,
    required int estrelasTecnico,
    required int estrelasComportamental,
    required int estrelasEconomico,
    String? comentario,
    List<XFile> fotos = const [],
  }) async {
    final bytesDasFotos = <Uint8List>[];
    final nomesDasFotos = <String>[];
    for (final foto in fotos) {
      bytesDasFotos.add(await foto.readAsBytes());
      nomesDasFotos.add(foto.name);
    }

    final resposta = await _api.postMultipart(
      '/servicos/$idServico/avaliacoes/profissional',
      campos: {
        'estrelas_tecnico': '$estrelasTecnico',
        'estrelas_comportamental': '$estrelasComportamental',
        'estrelas_economico': '$estrelasEconomico',
        if (comentario != null && comentario.isNotEmpty) 'comentario': comentario,
      },
      arquivos: bytesDasFotos,
      nomesArquivos: nomesDasFotos,
    );
    return resposta as Map<String, dynamic>;
  }

  /// O PROFISSIONAL avalia o CLIENTE. Sem foto -- essa tabela não tem essa
  /// coluna (ver avaliacoes.repository.ts no backend) -- por isso aqui é
  /// um POST JSON normal, mais simples que o de cima.
  Future<Map<String, dynamic>> avaliarCliente({
    required String idServico,
    required int estrelasClareza,
    required int estrelasComportamental,
    required int estrelasPagamento,
    String? comentario,
  }) async {
    final resposta = await _api.post(
      '/servicos/$idServico/avaliacoes/cliente',
      corpo: {
        'estrelas_clareza': estrelasClareza,
        'estrelas_comportamental': estrelasComportamental,
        'estrelas_pagamento': estrelasPagamento,
        if (comentario != null && comentario.isNotEmpty) 'comentario': comentario,
      },
    );
    return resposta as Map<String, dynamic>;
  }

  /// Devolve `{ avaliacao_do_profissional: {...} | null, avaliacao_do_cliente: {...} | null }`.
  /// Usado para saber se a pessoa logada JÁ avaliou este serviço (e não
  /// mostrar o formulário de novo).
  Future<Map<String, dynamic>> buscarAvaliacoes(String idServico) async {
    final resposta = await _api.get('/servicos/$idServico/avaliacoes');
    return resposta as Map<String, dynamic>;
  }
}
