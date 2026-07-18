import { pool } from '../database';
import { MetodoPagamento, StatusTransacao, StatusRepasse } from '../utils/validacao';

/* ============================================================================
   O QUE ESTE ARQUIVO FAZ

   Máquina de estados de `transacoes` no modelo de intermediação (migração
   15 -- substitui por completo o modelo de Escrow/Split via Pagar.me da
   migração 14):

     AGUARDANDO_CONFIRMACAO_CLIENTE --(cliente recusa)--> RECUSADA
     AGUARDANDO_CONFIRMACAO_CLIENTE --(cliente confirma)--> AGUARDANDO_PAGAMENTO
     AGUARDANDO_PAGAMENTO --(API Pix própria confirma o pagamento)--> RETIDA
     RETIDA --(cliente confirma término do serviço)--> LIBERADA
     AGUARDANDO_CONFIRMACAO_CLIENTE | AGUARDANDO_PAGAMENTO --(serviço cancelado)--> CANCELADA

   Mesmo padrão de `atualizarStatusCondicional` de `servicos.repository.ts`:
   todo UPDATE de status é condicional (`WHERE status = 'ESPERADO'`) e
   devolve `boolean` via `rowCount` -- nunca lança para "não estava no
   estado esperado", quem decide o HTTP correto é a rota.

   VALORES MONETÁRIOS: toda coluna NUMERIC é lida com `::text` explícito
   (nunca cai no parser float global de `database.ts`) e escrita como
   string -- ver o comentário completo em `utils/dinheiro.ts`. `taxa_comissao`
   e `valor_repasse` são GENERATED pelo banco (ver migração 15) -- nunca
   aparecem do lado esquerdo de um INSERT/UPDATE aqui.
   ========================================================================= */

export interface Transacao {
  id_transacao: string;
  id_servico: string;
  status: StatusTransacao;

  valor_total: string;
  taxa_comissao_percentual: string;
  taxa_comissao: string;
  valor_repasse: string;

  proposto_em: string;
  respondido_em: string | null;

  metodo_pagamento: MetodoPagamento | null;
  chave_cobranca: string | null;
  id_cobranca_externa: string | null;

  pago_em: string | null;
  liberado_em: string | null;

  status_repasse: StatusRepasse;
  repasse_confirmado_em: string | null;
  repasse_confirmado_por_admin_id: string | null;
  referencia_repasse: string | null;

  created_at: string;
  updated_at: string;
}

const SELECT_TRANSACAO = `
  SELECT
    id_transacao,
    id_servico,
    status,
    valor_total::text,
    taxa_comissao_percentual::text,
    taxa_comissao::text,
    valor_repasse::text,
    proposto_em,
    respondido_em,
    metodo_pagamento,
    chave_cobranca,
    id_cobranca_externa,
    pago_em,
    liberado_em,
    status_repasse,
    repasse_confirmado_em,
    repasse_confirmado_por_admin_id,
    referencia_repasse,
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

/** Usado pelo handler de webhook para achar a transação a partir do id de cobrança da API Pix própria. */
export async function buscarTransacaoPorIdCobrancaExterna(
  idCobrancaExterna: string,
): Promise<Transacao | null> {
  const { rows } = await pool.query<Transacao>(
    `${SELECT_TRANSACAO} WHERE id_cobranca_externa = $1`,
    [idCobrancaExterna],
  );
  return rows[0] ?? null;
}

/** Todas as tentativas de proposta/pagamento de um serviço, mais recente primeiro. */
export async function listarTransacoesDoServico(idServico: string): Promise<Transacao[]> {
  const { rows } = await pool.query<Transacao>(
    `${SELECT_TRANSACAO} WHERE id_servico = $1 ORDER BY created_at DESC`,
    [idServico],
  );
  return rows;
}

/**
 * Uma transação "em aberto" (ainda não recusada/cancelada, e ainda não
 * liberada) para o mesmo serviço -- usada para recusar uma SEGUNDA proposta
 * de valor enquanto a primeira ainda está em curso. Sem essa checagem, o
 * profissional poderia propor dois valores diferentes ao mesmo tempo para o
 * mesmo serviço.
 */
export async function existeTransacaoEmAbertoParaServico(idServico: string): Promise<boolean> {
  const { rows } = await pool.query(
    `SELECT 1 FROM transacoes
      WHERE id_servico = $1
        AND status = ANY(ARRAY['AGUARDANDO_CONFIRMACAO_CLIENTE','AGUARDANDO_PAGAMENTO','RETIDA']::status_transacao_enum[])
      LIMIT 1`,
    [idServico],
  );
  return rows.length > 0;
}

export interface DadosNovaProposta {
  idServico: string;
  /** String decimal, ex. "150.00" -- o valor que o profissional avaliou presencialmente. */
  valorTotal: string;
  /** String decimal, ex. "8.9" -- o percentual VIGENTE no momento desta proposta (ver env.comissaoPlataformaPercentual). */
  taxaComissaoPercentual: string;
}

/** Cria a proposta de valor (o profissional avalia o serviço e insere o preço). */
export async function criarPropostaTransacao(dados: DadosNovaProposta): Promise<Transacao> {
  const { rows } = await pool.query<{ id_transacao: string }>(
    `INSERT INTO transacoes (id_servico, valor_total, taxa_comissao_percentual)
     VALUES ($1, $2::numeric, $3::numeric)
     RETURNING id_transacao`,
    [dados.idServico, dados.valorTotal, dados.taxaComissaoPercentual],
  );

  const transacao = await buscarTransacaoPorId(rows[0].id_transacao);
  return transacao as Transacao; // acabamos de inserir, não pode ser null
}

/** O cliente recusa o valor proposto -- fim de linha para esta tentativa; o profissional pode propor outra. */
export async function recusarProposta(idTransacao: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE transacoes
        SET status = 'RECUSADA'::status_transacao_enum,
            respondido_em = NOW()
      WHERE id_transacao = $1
        AND status = 'AGUARDANDO_CONFIRMACAO_CLIENTE'::status_transacao_enum`,
    [idTransacao],
  );
  return (rowCount ?? 0) > 0;
}

export interface DadosConfirmacao {
  metodoPagamento: MetodoPagamento;
  chaveCobranca: string;
  idCobrancaExterna: string;
}

/**
 * O cliente confirma o valor proposto -- gera a cobrança (Pix/Boleto) na
 * conta do profissional. AGUARDANDO_CONFIRMACAO_CLIENTE -> AGUARDANDO_PAGAMENTO.
 * A rota chama isto DEPOIS de já ter chamado `services/pix-proprio.ts`
 * (`gerarCobranca`) -- este repository só grava o resultado, nunca fala com
 * a API externa.
 */
export async function confirmarProposta(
  idTransacao: string,
  dados: DadosConfirmacao,
): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE transacoes
        SET status = 'AGUARDANDO_PAGAMENTO'::status_transacao_enum,
            respondido_em = NOW(),
            metodo_pagamento = $2::metodo_pagamento_enum,
            chave_cobranca = $3,
            id_cobranca_externa = $4
      WHERE id_transacao = $1
        AND status = 'AGUARDANDO_CONFIRMACAO_CLIENTE'::status_transacao_enum`,
    [idTransacao, dados.metodoPagamento, dados.chaveCobranca, dados.idCobrancaExterna],
  );
  return (rowCount ?? 0) > 0;
}

/**
 * A API Pix própria confirma que o pagamento chegou (retido na fonte, na
 * conta do profissional). AGUARDANDO_PAGAMENTO -> RETIDA. Chamada pelo
 * webhook (`POST /pagamentos/webhook`) ou, em modo simulado/desenvolvimento,
 * pela rota `POST /pagamentos/:id/simular-pagamento-recebido`.
 */
export async function marcarPagamentoRetido(idTransacao: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE transacoes
        SET status = 'RETIDA'::status_transacao_enum,
            pago_em = NOW()
      WHERE id_transacao = $1
        AND status = 'AGUARDANDO_PAGAMENTO'::status_transacao_enum`,
    [idTransacao],
  );
  return (rowCount ?? 0) > 0;
}

export function marcarPagamentoRetidoPorCobrancaExterna(
  idCobrancaExterna: string,
): Promise<boolean> {
  return pool
    .query(
      `UPDATE transacoes
          SET status = 'RETIDA'::status_transacao_enum,
              pago_em = NOW()
        WHERE id_cobranca_externa = $1
          AND status = 'AGUARDANDO_PAGAMENTO'::status_transacao_enum`,
      [idCobrancaExterna],
    )
    .then(({ rowCount }) => (rowCount ?? 0) > 0);
}

/**
 * O cliente confirma o término do serviço -- libera a retenção. Na prática
 * o dinheiro já está na conta do profissional desde `RETIDA` (ele nunca
 * "sai" da conta dele nesse modelo); liberar só significa que ele deixa de
 * estar congelado, e a comissão (8,9%) passa a ser devida à plataforma.
 * RETIDA -> LIBERADA.
 */
export async function marcarLiberada(idTransacao: string): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE transacoes
        SET status = 'LIBERADA'::status_transacao_enum,
            liberado_em = NOW()
      WHERE id_transacao = $1
        AND status = 'RETIDA'::status_transacao_enum`,
    [idTransacao],
  );
  return (rowCount ?? 0) > 0;
}

/**
 * Cancela toda transação AINDA NÃO PAGA de um serviço (chamada quando o
 * serviço em si é cancelado). Limitada a AGUARDANDO_CONFIRMACAO_CLIENTE e
 * AGUARDANDO_PAGAMENTO DE PROPÓSITO -- uma transação já `RETIDA` significa
 * que o dinheiro já chegou na conta do profissional; cancelar isso não é
 * uma operação de banco de dados, é um estorno de verdade que precisa de
 * intervenção manual/admin, fora do escopo deste UPDATE.
 */
export async function cancelarTransacoesAbertasDoServico(idServico: string): Promise<number> {
  const { rowCount } = await pool.query(
    `UPDATE transacoes
        SET status = 'CANCELADA'::status_transacao_enum,
            respondido_em = COALESCE(respondido_em, NOW())
      WHERE id_servico = $1
        AND status = ANY(ARRAY['AGUARDANDO_CONFIRMACAO_CLIENTE','AGUARDANDO_PAGAMENTO']::status_transacao_enum[])`,
    [idServico],
  );
  return rowCount ?? 0;
}

/* ============================================================================
   CONCILIAÇÃO DA COMISSÃO (admin) -- pedido explícito: "status_repasse
   (pendente/concluído)", reinterpretado para este modelo como a comissão da
   PLATAFORMA (não um repasse ao profissional -- ver comentário na migração
   15). Só um admin confirma; ver `middlewares/autenticacao.ts` (`exigirPapel('admin')`).
   ========================================================================= */

export interface DadosConciliacaoRepasse {
  adminId: string;
  referencia?: string;
}

export async function confirmarRepasseComissao(
  idTransacao: string,
  dados: DadosConciliacaoRepasse,
): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE transacoes
        SET status_repasse = 'CONCLUIDO'::status_repasse_enum,
            repasse_confirmado_em = NOW(),
            repasse_confirmado_por_admin_id = $2,
            referencia_repasse = $3
      WHERE id_transacao = $1
        AND status = 'LIBERADA'::status_transacao_enum
        AND status_repasse = 'PENDENTE'::status_repasse_enum`,
    [idTransacao, dados.adminId, dados.referencia ?? null],
  );
  return (rowCount ?? 0) > 0;
}

/** Fila de conciliação do admin -- toda transação já LIBERADA cuja comissão ainda não foi confirmada como recebida. */
export async function listarTransacoesPendentesDeRepasse(): Promise<Transacao[]> {
  const { rows } = await pool.query<Transacao>(
    `${SELECT_TRANSACAO}
      WHERE status = 'LIBERADA'::status_transacao_enum
        AND status_repasse = 'PENDENTE'::status_repasse_enum
      ORDER BY liberado_em ASC`,
  );
  return rows;
}

/**
 * Resumo financeiro para o dashboard do admin -- "Saldo de Comissão"
 * (pedido explícito do usuário). `comissao_pendente` é o que ainda falta
 * conciliar; `comissao_conciliada` é o que já foi confirmado como recebido.
 * Somas feitas em SQL (aritmética NUMERIC exata), nunca em JS.
 */
export interface ResumoFinanceiroAdmin {
  comissao_pendente: string;
  comissao_conciliada: string;
  valor_repasse_total_liberado: string;
  quantidade_liberada: number;
}

export async function buscarResumoFinanceiroAdmin(): Promise<ResumoFinanceiroAdmin> {
  const { rows } = await pool.query<{
    comissao_pendente: string;
    comissao_conciliada: string;
    valor_repasse_total_liberado: string;
    quantidade_liberada: string;
  }>(
    `SELECT
       COALESCE(SUM(taxa_comissao) FILTER (WHERE status_repasse = 'PENDENTE'), 0)::text  AS comissao_pendente,
       COALESCE(SUM(taxa_comissao) FILTER (WHERE status_repasse = 'CONCLUIDO'), 0)::text AS comissao_conciliada,
       COALESCE(SUM(valor_repasse), 0)::text                                             AS valor_repasse_total_liberado,
       COUNT(*)::text                                                                    AS quantidade_liberada
     FROM transacoes
     WHERE status = 'LIBERADA'::status_transacao_enum`,
  );
  const linha = rows[0];
  return {
    comissao_pendente: linha.comissao_pendente,
    comissao_conciliada: linha.comissao_conciliada,
    valor_repasse_total_liberado: linha.valor_repasse_total_liberado,
    quantidade_liberada: Number(linha.quantidade_liberada),
  };
}
