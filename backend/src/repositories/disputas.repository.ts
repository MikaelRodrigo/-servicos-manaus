import { pool } from '../database';
import { StatusDisputa } from '../utils/validacao';

/* ============================================================================
   `disputas_transacao` (migração 14, mantida pela migração 15) -- o ticket
   de mediação aberto pelo cliente. Este arquivo só cobre ABERTURA e
   RESOLUÇÃO manual da disputa -- desde a migração 15 já existe um papel
   "admin" (`Papel = 'cliente' | 'profissional' | 'admin'`, ver utils/jwt.ts)
   capaz de proteger uma rota de resolução (`exigirPapel('admin')`), mas
   NENHUMA ROTA chama `resolverDisputa` ainda -- o novo fluxo de pagamento
   (migração 15, `routes/pagamentos.routes.ts`) não reabriu a integração de
   disputas (não fazia parte do pedido que motivou a remoção do Pagar.me).
   Fica pronta para quando isso for retomado.

   REMOVIDO DE PROPÓSITO: o cálculo automático de dano (desconto de 30% do
   profissional / reembolso de 20% extra da plataforma) que uma versão
   anterior tinha aqui -- decisão explícita de tirar essa funcionalidade,
   tanto do banco (ver migração 14) quanto deste repository.
   ========================================================================= */

export interface Disputa {
  id_disputa: string;
  id_transacao: string;
  id_servico: string;
  aberto_por_cliente_id: string;
  motivo: string;
  status: StatusDisputa;
  resolucao_observacao: string | null;
  resolvido_em: string | null;
  created_at: string;
  updated_at: string;
}

const SELECT_DISPUTA = `
  SELECT
    id_disputa, id_transacao, id_servico, aberto_por_cliente_id, motivo, status,
    resolucao_observacao, resolvido_em, created_at, updated_at
  FROM disputas_transacao
`;

export async function buscarDisputaPorId(idDisputa: string): Promise<Disputa | null> {
  const { rows } = await pool.query<Disputa>(`${SELECT_DISPUTA} WHERE id_disputa = $1`, [idDisputa]);
  return rows[0] ?? null;
}

export async function buscarDisputaAbertaDaTransacao(idTransacao: string): Promise<Disputa | null> {
  const { rows } = await pool.query<Disputa>(
    `${SELECT_DISPUTA}
      WHERE id_transacao = $1
        AND status = ANY(ARRAY['ABERTA','EM_MEDIACAO']::status_disputa_enum[])
      ORDER BY created_at DESC
      LIMIT 1`,
    [idTransacao],
  );
  return rows[0] ?? null;
}

/**
 * Abre o ticket (REPORT_ISSUE). NÃO muda `transacoes.status` sozinha --
 * quem chama (a rota) é responsável por também chamar
 * `marcarEmDisputa` (transacoes.repository.ts) na mesma requisição, para
 * as duas tabelas ficarem coerentes (poderíamos envolver isso numa
 * transação de banco só, como em `marcarAutorizada`/`marcarLiberada`, mas
 * deixamos a cargo da rota aqui porque `disputas.repository.ts` não
 * importa de `transacoes.repository.ts` de propósito -- evita um ciclo de
 * dependência entre os dois repositories; a rota já orquestra os dois).
 */
export async function abrirDisputa(dados: {
  idTransacao: string;
  idServico: string;
  abertoPorClienteId: string;
  motivo: string;
}): Promise<Disputa> {
  const { rows } = await pool.query<{ id_disputa: string }>(
    `INSERT INTO disputas_transacao (id_transacao, id_servico, aberto_por_cliente_id, motivo)
     VALUES ($1, $2, $3, $4)
     RETURNING id_disputa`,
    [dados.idTransacao, dados.idServico, dados.abertoPorClienteId, dados.motivo],
  );
  const disputa = await buscarDisputaPorId(rows[0].id_disputa);
  return disputa as Disputa;
}

/**
 * Resolve o ticket -- PRONTA PARA USO FUTURO, ainda sem rota que a chame
 * (ver comentário no topo do arquivo). Só marca QUEM ganhou a mediação e
 * a observação; não existe mais nenhum cálculo de valor automático embutido
 * aqui (ver nota "REMOVIDO DE PROPÓSITO" no topo do arquivo) -- se um dia a
 * mediação precisar ajustar valores, isso é responsabilidade de quem
 * chama esta função (a rota), não deste repository.
 */
export async function resolverDisputa(
  idDisputa: string,
  dados: {
    resolucao: 'RESOLVIDA_CLIENTE' | 'RESOLVIDA_PROFISSIONAL';
    observacao?: string;
  },
): Promise<boolean> {
  const { rowCount } = await pool.query(
    `UPDATE disputas_transacao
        SET status = $2::status_disputa_enum,
            resolucao_observacao = $3,
            resolvido_em = NOW()
      WHERE id_disputa = $1
        AND status = ANY(ARRAY['ABERTA','EM_MEDIACAO']::status_disputa_enum[])`,
    [idDisputa, dados.resolucao, dados.observacao ?? null],
  );
  return (rowCount ?? 0) > 0;
}
