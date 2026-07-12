import 'package:image_picker/image_picker.dart';
import 'api_client.dart';

/// Camada de transporte para /servicos/:id/avaliacoes/*.
class AvaliacoesService {
  AvaliacoesService._();
  static final AvaliacoesService instancia = AvaliacoesService._();

  final _api = ApiClient.instancia;

  /// O CLIENTE avalia o PROFISSIONAL. `foto` é opcional -- por isso sempre
  /// mandamos como multipart/form-data (via `postMultipart`), com ou sem
  /// arquivo anexado. O backend (multer) lida com os dois casos igual.
  ///
  /// `foto` é um `XFile` (do image_picker), não um `dart:io File` -- é o
  /// tipo que funciona igual em mobile, desktop E web. `readAsBytes()`
  /// nele funciona nas três plataformas.
  Future<Map<String, dynamic>> avaliarProfissional({
    required String idServico,
    required int estrelasTecnico,
    required int estrelasComportamental,
    required int estrelasEconomico,
    String? comentario,
    XFile? foto,
  }) async {
    final resposta = await _api.postMultipart(
      '/servicos/$idServico/avaliacoes/profissional',
      campos: {
        'estrelas_tecnico': '$estrelasTecnico',
        'estrelas_comportamental': '$estrelasComportamental',
        'estrelas_economico': '$estrelasEconomico',
        if (comentario != null && comentario.isNotEmpty) 'comentario': comentario,
      },
      bytesArquivo: foto != null ? await foto.readAsBytes() : null,
      nomeArquivo: foto?.name,
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
