import crypto from 'crypto';
import { env } from '../env';

/* ============================================================================
   O QUE ESTE ARQUIVO FAZ

   Substitui `services/gateway-pagamento.ts` (Pagar.me, removido na migração
   15). Isola TODA a conversa com a futura API Pix PRÓPRIA do usuário --
   "Eu criarei uma api, integrada a minha conta pix jurídica que aceita alto
   fluxos" -- atrás de um punhado de funções, mesmo espírito de
   `services/cep.ts`: a ROTA (`routes/pagamentos.routes.ts`) nunca monta um
   payload nem lê uma resposta externa diretamente, só chama estas funções.

   ESSA API NÃO EXISTE HOJE. Diferente do antigo `gateway-pagamento.ts` (que
   tinha uma implementação real contra a documentação pública do Pagar.me,
   só não testada), aqui não há documentação nenhuma para seguir -- o
   usuário ainda vai construí-la. Por isso este arquivo tem DOIS modos:

     MODO SIMULADO (`env.pixProprio.baseUrl` ausente -- o padrão em
     qualquer ambiente até a API própria existir): `gerarCobranca` devolve
     uma cobrança FALSA na hora, sem chamar rede nenhuma. É o que permite
     testar o fluxo inteiro (proposta -> confirmação -> retenção ->
     liberação) no app hoje. O "pagamento chegou" (transição para RETIDA)
     nesse modo é disparado manualmente -- ver a rota de desenvolvimento
     `POST /pagamentos/:id/simular-pagamento-recebido` em pagamentos.routes.ts,
     que só existe enquanto o modo simulado estiver ativo.

     MODO REAL (`env.pixProprio.baseUrl` definida): tenta chamar a API de
     verdade. NÃO IMPLEMENTADO ainda -- lança `ErroDePixProprio` explicando
     que falta implementar contra o formato real, assim que ele existir.
     Quando a API própria estiver pronta, implemente `chamarApiPixProprio`
     abaixo seguindo a documentação dela (o mesmo padrão de
     `chamarComTimeout` que o antigo `gateway-pagamento.ts` usava para o
     Pagar.me é um bom ponto de partida).
   ========================================================================= */

/**
 * Erro de comunicação com a API Pix própria -- mesmo papel que
 * `ErroDeGateway` tinha para o Pagar.me: HTTP 502 (nosso servidor tentou
 * falar com algo externo e deu errado), nunca 400 (não é erro de quem
 * chamou nossa API) nem 500 (não é bug nosso).
 */
export class ErroDePixProprio extends Error {
  public readonly status = 502;

  constructor(mensagem: string) {
    super(mensagem);
    this.name = 'ErroDePixProprio';
  }
}

function modoSimuladoAtivo(): boolean {
  return !env.pixProprio.baseUrl;
}

export interface DadosParaGerarCobranca {
  idTransacao: string;
  /** String decimal, ex. "150.00" -- ver utils/dinheiro.ts. */
  valorTotal: string;
  metodoPagamento: 'PIX' | 'BOLETO' | 'OUTRO';
  /** Chave Pix cadastrada pelo profissional (`profissionais.chave_pix`) -- é PARA ELA que o dinheiro vai. */
  chavePixProfissional: string | null;
}

export interface ResultadoCobranca {
  /** ID da cobrança do lado da API externa -- grava em `transacoes.id_cobranca_externa`. */
  idCobrancaExterna: string;
  /** "Copia e cola" do Pix (ou linha digitável do boleto) -- o que o app mostra para o cliente pagar. */
  chaveCobranca: string;
}

/**
 * Gera a cobrança Pix/Boleto na conta do PRÓPRIO profissional. Chamada pela
 * rota de confirmação (`POST /pagamentos/:id/confirmar`), no momento em que
 * o cliente confirma o valor proposto.
 */
export async function gerarCobranca(dados: DadosParaGerarCobranca): Promise<ResultadoCobranca> {
  if (modoSimuladoAtivo()) {
    // Cobrança FALSA -- ver "MODO SIMULADO" no comentário do topo. O
    // prefixo "SIMULADO-" deixa óbvio, em qualquer log ou tela de debug,
    // que este ID nunca existiu de verdade num banco.
    const idFalso = `SIMULADO-${crypto.randomUUID()}`;
    return {
      idCobrancaExterna: idFalso,
      chaveCobranca:
        dados.metodoPagamento === 'BOLETO'
          ? `00190.00009 03384.019007 00000.000000 1 00000000000000` // linha digitável de exemplo
          : `00020126SIMULADO-PIX-${dados.idTransacao}-${dados.valorTotal}5204000053039865802BR6009MANAUS`,
    };
  }

  if (!dados.chavePixProfissional) {
    throw new ErroDePixProprio(
      'O profissional ainda não cadastrou uma chave Pix. Não é possível gerar a cobrança.',
    );
  }

  return chamarApiPixProprio(dados);
}

/**
 * Chamada de verdade contra a API própria -- SEM IMPLEMENTAÇÃO ainda,
 * porque a API não existe. Quando ela existir, troque este corpo pela
 * chamada HTTP real (autenticação via `env.pixProprio.apiKey`, endpoint(s)
 * documentados pela própria API), seguindo o mesmo padrão de
 * `chamarComTimeout`/`AbortController` que `gateway-pagamento.ts` usava
 * para o Pagar.me (ver histórico do Git se precisar do exemplo).
 */
async function chamarApiPixProprio(_dados: DadosParaGerarCobranca): Promise<ResultadoCobranca> {
  throw new ErroDePixProprio(
    'PIX_PROPRIO_BASE_URL está configurada, mas a integração real ainda não foi implementada em services/pix-proprio.ts (função chamarApiPixProprio). Implemente contra o formato da API própria antes de usar em produção.',
  );
}

/* ============================================================================
   WEBHOOK -- verificação do segredo compartilhado

   Verificação PROVISÓRIA por igualdade simples de string (`timingSafeEqual`
   para evitar timing attack), NÃO HMAC -- diferente do antigo
   `verificarAssinaturaWebhook` do Pagar.me. O formato de assinatura real da
   API própria ainda não existe para ser seguido. Troque por HMAC (mesmo
   padrão usado para o Pagar.me) assim que o formato oficial dela for
   definido -- não deixe esta verificação simples em produção com tráfego
   real sem revisar contra a documentação da API própria nesse momento.
   ========================================================================= */
export function verificarSegredoWebhook(segredoRecebido: string | undefined): boolean {
  if (!env.pixProprio.webhookSecret) {
    // Sem segredo configurado, não dá para verificar nada -- aceitável só
    // em desenvolvimento local (modo simulado), nunca em produção.
    return false;
  }
  if (!segredoRecebido) return false;

  const esperado = Buffer.from(env.pixProprio.webhookSecret);
  const recebido = Buffer.from(segredoRecebido);

  if (esperado.length !== recebido.length) return false;
  return crypto.timingSafeEqual(esperado, recebido);
}

/** Formato (provisório) do corpo que a futura API própria mandaria no webhook de confirmação de pagamento. Ajuste assim que o formato real existir. */
export interface PayloadWebhookPixProprio {
  id_cobranca_externa: string;
  status: 'pago' | 'falhou' | string;
}
