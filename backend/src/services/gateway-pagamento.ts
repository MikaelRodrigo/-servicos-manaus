import crypto from 'crypto';
import { env } from '../env';
import { valorParaCentavos } from '../utils/dinheiro';

/* ============================================================================
   O QUE ESTE ARQUIVO FAZ

   Isola TODA a conversa com o Pagar.me (API v5, https://api.pagar.me/core/v5)
   atrás de um punhado de funções -- mesmo espírito de `services/cep.ts`
   (ViaCEP/Nominatim): a ROTA (`routes/pagamentos.routes.ts`) nunca monta um
   payload de gateway nem lê um campo de resposta dele diretamente, só chama
   estas funções.

   ATENÇÃO -- ISTO NÃO FOI TESTADO CONTRA UMA CONTA PAGAR.ME DE VERDADE.
   Os formatos de request/response abaixo vêm da documentação pública
   (https://docs.pagar.me/reference, consultada nesta mesma sessão) mas o
   projeto não tem credenciais de sandbox para validar ponta a ponta. Antes
   de usar isto contra tráfego real:
     1. Crie uma conta de TESTE no Pagar.me e gere uma chave sk_test_...
     2. Rode o fluxo completo (autorizar -> webhook -> liberar) contra o
        sandbox deles e compare CADA payload de resposta com o que as
        funções abaixo esperam (em especial `interpretarRespostaPedido` e
        `verificarAssinaturaWebhook` -- o nome exato do header de
        assinatura e o algoritmo devem ser confirmados no painel, na tela
        de configuração do webhook).
     3. Só depois disso, aponte para a chave de produção.
   ========================================================================= */

const BASE_URL = 'https://api.pagar.me/core/v5';

/**
 * Erro de comunicação com o gateway -- deliberadamente DIFERENTE de
 * `ErroDeValidacao` (400): o problema não é o que o cliente mandou pra
 * nossa API, é o gateway ter recusado o pagamento, estar fora do ar, ou
 * uma credencial estar ausente/errada. HTTP 502 (Bad Gateway) é o código
 * correto para "nosso servidor tentou falar com um serviço externo, e deu
 * errado" -- diferente de 400 (nosso erro de validação) e 500 (bug nosso).
 */
export class ErroDeGateway extends Error {
  public readonly status = 502;

  constructor(mensagem: string) {
    super(mensagem);
    this.name = 'ErroDeGateway';
  }
}

function exigirCredenciais(): { apiKey: string } {
  if (!env.pagarme.apiKey) {
    // Erro de CONFIGURAÇÃO do servidor, não do usuário -- por isso não é
    // ErroDeValidacao. Quem vê isto é o backend (log), não o cliente final
    // (a rota deveria capturar e devolver uma mensagem genérica, mas o
    // detalhe completo fica no log do servidor).
    throw new ErroDeGateway(
      'PAGARME_API_KEY não configurada no servidor. Configure o .env antes de usar o módulo de pagamentos.',
    );
  }
  return { apiKey: env.pagarme.apiKey };
}

/** HTTP Basic Auth com a chave secreta como usuário e senha vazia -- é assim que a API v5 do Pagar.me autentica toda requisição. */
function cabecalhoAutenticacao(apiKey: string): string {
  return `Basic ${Buffer.from(`${apiKey}:`).toString('base64')}`;
}

async function chamarComTimeout(
  caminho: string,
  opcoes: { method: string; body?: unknown },
  timeoutMs = 15_000,
): Promise<Response> {
  const { apiKey } = exigirCredenciais();
  const controlador = new AbortController();
  const temporizador = setTimeout(() => controlador.abort(), timeoutMs);

  try {
    return await fetch(`${BASE_URL}${caminho}`, {
      method: opcoes.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: cabecalhoAutenticacao(apiKey),
      },
      body: opcoes.body ? JSON.stringify(opcoes.body) : undefined,
      signal: controlador.signal,
    });
  } catch (erro) {
    throw new ErroDeGateway(
      `Não foi possível falar com o gateway de pagamento agora. Tente novamente em instantes. (${erro instanceof Error ? erro.message : 'erro de rede'})`,
    );
  } finally {
    clearTimeout(temporizador);
  }
}

/* ============================================================================
   ETAPA A -- AUTORIZAÇÃO
   ========================================================================= */

export interface DadosParaAutorizar {
  /** Usado como `code` do pedido no Pagar.me -- nosso `id_transacao`, para conseguirmos casar o pedido de volta a partir do webhook mesmo antes do `id_pedido_gateway` ter sido gravado. */
  idTransacao: string;
  /** Valor TOTAL a cobrar do cliente (valor_servico + taxa_parcelamento), como string decimal -- ver utils/dinheiro.ts. */
  valorTotalCobrado: string;
  metodoPagamento: 'PIX' | 'CARTAO';
  parcelas: number;
  cliente: {
    nome: string;
    email: string;
    /** CPF ou CNPJ, só dígitos. */
    documento: string;
  };
  /**
   * Presente só quando `metodoPagamento === 'CARTAO'` -- token gerado no
   * FRONT (Flutter, via tokenizecard.js/SDK do Pagar.me) a partir dos
   * dados do cartão. O backend NUNCA deve receber número de cartão em
   * texto puro -- isso tiraria o app do escopo PCI-DSS "light" que o
   * tokenizer permite. Ver https://docs.pagar.me/docs/tokenizecard.
   */
  tokenCartao?: string;
}

export interface ResultadoAutorizacao {
  idPedidoGateway: string;
  idCobrancaGateway: string;
  idTransacaoGateway: string | null;
  /** true = autorizado/pago (síncrono); false = falhou/recusado. Estados assíncronos (ex.: PIX aguardando pagamento) chegam pelo webhook, não por aqui. */
  autorizadoDeImediato: boolean;
  /** Só para PIX -- o "copia e cola"/QR code para o cliente pagar. */
  qrCodePix?: string;
  qrCodePixUrl?: string;
}

/**
 * Cria o "Pedido" (order) no Pagar.me com uma única cobrança (charge).
 * PIX geralmente volta com status `pending` (o cliente ainda precisa
 * escanear o QR code) -- a confirmação de verdade chega pelo webhook
 * (`order.paid`). Cartão pode voltar já `paid` de forma síncrona, mas o
 * webhook é sempre a fonte de verdade final (é possível um `paid` síncrono
 * ser seguido de um `chargedback` dias depois -- fora do escopo desta
 * função, tratado por eventos futuros do mesmo webhook).
 */
export async function autorizarCobranca(dados: DadosParaAutorizar): Promise<ResultadoAutorizacao> {
  const valorCentavos = valorParaCentavos(dados.valorTotalCobrado);

  const payment =
    dados.metodoPagamento === 'PIX'
      ? { payment_method: 'pix' as const, pix: { expires_in: 3600 } }
      : {
          payment_method: 'credit_card' as const,
          credit_card: {
            installments: dados.parcelas,
            card_token: dados.tokenCartao,
          },
        };

  const resposta = await chamarComTimeout('/orders', {
    method: 'POST',
    body: {
      // `code` -- identificador NOSSO no pedido do gateway. É o que
      // permite, no handler do webhook, achar a transação mesmo que o
      // evento chegue fora de ordem ou antes de gravarmos `id_pedido_gateway`.
      code: dados.idTransacao,
      items: [
        {
          amount: valorCentavos,
          description: 'Serviço via Serviços Manaus',
          quantity: 1,
        },
      ],
      customer: {
        name: dados.cliente.nome,
        email: dados.cliente.email,
        document: dados.cliente.documento,
        document_type: dados.cliente.documento.length === 14 ? 'CNPJ' : 'CPF',
        type: dados.cliente.documento.length === 14 ? 'company' : 'individual',
      },
      payments: [payment],
    },
  });

  if (!resposta.ok) {
    const corpo = await resposta.text().catch(() => '');
    throw new ErroDeGateway(
      `Gateway recusou a criação da cobrança (HTTP ${resposta.status}). ${corpo.slice(0, 300)}`,
    );
  }

  const pedido = (await resposta.json()) as RespostaPedidoPagarme;
  return interpretarRespostaPedido(pedido);
}

/**
 * Formato reduzido da resposta de POST /orders -- só os campos que
 * realmente usamos. O Pagar.me devolve MUITO mais coisa (endereço,
 * metadata, etc.) que não precisamos tipar aqui.
 */
interface RespostaPedidoPagarme {
  id: string;
  status: string; // 'pending' | 'paid' | 'canceled' | 'failed' (conferir contra a doc antes de produção)
  charges: Array<{
    id: string;
    status: string;
    last_transaction?: {
      id?: string;
      qr_code?: string;
      qr_code_url?: string;
    };
  }>;
}

function interpretarRespostaPedido(pedido: RespostaPedidoPagarme): ResultadoAutorizacao {
  const cobranca = pedido.charges[0];
  if (!cobranca) {
    throw new ErroDeGateway('Resposta do gateway sem nenhuma cobrança (charges[]) -- payload inesperado.');
  }

  return {
    idPedidoGateway: pedido.id,
    idCobrancaGateway: cobranca.id,
    idTransacaoGateway: cobranca.last_transaction?.id ?? null,
    autorizadoDeImediato: cobranca.status === 'paid',
    qrCodePix: cobranca.last_transaction?.qr_code,
    qrCodePixUrl: cobranca.last_transaction?.qr_code_url,
  };
}

/* ============================================================================
   ETAPA D -- SPLIT / LIBERAÇÃO

   IMPORTANTE: a API v5 documenta o Split como algo configurado NA CRIAÇÃO
   do pedido (`payments[].split`, com `type`/`amount`/`recipient_id` por
   recebedor -- ver https://docs.pagar.me/docs/pedidos-com-split), não como
   uma transferência separada disparada depois. Ou seja, o jeito "oficial"
   de fazer o Split seria declarar o repasse do profissional JÁ na chamada
   de `autorizarCobranca` acima (Etapa A) -- o gateway reteria a parte da
   plataforma e já destinaria a parte do profissional automaticamente,
   SEM precisar de uma chamada de liberação manual aqui.

   Isso colide com o requisito de negócio do fluxo pedido (Etapa D: "assim
   que o CLIENTE confirma, chama Transferência/Split" -- ou seja, a
   liberação deve ser CONDICIONADA à confirmação, não automática no
   momento do pagamento). Duas formas de resolver isso, e a escolha entre
   elas é uma decisão de produto que fica para quem for validar contra o
   sandbox:

     (a) Usar `recipient_id` no Split da Etapa A, mas com o dinheiro
         retido numa conta do tipo "reserva" configurável no Pagar.me
         (marketplace com liquidação programada) -- o "Escrow" seria
         nativo do gateway.
     (b) NÃO declarar split na Etapa A (recebedor único: a plataforma) e
         fazer a liberação como uma TRANSFERÊNCIA avulsa (POST
         /recipients/{id}/transfers) na Etapa D -- é o modelo que esta
         função assume, por ser o que dá controle EXPLÍCITO sobre o
         momento da liberação (mais alinhado ao pedido "o dinheiro fica
         retido até o evento de liberação ser acionado").

   O código abaixo implementa (b). Confirmar contra a doc/suporte Pagar.me
   se a conta do projeto tem esse endpoint de transferência avulsa
   habilitado (é um recurso de conta PSP/marketplace, não vem ligado por
   padrão em toda conta).
   ========================================================================= */

export interface DadosParaLiberarRepasse {
  /** Subconta do profissional -- `profissionais.id_recebedor_gateway`. */
  idRecebedorGateway: string;
  /** Valor a transferir, já calculado (valor_servico - taxa_plataforma, ou o valor ajustado por uma disputa com flag_dano). */
  valorRepasse: string;
}

export interface ResultadoTransferencia {
  idTransferenciaGateway: string;
}

export async function criarTransferenciaSplit(
  dados: DadosParaLiberarRepasse,
): Promise<ResultadoTransferencia> {
  const valorCentavos = valorParaCentavos(dados.valorRepasse);

  const resposta = await chamarComTimeout(`/recipients/${dados.idRecebedorGateway}/transfers`, {
    method: 'POST',
    body: { amount: valorCentavos },
  });

  if (!resposta.ok) {
    const corpo = await resposta.text().catch(() => '');
    throw new ErroDeGateway(
      `Gateway recusou a transferência de repasse (HTTP ${resposta.status}). ${corpo.slice(0, 300)}`,
    );
  }

  const dadosResposta = (await resposta.json()) as { id: string };
  return { idTransferenciaGateway: dadosResposta.id };
}

/* ============================================================================
   WEBHOOK -- verificação de assinatura

   O corpo BRUTO (`req.rawBody`, ver `types/express.d.ts` e o `verify`
   callback em `app.ts`) é obrigatório aqui: recalcular a assinatura sobre
   `JSON.stringify(req.body)` (o objeto já parseado) não é confiável --
   nada garante que a re-serialização produza os MESMOS bytes que o
   Pagar.me assinou.
   ========================================================================= */

/**
 * `true` se a assinatura bater. Usa `timingSafeEqual` (não `===`) para não
 * vazar, por diferença de tempo de resposta, quantos bytes da assinatura
 * já acertamos -- um ataque de "timing attack" clássico contra comparação
 * de segredo.
 */
export function verificarAssinaturaWebhook(corpoBruto: Buffer, assinaturaRecebida: string | undefined): boolean {
  if (!env.pagarme.webhookSecret) {
    // Sem segredo configurado, não dá para verificar nada -- decisão de
    // quem chama (o handler da rota) se aceita mesmo assim (aceitável só
    // em desenvolvimento local, nunca em produção).
    return false;
  }
  if (!assinaturaRecebida) return false;

  // Formato comum (GitHub, e aparentemente Pagar.me): "sha256=<hex>".
  const assinaturaLimpa = assinaturaRecebida.replace(/^sha256=/, '');

  const esperada = crypto
    .createHmac('sha256', env.pagarme.webhookSecret)
    .update(corpoBruto)
    .digest('hex');

  const bufferEsperado = Buffer.from(esperada, 'hex');
  const bufferRecebido = Buffer.from(assinaturaLimpa, 'hex');

  if (bufferEsperado.length !== bufferRecebido.length) return false;
  return crypto.timingSafeEqual(bufferEsperado, bufferRecebido);
}

/** Formato (reduzido) do corpo que todo webhook do Pagar.me manda -- ver "Visão geral sobre Webhooks" na doc. */
export interface PayloadWebhookPagarme {
  id: string;
  event: string; // ex.: 'order.paid', 'order.payment_failed', 'charge.refunded'
  data: {
    id: string; // id do order OU da charge, dependendo do evento
    code?: string; // o `code` que mandamos em `autorizarCobranca` -- nosso id_transacao
    status?: string;
  };
}
