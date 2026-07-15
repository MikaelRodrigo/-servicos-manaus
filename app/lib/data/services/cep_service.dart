import '../models/endereco_cep.dart';
import 'api_client.dart';

/// Camada de transporte para /cep -- rota PÚBLICA (sem login), usada só
/// para o autofill em tempo real do endereço enquanto o usuário digita um
/// CEP num formulário. Não confundir com a geocodificação de verdade, que
/// roda no backend só quando o formulário é salvo (`PATCH /profissionais/me`).
class CepService {
  CepService._();
  static final CepService instancia = CepService._();

  final _api = ApiClient.instancia;

  /// GET /cep/:cep -- devolve rua/bairro/cidade/UF. Lança [ApiException]
  /// com mensagem amigável se o CEP não existir (o backend já traduz o
  /// erro do ViaCEP) ou não tiver 8 dígitos.
  Future<EnderecoPorCep> buscarEndereco(String cep) async {
    final resposta = await _api.get('/cep/$cep', comAutenticacao: false);
    return EnderecoPorCep.fromJson(resposta as Map<String, dynamic>);
  }
}
