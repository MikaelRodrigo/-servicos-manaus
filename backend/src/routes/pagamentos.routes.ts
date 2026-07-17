import { Router, Request, Response, NextFunction } from 'express';
import {
  uuidObrigatorio,
  metodoPagamentoObrigatorio,
  parcelasOpcional,
  valorMonetarioObrigatorio,
  textoObrigatorio,
  ErroDeValidacao,
  ErroDeConflito,
  ErroNaoEncontrado,
} from '../utils/validacao';
import { exigirAutenticacao, exigirPapel, ErroDeAutenticacao } from '../middlewares/autenticacao';
import { buscarServicoPorId } from '../repositories/servicos.repository';
import { buscarDadosClienteParaGateway } from '../repositories/clientes.repository';
import { buscarDadosProfissionalParaGateway } from '../repositories/profissionais.repository';
import {
  buscarTransacaoPorId,
  buscarTransacaoPorIdPedidoGateway,
  listarTransacoesDoServico,
  existeTransacaoEmAbertoParaServico,
  existeTransacaoAutorizada,
  criarTransacaoPendente,
  gravarIdsDoGateway,
  marcarAutorizada,
  marcarFalhou,
  marcarEmDisputa,
  marcarLiberada,
  criarEventoWebhook,
  marcarEventoProcessado,
  marcarEventoComErro,
} from '../repositories/transacoes.repository';
import { abrirDisputa } from '../repositories/disputas.repository';
import { gerarCashback } from '../repositories/creditos.repository';
import { criarNotaFiscalPendente } from '../repositories/notas-fiscais.repository';
import {
  autorizarCobranca,
  criarTransferenciaSplit,
  verificarAssinaturaWebhook,
  PayloadWebhookPagarme,
} from '../services/gateway-pagamento';

export const pagamentosRouter = Router();

/* ============================================================================
   REGRAS DE NEGÓCIO AINDA NÃO DEFINIDAS -- PLACEHOLDERS EXPLÍCITOS

   Nem a migração 14 nem o pedido original fixam QUANTO é a taxa da
   plataforma, a taxa de parcelamento, ou o percentual de cashback -- só
   dizem que elas existem. Os valores abaixo são CHUTES razoáveis para o
   sistema ser funcional de ponta a ponta, não uma decisão de produto já
   tomada. Troque por uma fonte de verdade real (variável de ambiente,
   tabela de configuração, ou regra por categoria) antes de produção.
   ========================================================================= */
const TAXA_PLATAFORMA_PERCENTUAL = 0.1; // 10% -- placeholder
const TAXA_ANTECIPACAO_POR_PARCELA_EXTRA = 0.0299; // ~3% ao mês, só a partir da 2ª parcela -- placeholder
const PERCENTUAL_CASHBACK = 0.02; // 2% -- placeholder

function multiplicarValorDecimal(valorDecimal: string, fator: number): string {
  // Único lugar deste módulo em que fazemos aritmética monetária em JS
  // (não em SQL) -- aceitável aqui porque o RESULTADO é só usado como
  // ENTRADA de um novo registro (nunca comparado/somado de volta contra
  // outro valor já gravado), e arredondamos explicitamente para 2 casas
  // antes de formatar. Ver utils/dinheiro.ts para o motivo geral de
  // evitar float em dinheiro -- aqui o placeholder de regra de negócio já
  // é uma aproximação por definição, então o mesmo cuidado extremo não se
  // paga; ainda assim, arredondamos por último, uma vez só.
  const resultado = Math.round(Number(valorDecimal) * fator * 100) / 100;
  return resultado.toFixed(2);
}

/* ============================================================================
   ETAPA A -- POST /pagamentos
   Cliente inicia o pagamento de um serviço já ACEITO pelo profissional.

   Body: {
     id_servico: string (uuid),
     valor_servico: string decimal (ex: "150.00"),
     metodo_pagamento: "PIX" | "CARTAO",
     parcelas?: number (1-12, só relevante para CARTAO),
     token_cartao?: string (obrigatório se metodo_pagamento === "CARTAO" --
       gerado no APP, nunca mande número de cartão cru para este endpoint),
   }

   GAP CONHECIDO: `valor_servico` vem do CORPO DA REQUISIÇÃO, decidido pelo
   próprio cliente que está pagando -- não existe hoje, em lugar nenhum do
   schema, um preço/orçamento associado a um serviço (nem fixo por
   subcategoria, nem uma proposta que o profissional envia ao aceitar).
   Isso é INSEGURO para produção: nada impede o cliente de mandar um valor
   menor do que o combinado por fora. Antes de expor esta rota de verdade,
   o valor precisa vir de uma fonte que o CLIENTE não controle -- por
   exemplo, um campo `valor_proposto` preenchido pelo PROFISSIONAL no
   momento de aceitar o serviço (`PATCH /servicos/:id/aceitar`).
   ========================================================================= */
pagamentosRouter.post(
  '/',
  exigirAutenticacao,
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Record<string, unknown>;
      const idServico = uuidObrigatorio(body.id_servico, 'id_servico');
      const valorServico = valorMonetarioObrigatorio(body.valor_servico, 'valor_servico');
      const metodoPagamento = metodoPagamentoObrigatorio(body.metodo_pagamento);
      const parcelas = parcelasOpcional(body.parcelas);
      const tokenCartao =
        metodoPagamento === 'CARTAO' ? textoObrigatorio(body.token_cartao, 'token_cartao', { max: 500 }) : undefined;

      if (metodoPagamento === 'PIX' && parcelas !== 1) {
        throw new ErroDeValidacao('PIX não aceita parcelamento -- "parcelas" deve ser 1 ou omitido.');
      }

      const servico = await buscarServicoPorId(idServico);
      if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');
      if (servico.cliente_id !== req.usuario!.sub) {
        throw new ErroDeAutenticacao('Este serviço não pertence a você.', 403);
      }
      if (servico.status !== 'ACEITO') {
        throw new ErroDeConflito(
          `Só é possível pagar um serviço com status "ACEITO" (o profissional precisa aceitar primeiro). Status atual: "${servico.status}".`,
        );
      }
      if (await existeTransacaoEmAbertoParaServico(idServico)) {
        throw new ErroDeConflito('Já existe um pagamento em andamento para este serviço.');
      }

      const cliente = await buscarDadosClienteParaGateway(req.usuario!.sub);
      if (!cliente) throw new ErroNaoEncontrado('Cliente não encontrado.');

      const taxaParcelamento =
        metodoPagamento === 'CARTAO' && parcelas > 1
          ? multiplicarValorDecimal(valorServico, TAXA_ANTECIPACAO_POR_PARCELA_EXTRA * (parcelas - 1))
          : '0.00';
      const taxaPlataforma = multiplicarValorDecimal(valorServico, TAXA_PLATAFORMA_PERCENTUAL);

      const transacao = await criarTransacaoPendente({
        idServico,
        metodoPagamento,
        parcelas,
        valorServico,
        taxaParcelamento,
        taxaPlataforma,
      });

      let resultadoGateway;
      try {
        resultadoGateway = await autorizarCobranca({
          idTransacao: transacao.id_transacao,
          valorTotalCobrado: transacao.valor_total_cobrado,
          metodoPagamento,
          parcelas,
          cliente,
          tokenCartao,
        });
      } catch (erro) {
        // O gateway recusou/falhou ao criar a cobrança -- a transação fica
        // em PENDENTE (nunca chegou a existir do lado do gateway, não faz
        // sentido marcar FALHOU aqui; FALHOU é para quando o webhook avisa
        // que uma cobrança que CHEGOU a existir foi recusada depois).
        // Devolvemos o erro para o cliente tentar de novo (talvez outro
        // cartão), mas a transação PENDENTE fica no histórico.
        throw erro;
      }

      await gravarIdsDoGateway(transacao.id_transacao, {
        idPedidoGateway: resultadoGateway.idPedidoGateway,
        idCobrancaGateway: resultadoGateway.idCobrancaGateway,
        idTransacaoGateway: resultadoGateway.idTransacaoGateway,
      });

      if (resultadoGateway.autorizadoDeImediato) {
        await marcarAutorizada(transacao.id_transacao);
      }

      const transacaoAtualizada = await buscarTransacaoPorId(transacao.id_transacao);

      return res.status(201).json({
        transacao: transacaoAtualizada,
        // Só preenchido para PIX -- o Flutter usa isto para desenhar o QR
        // code / botão "copiar código". Para CARTAO, `autorizadoDeImediato`
        // já diz se deu certo (não há nada a mais para o usuário fazer).
        qr_code_pix: resultadoGateway.qrCodePix ?? null,
        qr_code_pix_url: resultadoGateway.qrCodePixUrl ?? null,
      });
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /pagamentos/servico/:idServico -- histórico de tentativas de
   pagamento de UM serviço. Protegido por ownership (cliente OU profissional
   do serviço), mesmo padrão de `verificarPertencimento` em servicos.routes.ts.
   ========================================================================= */
pagamentosRouter.get(
  '/servico/:idServico',
  exigirAutenticacao,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idServico = uuidObrigatorio(req.params.idServico, 'idServico');
      const servico = await buscarServicoPorId(idServico);
      if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');

      const { sub, papel } = req.usuario!;
      const ehDono =
        (papel === 'cliente' && servico.cliente_id === sub) ||
        (papel === 'profissional' && servico.profissional_id === sub);
      if (!ehDono) throw new ErroDeAutenticacao('Você não tem acesso a este serviço.', 403);

      const transacoes = await listarTransacoesDoServico(idServico);
      return res.json(transacoes);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   ETAPA C/D -- POST /pagamentos/:idTransacao/confirmar
   O botão CONFIRM_SERVICE do cliente. Dispara a liberação (split) na hora
   -- síncrona, dentro da própria requisição HTTP (diferente da
   autorização, que tem um webhook como "fonte de verdade" assíncrona; aqui
   é o CLIENTE que decide o momento, não o gateway).
   ========================================================================= */
pagamentosRouter.post(
  '/:idTransacao/confirmar',
  exigirAutenticacao,
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idTransacao = uuidObrigatorio(req.params.idTransacao, 'idTransacao');
      const transacao = await buscarTransacaoPorId(idTransacao);
      if (!transacao) throw new ErroNaoEncontrado('Transação não encontrada.');

      const servico = await buscarServicoPorId(transacao.id_servico);
      if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');
      if (servico.cliente_id !== req.usuario!.sub) {
        throw new ErroDeAutenticacao('Esta transação não pertence a você.', 403);
      }

      if (transacao.status !== 'AUTORIZADA') {
        throw new ErroDeConflito(
          `Só é possível confirmar uma transação "AUTORIZADA". Status atual: "${transacao.status}".`,
        );
      }
      // Etapa C do fluxo pedido: a confirmação vem DEPOIS do profissional
      // finalizar o serviço (a "requisição de finalização" que dispara a
      // notificação para o cliente verificar). Sem essa checagem, o
      // cliente poderia liberar o dinheiro antes do trabalho existir.
      if (servico.status !== 'CONCLUIDO') {
        throw new ErroDeConflito(
          `O profissional ainda não marcou este serviço como concluído (status atual: "${servico.status}"). Aguarde a finalização antes de confirmar o pagamento.`,
        );
      }

      const profissional = await buscarDadosProfissionalParaGateway(servico.profissional_id);
      if (!profissional?.idRecebedorGateway) {
        // Gap de produto, não bug: o profissional precisa ter passado por
        // um onboarding financeiro (criação da subconta no gateway, ver
        // migração 14) ANTES de conseguir receber. Sem isso, não tem para
        // onde transferir -- melhor falhar aqui, alto e claro, do que
        // silenciosamente deixar o dinheiro preso no Escrow sem viés de
        // liberação nenhum.
        throw new ErroDeConflito(
          'O profissional ainda não completou o cadastro financeiro (subconta no gateway de pagamento). Não é possível liberar o repasse agora.',
        );
      }

      const valorRepasse = (
        Number(transacao.valor_servico) - Number(transacao.taxa_plataforma)
      ).toFixed(2);

      await criarTransferenciaSplit({
        idRecebedorGateway: profissional.idRecebedorGateway,
        valorRepasse,
      });

      const liberou = await marcarLiberada(idTransacao, 'AUTORIZADA');
      if (!liberou) {
        throw new ErroDeConflito('O status da transação mudou. Recarregue e tente novamente.');
      }

      // Cashback (checklist item "Cashback") -- gerado depois da
      // liberação confirmada, nunca antes (se a transferência tivesse
      // falhado acima, o `throw` já teria interrompido a rota antes de
      // chegar aqui).
      const valorCashback = multiplicarValorDecimal(transacao.valor_servico, PERCENTUAL_CASHBACK);
      if (Number(valorCashback) > 0) {
        await gerarCashback({
          clienteId: servico.cliente_id,
          idTransacao,
          valor: valorCashback,
        });
      }

      // Nota fiscal (checklist item "Automação Fiscal") -- só cria o
      // REGISTRO pendente; a emissão de verdade é um worker futuro, fora
      // do escopo desta entrega (ver notas-fiscais.repository.ts).
      await criarNotaFiscalPendente({ idServico: servico.id_servico, idTransacao });

      const transacaoFinal = await buscarTransacaoPorId(idTransacao);
      return res.json(transacaoFinal);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   ETAPA C -- POST /pagamentos/:idTransacao/reportar-problema (REPORT_ISSUE)
   Abre a disputa e trava a liberação -- `marcarEmDisputa` só sai de
   AUTORIZADA, então uma transação já LIBERADA não pode mais ser disputada
   por aqui (o checklist não cobre estorno pós-liberação; isso ficaria a
   cargo de um fluxo de reembolso manual/mediação direta com o gateway).
   ========================================================================= */
pagamentosRouter.post(
  '/:idTransacao/reportar-problema',
  exigirAutenticacao,
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idTransacao = uuidObrigatorio(req.params.idTransacao, 'idTransacao');
      const motivo = textoObrigatorio((req.body as Record<string, unknown>).motivo, 'motivo', {
        min: 10,
        max: 1000,
      });

      const transacao = await buscarTransacaoPorId(idTransacao);
      if (!transacao) throw new ErroNaoEncontrado('Transação não encontrada.');

      const servico = await buscarServicoPorId(transacao.id_servico);
      if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');
      if (servico.cliente_id !== req.usuario!.sub) {
        throw new ErroDeAutenticacao('Esta transação não pertence a você.', 403);
      }

      if (transacao.status !== 'AUTORIZADA') {
        throw new ErroDeConflito(
          `Só é possível reportar um problema numa transação "AUTORIZADA". Status atual: "${transacao.status}".`,
        );
      }

      const conseguiuTravar = await marcarEmDisputa(idTransacao);
      if (!conseguiuTravar) {
        throw new ErroDeConflito('O status da transação mudou. Recarregue e tente novamente.');
      }

      const disputa = await abrirDisputa({
        idTransacao,
        idServico: servico.id_servico,
        abertoPorClienteId: req.usuario!.sub,
        motivo,
      });

      return res.status(201).json(disputa);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   WEBHOOK -- POST /pagamentos/webhook

   SEM `exigirAutenticacao` (é o gateway chamando, não um usuário do app) --
   a "autenticação" aqui é a assinatura HMAC, verificada abaixo. Sempre
   responde 200 no final (mesmo quando o evento não é reconhecido ou já foi
   processado antes) -- é o que evita o Pagar.me reenviar o mesmo evento
   indefinidamente achando que falhou.
   ========================================================================= */
pagamentosRouter.post('/webhook', async (req: Request, res: Response) => {
  const assinatura = req.headers['x-hub-signature-256'] as string | undefined;

  if (!req.rawBody || !verificarAssinaturaWebhook(req.rawBody, assinatura)) {
    // 401, não 200: uma assinatura inválida é motivo para o Pagar.me
    // registrar a falha (e permitir reenvio manual pelo painel deles) --
    // diferente de "evento válido, mas já processado", que É 200.
    console.warn('[webhook pagamentos] Assinatura inválida ou ausente -- requisição rejeitada.');
    return res.status(401).json({ erro: 'Assinatura inválida.' });
  }

  const payload = req.body as PayloadWebhookPagarme;

  const evento = await criarEventoWebhook({
    gateway: 'pagarme',
    tipoEvento: payload.event,
    idEventoExterno: payload.id,
    payload,
  });

  if (!evento) {
    // Reentrega do mesmo evento -- já processamos da primeira vez.
    // Idempotência via UNIQUE do banco (ver transacoes.repository.ts).
    return res.status(200).json({ recebido: true, duplicado: true });
  }

  try {
    await processarEventoWebhook(payload);
    await marcarEventoProcessado(evento.id_evento, null);
    return res.status(200).json({ recebido: true });
  } catch (erro) {
    // Loga e devolve 200 mesmo assim -- devolver erro faria o Pagar.me
    // reentregar o MESMO evento indefinidamente, o que não ajuda quando o
    // problema é, por exemplo, a transação correspondente não existir no
    // nosso banco (reenviar não vai fazer ela aparecer). `erro_processamento`
    // fica gravado no evento para investigação manual depois.
    console.error('[webhook pagamentos] Erro ao processar evento:', erro);
    await marcarEventoComErro(evento.id_evento, erro instanceof Error ? erro.message : String(erro));
    return res.status(200).json({ recebido: true, erro_no_processamento: true });
  }
});

/**
 * Interpreta o `event` do payload e aplica a transição de estado
 * correspondente. Eventos que não conhecemos são ignorados silenciosamente
 * (não é erro -- o webhook pode estar configurado para mandar TODOS os
 * eventos da conta, não só os que este código trata).
 *
 * Nomes de evento conferidos contra https://docs.pagar.me/reference/eventos-de-webhook-1
 * (consultado nesta sessão) -- `order.paid`/`order.payment_failed` são os
 * dois que efetivamente usamos; os demais (`charge.*`, `recipient.*`) não
 * têm handler ainda porque o fluxo desta etapa só precisa saber se o
 * PEDIDO como um todo foi pago ou falhou.
 */
async function processarEventoWebhook(payload: PayloadWebhookPagarme): Promise<void> {
  const idPedidoGateway = payload.data.code ?? payload.data.id;
  const transacao = await buscarTransacaoPorIdPedidoGateway(idPedidoGateway);

  if (!transacao) {
    // Pode ser um evento de um pedido que não é nosso (conta compartilhada
    // com outro sistema) ou um evento cujo `data` não é um order/charge
    // reconhecível. Não é erro fatal -- só não há o que fazer aqui.
    console.warn(`[webhook pagamentos] Nenhuma transação encontrada para o pedido "${idPedidoGateway}".`);
    return;
  }

  switch (payload.event) {
    case 'order.paid':
      await marcarAutorizada(transacao.id_transacao);
      break;
    case 'order.payment_failed':
      await marcarFalhou(transacao.id_transacao);
      break;
    default:
      // Evento reconhecido pelo Pagar.me mas sem ação nossa -- ex.:
      // charge.pending (PIX ainda aguardando o cliente pagar, não muda
      // nada do nosso lado até virar order.paid ou order.payment_failed).
      break;
  }
}

/* ============================================================================
   ETAPA B -- gate de pagamento para "Iniciar" -- PRONTO, NÃO WIREADO.

   Middleware pronto para ser inserido em `servicos.routes.ts`, na rota
   `PATCH /servicos/:id/iniciar`:

     servicosRouter.patch(
       '/:id/iniciar',
       exigirPapel('profissional'),
       exigirPagamentoAutorizado,               // <- adicionar esta linha
       criarRotaDeTransicaoDoProfissional({...}),
     );

   NÃO fizemos essa mudança nesta entrega de propósito: `servicos.routes.ts`
   é a rota que o app Flutter EM PRODUÇÃO já usa para o profissional
   iniciar um serviço, e o Flutter ainda não tem NENHUMA tela de checkout
   (nada chama `POST /pagamentos`). Ativar este gate agora bloquearia todo
   profissional de iniciar qualquer serviço, imediatamente, sem que exista
   um jeito do cliente pagar pelo app -- travaria o uso real do produto.
   Fica pronto para quando o checkout do Flutter existir.
   ========================================================================= */
export async function exigirPagamentoAutorizado(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    const idServico = req.params.id;
    const autorizado = await existeTransacaoAutorizada(idServico);
    if (!autorizado) {
      throw new ErroDeConflito(
        'Este serviço ainda não tem um pagamento autorizado. O cliente precisa pagar antes de você poder iniciar.',
      );
    }
    next();
  } catch (erro) {
    next(erro);
  }
}
