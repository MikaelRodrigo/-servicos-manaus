import { Router, Request, Response, NextFunction } from 'express';
import {
  uuidObrigatorio,
  metodoPagamentoObrigatorio,
  valorMonetarioObrigatorio,
  textoOpcional,
  ErroDeConflito,
  ErroNaoEncontrado,
} from '../utils/validacao';
import { exigirAutenticacao, exigirPapel, ErroDeAutenticacao } from '../middlewares/autenticacao';
import { env } from '../env';
import { buscarServicoPorId, marcarServicoConcluidoPeloPagamento, iniciarServico } from '../repositories/servicos.repository';
import { buscarChavePixDoProfissional } from '../repositories/profissionais.repository';
import {
  Transacao,
  buscarTransacaoPorId,
  listarTransacoesDoServico,
  existeTransacaoEmAbertoParaServico,
  criarPropostaTransacao,
  recusarProposta,
  confirmarProposta,
  marcarPagamentoRetido,
  marcarPagamentoRetidoPorCobrancaExterna,
  marcarLiberada,
  confirmarRepasseComissao,
  listarTransacoesPendentesDeRepasse,
  buscarResumoFinanceiroAdmin,
} from '../repositories/transacoes.repository';
import { gerarCobranca, verificarSegredoWebhook } from '../services/pix-proprio';

export const pagamentosRouter = Router();

/* ============================================================================
   MODELO DE INTERMEDIAÇÃO (migração 15) -- substitui por completo o antigo
   fluxo de checkout via Pagar.me (Escrow + Split, migração 14).

   Fluxo completo, na ordem:

     1) POST /pagamentos/propor          -- profissional avalia presencialmente
                                             e propõe um valor (serviço precisa
                                             estar "ACEITO")
     2) POST /pagamentos/:id/confirmar   -- cliente confirma; gera a cobrança
                                             Pix/Boleto na conta do PRÓPRIO
                                             profissional; serviço vira
                                             "EM_ANDAMENTO"
        POST /pagamentos/:id/recusar     -- OU cliente recusa; profissional
                                             pode propor de novo
     3) (o cliente paga a chave gerada, fora do app -- no banco dele)
        POST /pagamentos/webhook         -- a futura API Pix própria avisa
                                             que o pagamento chegou -- OU, em
                                             modo simulado/dev:
        POST /pagamentos/:id/simular-pagamento-recebido
     4) POST /pagamentos/:id/confirmar-termino -- cliente confirma que o
                                             serviço acabou; libera a
                                             retenção; serviço vira
                                             "CONCLUIDO" (o que já libera as
                                             avaliações mútuas, via trigger
                                             existente do banco)
     5) POST /pagamentos/:id/confirmar-repasse -- ADMIN concilia a comissão
                                             (confirma que os 8,9% caíram na
                                             conta da empresa)

   A "taxa de comissão" (env.comissaoPlataformaPercentual) é configurável
   via variável de ambiente -- ver comentário em env.ts. Cada transação
   GRAVA o percentual vigente no momento da proposta (não uma referência
   viva à constante), então o histórico contábil nunca muda retroativamente
   se a taxa for ajustada no futuro.
   ========================================================================= */

/* ============================================================================
   POST /pagamentos/propor
   O profissional avalia o serviço presencialmente e insere o valor no app.

   Body: { id_servico: string (uuid), valor_total: string decimal (ex: "150.00") }
   ========================================================================= */
pagamentosRouter.post(
  '/propor',
  exigirAutenticacao,
  exigirPapel('profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Record<string, unknown>;
      const idServico = uuidObrigatorio(body.id_servico, 'id_servico');
      const valorTotal = valorMonetarioObrigatorio(body.valor_total, 'valor_total');

      const servico = await buscarServicoPorId(idServico);
      if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');
      if (servico.profissional_id !== req.usuario!.sub) {
        throw new ErroDeAutenticacao('Este serviço não pertence a você.', 403);
      }
      if (servico.status !== 'ACEITO') {
        throw new ErroDeConflito(
          `Só é possível propor um valor para um serviço "ACEITO" (você precisa aceitar o serviço primeiro). Status atual: "${servico.status}".`,
        );
      }
      if (await existeTransacaoEmAbertoParaServico(idServico)) {
        throw new ErroDeConflito('Já existe uma proposta em aberto para este serviço.');
      }

      const transacao = await criarPropostaTransacao({
        idServico,
        valorTotal,
        taxaComissaoPercentual: env.comissaoPlataformaPercentual.toString(),
      });

      return res.status(201).json(transacao);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /pagamentos/servico/:idServico -- histórico de propostas/pagamentos
   de UM serviço. Protegido por ownership (cliente OU profissional do
   serviço).
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
        (papel === 'profissional' && servico.profissional_id === sub) ||
        papel === 'admin';
      if (!ehDono) throw new ErroDeAutenticacao('Você não tem acesso a este serviço.', 403);

      const transacoes = await listarTransacoesDoServico(idServico);
      return res.json(transacoes);
    } catch (erro) {
      return next(erro);
    }
  },
);

/**
 * Busca a transação e o serviço, e confere que quem chamou é o CLIENTE
 * dono do serviço -- checagem repetida em confirmar/recusar/confirmar-
 * termino, extraída aqui para não copiar três vezes.
 */
async function buscarTransacaoDoClienteOuFalhar(
  idTransacao: string,
  clienteId: string,
): Promise<Transacao> {
  const transacao = await buscarTransacaoPorId(idTransacao);
  if (!transacao) throw new ErroNaoEncontrado('Transação não encontrada.');

  const servico = await buscarServicoPorId(transacao.id_servico);
  if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');
  if (servico.cliente_id !== clienteId) {
    throw new ErroDeAutenticacao('Esta transação não pertence a você.', 403);
  }
  return transacao;
}

/* ============================================================================
   POST /pagamentos/:idTransacao/recusar -- o cliente recusa o valor proposto.
   ========================================================================= */
pagamentosRouter.post(
  '/:idTransacao/recusar',
  exigirAutenticacao,
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idTransacao = uuidObrigatorio(req.params.idTransacao, 'idTransacao');
      const transacao = await buscarTransacaoDoClienteOuFalhar(idTransacao, req.usuario!.sub);

      if (transacao.status !== 'AGUARDANDO_CONFIRMACAO_CLIENTE') {
        throw new ErroDeConflito(
          `Só é possível recusar uma proposta "AGUARDANDO_CONFIRMACAO_CLIENTE". Status atual: "${transacao.status}".`,
        );
      }

      const conseguiu = await recusarProposta(idTransacao);
      if (!conseguiu) {
        throw new ErroDeConflito('O status da proposta mudou. Recarregue e tente novamente.');
      }

      return res.json(await buscarTransacaoPorId(idTransacao));
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /pagamentos/:idTransacao/confirmar -- o cliente confirma o valor
   proposto. Gera a cobrança na conta do PRÓPRIO profissional (não da
   plataforma) e já atualiza o serviço para "EM_ANDAMENTO".

   Body: { metodo_pagamento: "PIX" | "BOLETO" | "OUTRO" }
   ========================================================================= */
pagamentosRouter.post(
  '/:idTransacao/confirmar',
  exigirAutenticacao,
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idTransacao = uuidObrigatorio(req.params.idTransacao, 'idTransacao');
      const metodoPagamento = metodoPagamentoObrigatorio((req.body as Record<string, unknown>).metodo_pagamento);

      const transacao = await buscarTransacaoDoClienteOuFalhar(idTransacao, req.usuario!.sub);
      if (transacao.status !== 'AGUARDANDO_CONFIRMACAO_CLIENTE') {
        throw new ErroDeConflito(
          `Só é possível confirmar uma proposta "AGUARDANDO_CONFIRMACAO_CLIENTE". Status atual: "${transacao.status}".`,
        );
      }

      const servico = await buscarServicoPorId(transacao.id_servico);
      if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');

      const dadosProfissional = await buscarChavePixDoProfissional(servico.profissional_id);

      const cobranca = await gerarCobranca({
        idTransacao,
        valorTotal: transacao.valor_total,
        metodoPagamento,
        chavePixProfissional: dadosProfissional?.chavePix ?? null,
      });

      const confirmou = await confirmarProposta(idTransacao, {
        metodoPagamento,
        chaveCobranca: cobranca.chaveCobranca,
        idCobrancaExterna: cobranca.idCobrancaExterna,
      });
      if (!confirmou) {
        throw new ErroDeConflito('O status da proposta mudou. Recarregue e tente novamente.');
      }

      // "o status do serviço já se atualiza EM_ANDAMENTO" -- pedido
      // explícito do usuário, no momento em que a chave é gerada (não
      // quando o pagamento efetivamente chega). Reaproveita a mesma
      // transição ACEITO -> EM_ANDAMENTO que `PATCH /servicos/:id/iniciar`
      // usa -- aqui é disparada pela confirmação do CLIENTE, não por uma
      // ação do profissional, por isso chamada diretamente (não pela rota).
      await iniciarServico(servico.id_servico, servico.profissional_id);

      return res.json({
        transacao: await buscarTransacaoPorId(idTransacao),
        chave_cobranca: cobranca.chaveCobranca,
      });
    } catch (erro) {
      // ErroDePixProprio (falha ao gerar a cobrança) cai no mesmo `next`
      // dos demais -- o middleware de erro em app.ts sabe traduzi-lo para 502.
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /pagamentos/:idTransacao/simular-pagamento-recebido -- SÓ EXISTE EM
   MODO SIMULADO (env.pixProprio.baseUrl ausente). Marca a transação como
   RETIDA diretamente, sem esperar um webhook de verdade -- é o jeito de
   testar o fluxo completo (Etapa 4 em diante) antes da API Pix própria
   existir. Em qualquer ambiente com a API própria configurada, esta rota
   responde 404 -- não deveria existir um atalho desses fora de
   desenvolvimento.
   ========================================================================= */
pagamentosRouter.post(
  '/:idTransacao/simular-pagamento-recebido',
  exigirAutenticacao,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      if (env.pixProprio.baseUrl) {
        return res.status(404).json({ erro: 'Rota não encontrada.' });
      }

      const idTransacao = uuidObrigatorio(req.params.idTransacao, 'idTransacao');
      const transacao = await buscarTransacaoPorId(idTransacao);
      if (!transacao) throw new ErroNaoEncontrado('Transação não encontrada.');

      const servico = await buscarServicoPorId(transacao.id_servico);
      if (!servico) throw new ErroNaoEncontrado('Serviço não encontrado.');
      const { sub, papel } = req.usuario!;
      const ehDono =
        (papel === 'cliente' && servico.cliente_id === sub) ||
        (papel === 'profissional' && servico.profissional_id === sub);
      if (!ehDono) throw new ErroDeAutenticacao('Você não tem acesso a esta transação.', 403);

      if (transacao.status !== 'AGUARDANDO_PAGAMENTO') {
        throw new ErroDeConflito(
          `Só é possível simular o pagamento de uma transação "AGUARDANDO_PAGAMENTO". Status atual: "${transacao.status}".`,
        );
      }

      const conseguiu = await marcarPagamentoRetido(idTransacao);
      if (!conseguiu) {
        throw new ErroDeConflito('O status da transação mudou. Recarregue e tente novamente.');
      }

      return res.json(await buscarTransacaoPorId(idTransacao));
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /pagamentos/:idTransacao/confirmar-termino -- o botão "Confirmar
   término do serviço" do cliente. Libera a retenção e conclui o serviço --
   é isso que libera as avaliações mútuas (o schema já garante isso com um
   trigger em `servicos.status = 'CONCLUIDO'`, nada a fazer aqui além de
   chegar nesse status).
   ========================================================================= */
pagamentosRouter.post(
  '/:idTransacao/confirmar-termino',
  exigirAutenticacao,
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idTransacao = uuidObrigatorio(req.params.idTransacao, 'idTransacao');
      const transacao = await buscarTransacaoDoClienteOuFalhar(idTransacao, req.usuario!.sub);

      if (transacao.status !== 'RETIDA') {
        throw new ErroDeConflito(
          `Só é possível confirmar o término com a transação "RETIDA" (pagamento já recebido). Status atual: "${transacao.status}".`,
        );
      }

      const liberou = await marcarLiberada(idTransacao);
      if (!liberou) {
        throw new ErroDeConflito('O status da transação mudou. Recarregue e tente novamente.');
      }

      const concluiu = await marcarServicoConcluidoPeloPagamento(transacao.id_servico);
      if (!concluiu) {
        // Não desfaz a liberação -- o dinheiro já estava "quase liberado"
        // do lado financeiro; um serviço que não estava mais EM_ANDAMENTO
        // (ex.: cancelado por uma corrida rara) é uma inconsistência a
        // investigar manualmente, não motivo para reverter a liberação.
        console.warn(
          `[pagamentos] Transação ${idTransacao} liberada, mas o serviço ${transacao.id_servico} não estava mais EM_ANDAMENTO ao concluir.`,
        );
      }

      return res.json(await buscarTransacaoPorId(idTransacao));
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   WEBHOOK -- POST /pagamentos/webhook

   Chamado pela futura API Pix própria, avisando que um pagamento chegou.
   SEM `exigirAutenticacao` (é a API externa chamando, não um usuário do
   app) -- a "autenticação" é o segredo compartilhado no header
   `X-Webhook-Secret`, verificado abaixo. Formato do payload e do header
   são PROVISÓRIOS -- ver o comentário completo em `services/pix-proprio.ts`.
   ========================================================================= */
pagamentosRouter.post('/webhook', async (req: Request, res: Response) => {
  const segredo = req.headers['x-webhook-secret'] as string | undefined;

  if (!verificarSegredoWebhook(segredo)) {
    console.warn('[webhook pagamentos] Segredo inválido ou ausente -- requisição rejeitada.');
    return res.status(401).json({ erro: 'Segredo inválido.' });
  }

  const payload = req.body as { id_cobranca_externa?: string; status?: string };
  if (!payload.id_cobranca_externa || !payload.status) {
    return res.status(400).json({ erro: 'Payload inválido -- esperado { id_cobranca_externa, status }.' });
  }

  if (payload.status === 'pago') {
    const marcou = await marcarPagamentoRetidoPorCobrancaExterna(payload.id_cobranca_externa);
    if (!marcou) {
      console.warn(
        `[webhook pagamentos] Nenhuma transação AGUARDANDO_PAGAMENTO encontrada para a cobrança "${payload.id_cobranca_externa}".`,
      );
    }
  }
  // Outros status (ex.: "falhou") não têm ação automática ainda -- fica
  // registrado só no log; decisão de produto futura se algo deve acontecer
  // (ex.: voltar a proposta para o profissional propor de novo).

  return res.status(200).json({ recebido: true });
});

/* ============================================================================
   ADMIN -- conciliação da comissão (pedido explícito: "crie a conta do adm
   para fazer gerenciar" + "marcar as transações como Repassadas").
   ========================================================================= */

/** GET /pagamentos/admin/resumo -- "Saldo de Repasse"/"Saldo de Comissão" do dashboard. */
pagamentosRouter.get(
  '/admin/resumo',
  exigirAutenticacao,
  exigirPapel('admin'),
  async (_req: Request, res: Response, next: NextFunction) => {
    try {
      return res.json(await buscarResumoFinanceiroAdmin());
    } catch (erro) {
      return next(erro);
    }
  },
);

/** GET /pagamentos/admin/pendentes-repasse -- fila de conciliação. */
pagamentosRouter.get(
  '/admin/pendentes-repasse',
  exigirAutenticacao,
  exigirPapel('admin'),
  async (_req: Request, res: Response, next: NextFunction) => {
    try {
      return res.json(await listarTransacoesPendentesDeRepasse());
    } catch (erro) {
      return next(erro);
    }
  },
);

/**
 * POST /pagamentos/:idTransacao/confirmar-repasse -- o admin marca a
 * comissão desta transação como conciliada (o Pix manual/API bancária que
 * o usuário fizer por fora já caiu na conta da empresa).
 *
 * Body: { referencia?: string } -- anotação livre para bater com o
 * extrato do banco depois (ex.: um ID de comprovante).
 */
pagamentosRouter.post(
  '/:idTransacao/confirmar-repasse',
  exigirAutenticacao,
  exigirPapel('admin'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idTransacao = uuidObrigatorio(req.params.idTransacao, 'idTransacao');
      const referencia = textoOpcional((req.body as Record<string, unknown>).referencia, 'referencia', 200);

      const transacao = await buscarTransacaoPorId(idTransacao);
      if (!transacao) throw new ErroNaoEncontrado('Transação não encontrada.');

      if (transacao.status !== 'LIBERADA' || transacao.status_repasse !== 'PENDENTE') {
        throw new ErroDeConflito(
          `Só é possível conciliar uma transação "LIBERADA" com repasse "PENDENTE". Status atual: "${transacao.status}" / "${transacao.status_repasse}".`,
        );
      }

      const conseguiu = await confirmarRepasseComissao(idTransacao, {
        adminId: req.usuario!.sub,
        referencia,
      });
      if (!conseguiu) {
        throw new ErroDeConflito('O status da transação mudou. Recarregue e tente novamente.');
      }

      return res.json(await buscarTransacaoPorId(idTransacao));
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   ETAPA B (legado) -- gate de pagamento para "Iniciar", NÃO USADO no novo
   fluxo (a transição ACEITO -> EM_ANDAMENTO agora acontece dentro de
   `POST /pagamentos/:idTransacao/confirmar`, acima -- ver o comentário
   nessa rota). Mantido comentado só como referência histórica de por que
   `PATCH /servicos/:id/iniciar` nunca foi gateada por pagamento: essa rota
   continua existindo solta (para outros usos manuais/administrativos), mas
   o caminho normal do app não passa mais por ela.
   ========================================================================= */
