import 'package:image_picker/image_picker.dart';
import '../models/perfil_cliente.dart';
import 'api_client.dart';

/// Camada de transporte para /clientes/*. Diferente de
/// `ProfissionaisService` (que fala com rotas majoritariamente PÚBLICAS),
/// aqui as duas rotas exigem login -- é sempre o PRÓPRIO cliente logado
/// vendo/editando os próprios dados.
class ClientesService {
  ClientesService._();
  static final ClientesService instancia = ClientesService._();

  final _api = ApiClient.instancia;

  /// GET /clientes/me -- os dados do próprio cliente logado.
  Future<PerfilCliente> buscarMeuPerfil() async {
    final resposta = await _api.get('/clientes/me');
    return PerfilCliente.fromJson(resposta as Map<String, dynamic>);
  }

  /// PATCH /clientes/me -- o PRÓPRIO cliente logado edita contato, endereço
  /// fixo e/ou foto de perfil. Todos opcionais -- mas ao menos um precisa
  /// vir, senão o backend recusa com 400.
  ///
  /// `foto` é `XFile?` (image_picker), mesmo padrão de
  /// `ProfissionaisService.atualizarMeuPerfil` -- funciona em mobile e web.
  Future<PerfilCliente> atualizarMeuPerfil({
    String? contato,
    String? endereco,
    XFile? foto,
  }) async {
    final resposta = await _api.patchMultipart(
      '/clientes/me',
      campos: {
        if (contato != null) 'contato': contato,
        if (endereco != null) 'endereco': endereco,
      },
      bytesArquivo: foto != null ? await foto.readAsBytes() : null,
      nomeArquivo: foto?.name,
    );
    return PerfilCliente.fromJson(resposta as Map<String, dynamic>);
  }
}
