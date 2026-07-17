import { pool } from '../database';
import { StatusDisputa } from '../utils/validacao';

/* ============================================================================
   `disputas_transacao` (migração 14) -- o ticket de mediação aberto pelo
   REPORT_ISSUE do cliente (Etapa C). Este arquivo só cobre ABERTURA da
   disputa -- a RESOLUÇÃO (mediação decidindo a favor de um lado, aplicando
   o cálculo de dano do checklist) fica de fora de propósito: resolver uma
   disputa é uma ação administrativa, e o projeto ainda não tem um papel
   "admin" no sistema de autenticação (`Papel = 'cliente' | 'profissional'`,
   ver utils/jwt.ts) -- não dá para proteger esse endpoint corretamente sem
   inventar um mecanismo de auth novo, o que é uma decisão de produto, não
   um detalhe de implementação. `marcarEmMediacaoOuResolvida` abaixo existe
   pronta para quando isso for decidido.
   ========================================================================= */

export interface Disputa {
  id_disputa: string;
  id_transacao: string;
  id_servico: string;
  aberto_por_cliente_id: string;
  motivo: string;
  status: StatusDisputa;
  flag_dano: boolean;
  valor_profissional_ajustado: string | null;
  valor_reembolso_extra_plataforma: string | null;
  resolucao_observacao: string | null;
  resolvido_em: string | null;
  created_at: string;
  updated_at: string;
}

const SELECT_DISPUTA = `
  SELECT
    id_disputa, id_transacao, id_servico, aberto_por_cliente_id, motivo, status,
    flag_dano,
    valor_profissional_ajustado::text,
    valor_reembolso_extra_plataforma::text,
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
 * (ver comentário no topo do arquivo). `valorProfissionalAjustado`/
 * `valorReembolsoExtraPlataforma` só podem ser informados quando
 * `flagDano` é `true` (mesmo CHECK do banco, `chk_disputa_valores_apenas_com_dano`
 * -- o Postgres recusaria de qualquer forma, isto só evita a viagem ao
 * banco para descobrir isso).
 */
export async function resolverDisputa(
  idDisputa: string,
  dados: {
    resolucao: 'RESOLVIDA_CLIENTE' | 'RESOLVIDA_PROFISSIONAL';
    flagDano: boolean;
    valorProfissionalAjustado?: string;
    valorReembolsoExtraPlataforma?: string;
    observacao?: string;
  },
): Promise<boolean> {
  if (!dados.flagDano && (dados.valorProfissionalAjustado || dados.valorReembolsoExtraPlataforma)) {
    throw new Error(
      '[disputas] valorProfissionalAjustado/valorReembolsoExtraPlataforma só podem ser informados com flagDano=true.',
    );
  }

  const { rowCount } = await pool.query(
    `UPDATE disputas_transacao
        SET status = $2::status_disputa_enum,
            flag_dano = $3,
            valor_profissional_ajustado = $4::numeric,
            valor_reembolso_extra_plataforma = $5::numeric,
            resolucao_observacao = $6,
            resolvido_em = NOW()
      WHERE id_disputa = $1
        AND status = ANY(ARRAY['ABERTA','EM_MEDIACAO']::status_disputa_enum[])`,
    [
      idDisputa,
      dados.resolucao,
      dados.flagDano,
      dados.valorProfissionalAjustado ?? null,
      dados.valorReembolsoExtraPlataforma ?? null,
      dados.observacao ?? null,
    ],
  );
  return (rowCount ?? 0) > 0;
}
