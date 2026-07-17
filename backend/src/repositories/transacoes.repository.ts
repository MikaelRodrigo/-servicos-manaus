import { pool } from '../database';
import { MetodoPagamento, StatusTransacao } from '../utils/validacao';

/* ============================================================================
   O QUE ESTE ARQUIVO FAZ

   Máquina de estados de `transacoes` (Etapas A/C/D do fluxo de pagamento) +
   `retencoes_escrow` (1:1 com toda transação AUTORIZADA) + o log de
   idempotência de webhook (`eventos_webhook_pagamento`) -- os três vivem
   juntos aqui porque toda transição de `transacoes.status` mexe também
   numa das outras duas tabelas na MESMA operação lógica (autorizar cria a
   retenção; liberar fecha a retenção; todo evento de webhook processado
   está sempre ligado a uma transação).

     PENDENTE --(gateway autoriza)--> AUTORIZADA --(cliente confirma)--> LIBERADA
     PENDENTE --(gateway recusa)--> FALHOU
     AUTORIZADA --(REPORT_ISSUE)--> EM_DISPUTA --(mediação)--> LIBERADA | REEMBOLSADA

   Mesmo padrão de `atualizarStatusCondicional` de `servicos.repository.ts`:
   todo UPDATE de status é condicional (`WHERE status = 'ESPERADO'`) e
   devolve `boolean` via `rowCount` -- nunca lança para "não estava no
   estado esperado", quem decide o HTTP correto é a rota.

   VALORES MONETÁRIOS: toda coluna NUMERIC é lida com `::text` explícito
   (nunca cai no parser float global de `database.ts`) e escrita como
   string -- ver o comentário completo em `utils/dinheiro.ts`.
   ========================================================================= */

export interface Transacao {
  id_transacao: string;
  id_servico: string;
  status: StatusTransacao;
  metodo_pagamento: MetodoPagamento;
  parcelas: number;
  valor_servico: string;
  taxa_parcelamento: string;
  valor_total_cobrado: string;
  taxa_plataforma: string;
  valor_repasse_profissional: string | null;
  id_pedido_gateway: string | null;
  id_cobranca_gateway: string | null;
  id_transacao_gateway: string | null;
  autorizada_em: string | null;
  liberada_em: string | null;
  created_at: string;
  updated_at: string;
}

const SELECT_TRANSACAO = `
  SELECT
    id_transacao,
    id_servico,
    status,
    metodo_pagamento,
    parcelas,
    valor_servico::text,
    taxa_parcelamento::text,
    valor_total_cobrado::text,
    taxa_plataforma::text,
    valor_repasse_profissional::text,
    id_pedido_gateway,
    id_cobranca_gateway,
    id_transacao_gateway,
    autorizada_em,
    liberada_em,
    created_at,
    updated_at
  FROM transacoes
`;

export async function buscarTransacaoPorId(idTransacao: string): Promise<Transacao | null> {
  const { rows } = await pool.query<Transacao>(`${SELECT_TRANSACAO} WHERE id_transacao = $1`, [
    idTransacao,
  ]);
  return rows[0] ?? null;
}

/** Todas as tentativas de pagamento de um serviço, mais recente primeiro. */
export async function listarTransacoesDoServico(idServico: string): Promise<Transacao[]> {
  const { rows } = await pool.query<Transacao>(
    `${SELECT_TRANSACAO} WHERE id_servico = $1 ORDER BY created_at DESC`,
    [idServico],
  );
  return rows;
}

/** Usado pelo handler de webhook para achar a transação a partir do `code`/`order.id` do Pagar.me. */
export async function buscarTransacaoPorIdPedidoGateway(
  idPedidoGateway: string,
): Promise<Transacao | null> {
  const { rows } = await pool.query<Transacao>(
    `${SELECT_TRANSACAO} WHERE id_pedido_gateway = $1`,
    [idPedidoGateway],
  );
  return rows[0] ?? null;
}

/**
 * Uma transação "em aberto" (PENDENTE ou AUTORIZADA) para o mesmo serviço
 * -- usada para recusar uma SEGUNDA tentativa de pagamento enquanto a
 * primeira ainda não falhou/foi liberada. Sem essa checagem, um duplo
 * clique no botão "pagar" criaria duas cobranças para o mesmo serviço.
 */
export async function existeTransacaoEmAbertoParaServico(idServico: string): Promise<boolean> {
  const { rows } = await pool.query(
    `SELECT 1 FROM transacoes
      WHERE id_servico = $1
        AND status = ANY(ARRAY['PENDENTE','AUTORIZADA','EM_DISPUTA']::status_transacao_enum[])
      LIMIT 1`,
    [idServico],
  );
  return rows.length > 0;
}

/**
 * `true` se existir alguma transação AUTORIZADA (ou já LIBERADA -- o
 * profissional obviamente pode iniciar se o pagamento já foi liberado
 * também, embora esse caminho não devesse acontecer na ordem normal do
 * fluxo) para este serviço. É a checagem que `exigirPagamentoAutorizado`
 * (rotas de pagamento) usaria para liberar a Etapa B ("Iniciar") -- ver o
 * comentário sobre por que esse middleware existe mas NÃO está wireado em
 * `servicos.routes.ts` ainda.
 */
export async function existeTransacaoAutorizada(idServico: string): Promise<boolean> {
  const { rows } = await pool.query(
    `SELECT 1 FROM transacoes
      WHERE id_servico = $1
        AND status = ANY(ARRAY['AUTORIZADA','LIBERADA']::status_transacao_enum[])
      LIMIT 1`,
    [idServico],
  );
  return rows.length > 0;
}

export interface DadosNovaTransacao {
  idServico: string;
  metodoPagamento: MetodoPagamento;
  parcelas: number;
  /** String decimal, ex. "49.90" -- ver utils/dinheiro.ts. */
  valorServico: string;
  /** String decimal, DEFAULT "0" -- taxa de antecipação/parcelamento (Etapa A). */
  taxaParcelamento: string;
  /** String decimal, DEFAULT "0" -- taxa da plataforma. */
  taxaPlataforma: string;
}

/** Cria a transação em PENDENTE (Etapa A, antes de chamar o gateway). */
export async function criarTransacaoPendente(dados: DadosNovaTransacao): Promise<Transacao> {
  const { rows } = await pool.query<{ id_transacao: string }>(
    `INSERT INTO transacoes
       (id_servico, metodo_pagamento, parcelas, valor_servico, taxa_parcelamento, taxa_plataforma)
     VALUES ($1, $2::metodo_pagamento_enum, $3, $4::numeric, $5::numeric, $6::numeric)
     RETURNING id_transacao`,
    [
      dados.idServico,
      dados.metodoPagamento,
      dados.parcelas,
      dados.valorServico,
      dados.taxaParcelamento,
      dados.taxaPlataforma,
    ],
  );

  const transacao = await buscarTransacaoPorId(rows[0].id_transacao);
  return transacao as Transacao; // acabamos de inserir, não pode ser null
}

/** Grava os IDs do gateway assim que a chamada de autorização volta (mesmo antes de saber se foi aceita ou recusada) -- útil para o webhook conseguir casar o evento mesmo que ele chegue ANTES da nossa própria resposta HTTP terminar de processar. */
export async function gravarIdsDoGateway(
  idTransacao: string,
  ids: { idPedidoGateway: string; idCobrancaGateway: string; idTransacaoGateway: string | null },
): Promise<void> {
  await pool.query(
    `UPDATE transacoes
        SET id_pedido_gateway = $2, id_cobranca_gateway = $3, id_transacao_gateway = $4
      WHERE id_transacao = $1`,
    [idTransacao, ids.idPedidoGateway, ids.idCobrancaGateway, ids.idTransacaoGateway],
  );
}

/**
 * PENDENTE -> AUTORIZADA + cria a retenção no Escrow, na MESMA transação
 * de banco (`BEGIN`/`COMMIT` explícitos -- diferente do resto do projeto,
 * que usa só `pool.query` avulso, porque aqui DUAS tabelas precisam mudar
 * atomicamente: se a retenção falhasse ao inserir depois do UPDATE de
 * status já ter commitado, a transação ficaria "AUTORIZADA" sem nenhum
 * registro de quanto está retido -- um estado inconsistente que nenhuma
 * query de leitura detectaria sozinha).
 */
export async function marcarAutorizada(idTransacao: string): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows, rowCount } = await client.query<{ valor_total_cobrado: string }>(
      `UPDATE transacoes
          SET status = 'AUTORIZADA'::status_transacao_enum,
              autorizada_em = NOW()
        WHERE id_transacao = $1
          AND status = 'PENDENTE'::status_transacao_enum
        RETURNING valor_total_cobrado::text`,
      [idTransacao],
    );

    if ((rowCount ?? 0) === 0) {
      await client.query('ROLLBACK');
      return false;
    }

    await client.query(
      `INSERT INTO retencoes_escrow (id_transacao, valor_retido)
       VALUES ($1, $2::numeric)`,
      [idTransacao, rows[0].valor_total_cobrado],
    );

    await client.query('COMMIT');
    return true;
  } catch (erro) {
    await client.query('ROLLBACK');
    throw erro;
  } finally {
    client.release();
  }
}

export function marcarFalhou(idTransacao: string): Promise<boolean> {
  return atualizarStatusSimples(idTransacao, 'PENDENTE', 'FALHOU');
}

export function marcarEmDisputa(idTransacao: string): Promise<boolean> {
  return atualizarStatusSimples(idTransacao, 'AUTORIZADA', 'EM_DISPUTA');
}

/**
 * AUTORIZADA (ou EM_DISPUTA, quando uma mediação resolve a favor do
 * profissional) -> LIBERADA, grava o valor de repasse e fecha a retenção
 * do Escrow -- de novo, tudo numa transação de banco só.
 *
 * O valor de repasse é SEMPRE `valor_servico - taxa_plataforma`, calculado
 * em SQL (aritmética NUMERIC exata, nunca em JS -- ver utils/dinheiro.ts
 * sobre por que). Uma versão anterior desta função aceitava um valor
 * "override" para o caso de uma disputa com desconto por dano -- removido
 * de propósito junto com o resto dessa funcionalidade (ver o comentário no
 * topo de disputas.repository.ts).
 */
export async function marcarLiberada(
  idTransacao: string,
  statusEsperado: 'AUTORIZADA' | 'EM_DISPUTA',
): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rowCount } = await client.query(
      `UPDATE transacoes
          SET status = 'LIBERADA'::status_transacao_enum,
              liberada_em = NOW(),
              valor_repasse_profissional = valor_servico - taxa_plataforma
        WHERE id_transacao = $1
          AND status = $2::status_transacao_enum
        RETURNING id_transacao`,
      [idTransacao, statusEsperado],
    );

    if ((rowCount ?? 0) === 0) {
      await client.query('ROLLBACK');
      return false;
    }

    await client.query(
      `UPDATE retencoes_escrow
          SET status = 'LIBERADO'::status_escrow_enum,
              liberado_em = NOW()
        WHERE id_transacao = $1
          AND status = 'RETIDO'::status_escrow_enum`,
      [idTransacao],
    );

    await client.query('COMMIT');
    return true;
  } catch (erro) {
    await client.query('ROLLBACK');
    throw erro;
  } finally {
    client.release();
  }
}

async function atualizarStatusSimples(
  idTransacao: string,
  statusEsperado: StatusTransacao,
  novoStatus: StatusTransacao,
): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE transacoes
        SET status = $1::status_transacao_enum
      WHERE id_transacao = $2
        AND status = $3::status_transacao_enum`,
    [novoStatus, idTransacao, statusEsperado],
  );
  return (rowCount ?? 0) > 0;
}

/* ============================================================================
   EVENTOS DE WEBHOOK -- idempotência

   `criarEventoWebhook` devolve `null` (em vez de lançar) quando o INSERT
   bate no UNIQUE de `id_evento_externo` -- é o sinal de "este evento já
   foi recebido antes" que o handler da rota usa para responder 200 sem
   reprocessar nada.
   ========================================================================= */

export async function criarEventoWebhook(dados: {
  gateway: string;
  tipoEvento: string;
  idEventoExterno: string;
  payload: unknown;
}): Promise<{ id_evento: string } | null> {
  try {
    const { rows } = await pool.query<{ id_evento: string }>(
      `INSERT INTO eventos_webhook_pagamento (gateway, tipo_evento, id_evento_externo, payload)
       VALUES ($1, $2, $3, $4::jsonb)
       RETURNING id_evento`,
      [dados.gateway, dados.tipoEvento, dados.idEventoExterno, JSON.stringify(dados.payload)],
    );
    return rows[0];
  } catch (erro) {
    if (ehViolacaoDeUnicidade(erro)) {
      return null; // reentrega do mesmo evento -- idempotência via UNIQUE do banco
    }
    throw erro;
  }
}

function ehViolacaoDeUnicidade(erro: unknown): boolean {
  return typeof erro === 'object' && erro !== null && 'code' in erro && (erro as { code: string }).code === '23505';
}

export async function marcarEventoProcessado(idEvento: string, idTransacao: string | null): Promise<void> {
  await pool.query(
    `UPDATE eventos_webhook_pagamento
        SET processado_em = NOW(), id_transacao = $2
      WHERE id_evento = $1`,
    [idEvento, idTransacao],
  );
}

export async function marcarEventoComErro(idEvento: string, mensagemErro: string): Promise<void> {
  await pool.query(
    `UPDATE eventos_webhook_pagamento SET erro_processamento = $2 WHERE id_evento = $1`,
    [idEvento, mensagemErro.slice(0, 2000)],
  );
}
