import { pool } from '../database';

/* ============================================================================
   `creditos_usuario` (migração 14) -- extrato (ledger) de cashback do
   cliente. Nunca um UPDATE de valor: cada linha é um lançamento imutável
   (só `utilizado_em` muda, quando o crédito é gasto -- e a LÓGICA de gasto
   é de uma etapa futura, fora deste arquivo). O saldo disponível é sempre
   CALCULADO (SUM), nunca lido de um campo solto -- ver `saldoDisponivel`.
   ========================================================================= */

export interface Credito {
  id_credito: string;
  cliente_id: string;
  id_transacao: string | null;
  valor: string;
  motivo: string;
  utilizado_em: string | null;
  created_at: string;
}

/**
 * Gera o cashback -- pedido explícito do checklist: "o backend gera uma
 * entrada na tabela User_Credits vinculada ao User_ID do cliente" no
 * momento da liberação (Etapa D). `percentualCashback` é passado por quem
 * chama (a rota), não fixado aqui -- é uma regra de negócio que pode mudar
 * por campanha/categoria no futuro, este repository só grava o resultado.
 */
export async function gerarCashback(dados: {
  clienteId: string;
  idTransacao: string;
  /** String decimal (ex.: "1.50") -- o VALOR do cashback, já calculado por quem chama. */
  valor: string;
  motivo?: string;
}): Promise<Credito> {
  const { rows } = await pool.query<Credito>(
    `INSERT INTO creditos_usuario (cliente_id, id_transacao, valor, motivo)
     VALUES ($1, $2, $3::numeric, COALESCE($4, 'cashback_servico'))
     RETURNING
       id_credito, cliente_id, id_transacao, valor::text, motivo, utilizado_em, created_at`,
    [dados.clienteId, dados.idTransacao, dados.valor, dados.motivo ?? null],
  );
  return rows[0];
}

/** Soma de todo crédito ainda não gasto -- o "saldo" de moedas do cliente, sempre calculado, nunca armazenado. */
export async function saldoDisponivel(clienteId: string): Promise<string> {
  const { rows } = await pool.query<{ saldo: string }>(
    `SELECT COALESCE(SUM(valor), 0)::text AS saldo
       FROM creditos_usuario
      WHERE cliente_id = $1
        AND utilizado_em IS NULL`,
    [clienteId],
  );
  return rows[0].saldo;
}

export async function listarExtratoDoCliente(clienteId: string): Promise<Credito[]> {
  const { rows } = await pool.query<Credito>(
    `SELECT id_credito, cliente_id, id_transacao, valor::text, motivo, utilizado_em, created_at
       FROM creditos_usuario
      WHERE cliente_id = $1
      ORDER BY created_at DESC`,
    [clienteId],
  );
  return rows;
}
