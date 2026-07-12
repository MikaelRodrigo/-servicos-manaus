import { pool } from '../database';

/* ============================================================================
   AVALIAÇÃO BILATERAL

   Duas tabelas, cada uma com sua própria UNIQUE(id_servico) -- ou seja, um
   serviço recebe NO MÁXIMO uma avaliação de cada lado. Um trigger no banco
   (fn_valida_servico_concluido, Seção 8 do 01_schema.sql) já impede o
   INSERT se o serviço não estiver CONCLUIDO -- a rota (avaliacoes.routes.ts)
   confere isso ANTES de tentar o INSERT só para devolver uma mensagem
   amigável em vez do erro cru do trigger.
   ========================================================================= */

export interface AvaliacaoProfissional {
  id: string;
  id_servico: string;
  cliente_id: string;
  profissional_id: string;
  estrelas_tecnico: number;
  estrelas_comportamental: number;
  estrelas_economico: number;
  comentario: string | null;
  url_foto_servico: string | null;
  created_at: string;
}

export interface AvaliacaoCliente {
  id: string;
  id_servico: string;
  cliente_id: string;
  profissional_id: string;
  estrelas_clareza: number;
  estrelas_comportamental: number;
  estrelas_pagamento: number;
  comentario: string | null;
  created_at: string;
}

// ---------------------------------------------------------------------------
// CRIAR (o cliente avalia o profissional)
// ---------------------------------------------------------------------------
export async function criarAvaliacaoProfissional(dados: {
  idServico: string;
  clienteId: string;
  profissionalId: string;
  estrelasTecnico: number;
  estrelasComportamental: number;
  estrelasEconomico: number;
  comentario?: string;
  urlFotoServico?: string;
}): Promise<AvaliacaoProfissional> {
  const { rows } = await pool.query<AvaliacaoProfissional>(
    `INSERT INTO avaliacoes_profissional
       (id_servico, cliente_id, profissional_id,
        estrelas_tecnico, estrelas_comportamental, estrelas_economico,
        comentario, url_foto_servico)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [
      dados.idServico,
      dados.clienteId,
      dados.profissionalId,
      dados.estrelasTecnico,
      dados.estrelasComportamental,
      dados.estrelasEconomico,
      dados.comentario ?? null,
      dados.urlFotoServico ?? null,
    ],
  );
  return rows[0];
}

// ---------------------------------------------------------------------------
// CRIAR (o profissional avalia o cliente)
// ---------------------------------------------------------------------------
export async function criarAvaliacaoCliente(dados: {
  idServico: string;
  clienteId: string;
  profissionalId: string;
  estrelasClareza: number;
  estrelasComportamental: number;
  estrelasPagamento: number;
  comentario?: string;
}): Promise<AvaliacaoCliente> {
  const { rows } = await pool.query<AvaliacaoCliente>(
    `INSERT INTO avaliacoes_cliente
       (id_servico, cliente_id, profissional_id,
        estrelas_clareza, estrelas_comportamental, estrelas_pagamento, comentario)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING *`,
    [
      dados.idServico,
      dados.clienteId,
      dados.profissionalId,
      dados.estrelasClareza,
      dados.estrelasComportamental,
      dados.estrelasPagamento,
      dados.comentario ?? null,
    ],
  );
  return rows[0];
}

// ---------------------------------------------------------------------------
// CONSULTAR as avaliações de UM serviço específico (GET /servicos/:id/avaliacoes)
// ---------------------------------------------------------------------------
export async function buscarAvaliacaoProfissionalPorServico(
  idServico: string,
): Promise<AvaliacaoProfissional | null> {
  const { rows } = await pool.query<AvaliacaoProfissional>(
    `SELECT * FROM avaliacoes_profissional WHERE id_servico = $1`,
    [idServico],
  );
  return rows[0] ?? null;
}

export async function buscarAvaliacaoClientePorServico(
  idServico: string,
): Promise<AvaliacaoCliente | null> {
  const { rows } = await pool.query<AvaliacaoCliente>(
    `SELECT * FROM avaliacoes_cliente WHERE id_servico = $1`,
    [idServico],
  );
  return rows[0] ?? null;
}

// ---------------------------------------------------------------------------
// PORTFÓLIO PÚBLICO do profissional (GET /profissionais/:id/portfolio)
// ---------------------------------------------------------------------------

/** Espelha as colunas da view `vw_historico_portifolio` (Seção 9 do 01_schema.sql). */
export interface ItemDePortfolio {
  profissional_id: string;
  id_servico: string;
  cliente_id: string;
  nome_cliente: string;
  tipo_cliente: 'PF' | 'PJ';
  comentario: string | null;
  url_foto_servico: string | null;
  estrelas_tecnico: number;
  estrelas_comportamental: number;
  estrelas_economico: number;
  media_estrelas: number;
  data_conclusao: string;
  data_avaliacao: string;
}

export async function buscarPortifolio(
  profissionalId: string,
  paginacao: { limite: number; offset: number },
): Promise<ItemDePortfolio[]> {
  const { rows } = await pool.query<ItemDePortfolio>(
    `SELECT * FROM vw_historico_portifolio
      WHERE profissional_id = $1
      LIMIT $2 OFFSET $3`,
    [profissionalId, paginacao.limite, paginacao.offset],
  );
  return rows;
}

/** Resumo numérico -- médias e contagem. Base do "selo de qualidade" na tela de perfil. */
export interface ResumoDeAvaliacoes {
  total_avaliacoes: number;
  media_tecnico: number | null;
  media_comportamental: number | null;
  media_economico: number | null;
  media_geral: number | null;
}

export async function buscarResumoDeAvaliacoes(profissionalId: string): Promise<ResumoDeAvaliacoes> {
  const { rows } = await pool.query<ResumoDeAvaliacoes>(
    `SELECT
       COUNT(*)::int AS total_avaliacoes,
       ROUND(AVG(estrelas_tecnico)::numeric, 2)::float8        AS media_tecnico,
       ROUND(AVG(estrelas_comportamental)::numeric, 2)::float8 AS media_comportamental,
       ROUND(AVG(estrelas_economico)::numeric, 2)::float8      AS media_economico,
       ROUND(
         AVG((estrelas_tecnico + estrelas_comportamental + estrelas_economico) / 3.0)::numeric
       , 2)::float8                                            AS media_geral
     FROM avaliacoes_profissional
     WHERE profissional_id = $1`,
    [profissionalId],
  );
  // COUNT(*) sempre devolve uma linha, mesmo com zero avaliações (os AVG
  // vêm NULL nesse caso) -- por isso não precisamos de `?? valorPadrao` aqui.
  return rows[0];
}
