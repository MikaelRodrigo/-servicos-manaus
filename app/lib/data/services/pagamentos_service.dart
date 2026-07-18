import '../models/transacao.dart';
import 'api_client.dart';

/// Camada de transporte para /pagamentos/* (migração 15 -- modelo de
/// intermediação: proposta de valor -> confirmação -> cobrança na conta do
/// profissional -> retenção -> liberação). Substitui por completo o antigo
/// fluxo de checkout via Pagar.me.
class PagamentosService {
  PagamentosService._();
  static final PagamentosService instancia = PagamentosService._();

  final _api = ApiClient.instancia;

  /// O profissional avalia o serviço presencialmente e propõe um valor.
  /// `valorTotal` já deve estar no formato decimal com PONTO ("150.00") --
  /// ver `converterParaDecimalApi` em `servico_detalhe_screen.dart` para a
  /// conversão a partir do que o usuário digita (com vírgula, padrão BR).
  Future<Transacao> propor({required String idServico, required String valorTotal}) async {
    final resposta = await _api.post(
      '/pagamentos/propor',
      corpo: {'id_servico': idServico, 'valor_total': valorTotal},
    );
    return Transacao.fromJson(resposta as Map<String, dynamic>);
  }

  Future<Transacao> recusar(String idTransacao) async {
    final resposta = await _api.post('/pagamentos/$idTransacao/recusar');
    return Transacao.fromJson(resposta as Map<String, dynamic>);
  }

  /// O cliente confirma o valor proposto. Devolve a transação atualizada E
  /// a chave de cobrança gerada (Pix "copia e cola" ou linha do boleto) --
  /// mesmo valor que fica em `transacao.chaveCobranca`, repetido na raiz da
  /// resposta só por conveniência de quem consome isto direto.
  Future<({Transacao transacao, String chaveCobranca})> confirmar({
    required String idTransacao,
    required MetodoPagamento metodoPagamento,
  }) async {
    final resposta = await _api.post(
      '/pagamentos/$idTransacao/confirmar',
      corpo: {'metodo_pagamento': metodoPagamento.valorApi},
    ) as Map<String, dynamic>;
    return (
      transacao: Transacao.fromJson(resposta['transacao'] as Map<String, dynamic>),
      chaveCobranca: resposta['chave_cobranca'] as String,
    );
  }

  /// O cliente confirma que o serviço terminou -- libera a retenção e
  /// conclui o serviço (o que já libera as avaliações mútuas do outro lado).
  Future<Transacao> confirmarTermino(String idTransacao) async {
    final resposta = await _api.post('/pagamentos/$idTransacao/confirmar-termino');
    return Transacao.fromJson(resposta as Map<String, dynamic>);
  }

  /// SÓ FUNCIONA em modo simulado (a API Pix própria ainda não existe --
  /// ver `services/pix-proprio.ts` no backend). Marca o pagamento como
  /// recebido na hora, sem esperar um webhook de verdade -- é o jeito de
  /// testar o fluxo completo antes da API própria existir. Em produção,
  /// com a API própria configurada, o backend devolve 404 para esta rota.
  Future<Transacao> simularPagamentoRecebido(String idTransacao) async {
    final resposta = await _api.post('/pagamentos/$idTransacao/simular-pagamento-recebido');
    return Transacao.fromJson(resposta as Map<String, dynamic>);
  }

  /// Todas as tentativas de proposta/pagamento de um serviço, da mais
  /// recente para a mais antiga -- a tela de detalhe usa só a primeira
  /// (`.first`), mas o histórico completo fica disponível para quem quiser.
  Future<List<Transacao>> listarDoServico(String idServico) async {
    final resposta = await _api.get('/pagamentos/servico/$idServico') as List<dynamic>;
    return resposta.map((item) => Transacao.fromJson(item as Map<String, dynamic>)).toList();
  }
}
