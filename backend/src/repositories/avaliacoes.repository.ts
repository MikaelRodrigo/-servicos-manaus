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
// CRIAR (o cliente avalia o profissional) -- agora com VÁRIAS fotos
// ---------------------------------------------------------------------------

/** O que criarAvaliacaoProfissional devolve: a avaliação + as fotos já anexadas. */
export interface AvaliacaoProfissionalComFotos extends AvaliacaoProfissional {
  urls_fotos: string[];
}

/**
 * Cria a avaliação e, se houver fotos, grava todas na tabela filha
 * avaliacoes_profissional_fotos -- as duas coisas dentro de UMA
 * transação. Por quê? Porque são duas operações dependentes: se o INSERT
 * das fotos falhasse depois do INSERT da avaliação já ter sido confirmado,
 * o cliente veria "avaliação enviada" mas as fotos que ele escolheu
 * sumiriam silenciosamente. Com transação, ou as duas coisas acontecem, ou
 * nenhuma -- ROLLBACK desfaz tudo se qualquer passo falhar.
 *
 * Esta é a primeira transação explícita do projeto (até aqui, cada rota só
 * fazia UM INSERT/UPDATE por vez, que o Postgres já trata atomicamente
 * sozinho). Sempre que uma operação virar "duas ou mais escritas que
 * precisam ou acontecer juntas ou não acontecer", é sinal de que chegou a
 * hora de usar BEGIN/COMMIT/ROLLBACK como aqui.
 */
export async function criarAvaliacaoProfissional(dados: {
  idServico: string;
  clienteId: string;
  profissionalId: string;
  estrelasTecnico: number;
  estrelasComportamental: number;
  estrelasEconomico: number;
  comentario?: string;
  urlsFotos?: string[];
}): Promise<AvaliacaoProfissionalComFotos> {
  // pool.connect() pega UMA conexão dedicada do pool -- diferente de
  // pool.query(...), que pode usar uma conexão DIFERENTE a cada chamada.
  // Uma transação só faz sentido se todos os comandos rodarem na MESMA
  // conexão (é a conexão, não o pool, que sabe "eu estou no meio de uma
  // transação agora").
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    const { rows } = await client.query<AvaliacaoProfissional>(
      `INSERT INTO avaliacoes_profissional
         (id_servico, cliente_id, profissional_id,
          estrelas_tecnico, estrelas_comportamental, estrelas_economico,
          comentario)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING *`,
      [
        dados.idServico,
        dados.clienteId,
        dados.profissionalId,
        dados.estrelasTecnico,
        dados.estrelasComportamental,
        dados.estrelasEconomico,
        dados.comentario ?? null,
      ],
    );
    const avaliacao = rows[0];

    const urlsFotos = dados.urlsFotos ?? [];
    for (let ordem = 0; ordem < urlsFotos.length; ordem++) {
      await client.query(
        `INSERT INTO avaliacoes_profissional_fotos (avaliacao_id, url_foto, ordem)
         VALUES ($1, $2, $3)`,
        [avaliacao.id, urlsFotos[ordem], ordem],
      );
    }

    await client.query('COMMIT');
    return { ...avaliacao, urls_fotos: urlsFotos };
  } catch (erro) {
    // Desfaz TUDO que essa transação tentou fazer -- inclusive o INSERT da
    // avaliação, mesmo que ele individualmente tivesse funcionado.
    await client.query('ROLLBACK');
    throw erro;
  } finally {
    // Devolve a conexão pro pool. Esquecer isto é o jeito clássico de um
    // servidor Node "vazar" conexões até o Postgres recusar novas.
    client.release();
  }
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

/** Espelha as colunas da view vw_historico_portifolio (Seção 3 da migração 05). */
export interface ItemDePortfolio {
  profissional_id: string;
  id_servico: string;
  avaliacao_id: string;
  cliente_id: string;
  nome_cliente: string;
  tipo_cliente: 'PF' | 'PJ';
  comentario: string | null;
  urls_fotos: string[];
  estrelas_tecnico: number;
  estrelas_comportamental: number;
  estrelas_economico: number;
  media_estrelas: number;
  total_curtidas: number;
  data_conclusao: string;
  data_avaliacao: string;
  /** Só é true quando usuarioIdAtual foi informado E essa pessoa já curtiu. */
  curtido_por_mim: boolean;
}

/**
 * Busca o portfólio público, já com curtido_por_mim calculado.
 *
 * usuarioIdAtual é OPCIONAL de propósito: esta rota é pública (qualquer
 * visitante vê o portfólio, mesmo sem conta -- é o que convence alguém a
 * se cadastrar). Quando a pessoa está logada, a rota manda o ID dela e a
 * gente marca quais avaliações ela já curtiu; sem login, curtido_por_mim
 * vem sempre false (mostrar "curtido" para quem nunca curtiu nada seria
 * um bug de exibição, não uma feature).
 */
export async function buscarPortifolio(
  profissionalId: string,
  paginacao: { limite: number; offset: number },
  usuarioIdAtual?: string,
): Promise<ItemDePortfolio[]> {
  const { rows } = await pool.query<ItemDePortfolio>(
    `SELECT
       v.*,
       CASE
         WHEN $4::uuid IS NULL THEN false
         ELSE EXISTS (
           SELECT 1 FROM avaliacoes_profissional_curtidas c
           WHERE c.avaliacao_id = v.avaliacao_id AND c.usuario_id = $4::uuid
         )
       END AS curtido_por_mim
     FROM vw_historico_portifolio v
     WHERE v.profissional_id = $1
     LIMIT $2 OFFSET $3`,
    [profissionalId, paginacao.limite, paginacao.offset, usuarioIdAtual ?? null],
  );
  return rows;
}

// ---------------------------------------------------------------------------
// CURTIR / DESCURTIR uma avaliação (botão "Útil" do portfólio)
// ---------------------------------------------------------------------------

/** Confere se a avaliação existe -- usado pela rota antes de tentar curtir. */
export async function avaliacaoProfissionalExiste(avaliacaoId: string): Promise<boolean> {
  const { rows } = await pool.query(`SELECT 1 FROM avaliacoes_profissional WHERE id = $1`, [
    avaliacaoId,
  ]);
  return rows.length > 0;
}

/**
 * Alterna a curtida: se a pessoa já tinha curtido, remove (descurtir); se
 * não tinha, adiciona. É o comportamento padrão de botão "like" -- clicar
 * de novo desfaz o clique anterior.
 *
 * DELETE ... RETURNING é o truque para saber, numa query só, se a linha
 * existia: rowCount > 0 quer dizer "existia e acabamos de apagar".
 */
export async function alternarCurtidaAvaliacao(
  avaliacaoId: string,
  usuarioId: string,
  usuarioPapel: 'cliente' | 'profissional',
): Promise<{ curtido: boolean; totalCurtidas: number }> {
  const remocao = await pool.query(
    `DELETE FROM avaliacoes_profissional_curtidas
      WHERE avaliacao_id = $1 AND usuario_id = $2
      RETURNING avaliacao_id`,
    [avaliacaoId, usuarioId],
  );

  let curtido: boolean;
  if ((remocao.rowCount ?? 0) > 0) {
    curtido = false; // já estava curtido -- acabamos de descurtir.
  } else {
    await pool.query(
      `INSERT INTO avaliacoes_profissional_curtidas (avaliacao_id, usuario_id, usuario_papel)
       VALUES ($1, $2, $3)`,
      [avaliacaoId, usuarioId, usuarioPapel],
    );
    curtido = true;
  }

  const { rows } = await pool.query<{ total: number }>(
    `SELECT COUNT(*)::int AS total FROM avaliacoes_profissional_curtidas WHERE avaliacao_id = $1`,
    [avaliacaoId],
  );

  return { curtido, totalCurtidas: rows[0].total };
}

/**
 * Resumo numérico -- médias, contagem e DISTRIBUIÇÃO por critério. Base do
 * "selo de qualidade" na tela de perfil.
 *
 * distribuicao_* é um array de 5 posições, sempre na ordem
 * [nota 5, nota 4, nota 3, nota 2, nota 1] -- quantas avaliações deram cada
 * nota NAQUELE critério. É o dado por trás do gráfico de barras "5
 * estrelas ▬▬▬▬▬ 482 / 4 estrelas ▬ 10 / ..." no perfil público.
 */
export interface ResumoDeAvaliacoes {
  total_avaliacoes: number;
  media_tecnico: number | null;
  media_comportamental: number | null;
  media_economico: number | null;
  media_geral: number | null;
  distribuicao_tecnico: number[];
  distribuicao_comportamental: number[];
  distribuicao_economico: number[];
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
       , 2)::float8                                            AS media_geral,

       -- Um array por critério, contando quantas avaliações deram cada
       -- nota (5 a 1). COUNT(*) FILTER (WHERE ...) conta só as linhas
       -- que batem a condição, dentro do MESMO agregado -- evita 5 queries
       -- separadas por critério.
       ARRAY[
         COUNT(*) FILTER (WHERE estrelas_tecnico = 5),
         COUNT(*) FILTER (WHERE estrelas_tecnico = 4),
         COUNT(*) FILTER (WHERE estrelas_tecnico = 3),
         COUNT(*) FILTER (WHERE estrelas_tecnico = 2),
         COUNT(*) FILTER (WHERE estrelas_tecnico = 1)
       ]::int[] AS distribuicao_tecnico,

       ARRAY[
         COUNT(*) FILTER (WHERE estrelas_comportamental = 5),
         COUNT(*) FILTER (WHERE estrelas_comportamental = 4),
         COUNT(*) FILTER (WHERE estrelas_comportamental = 3),
         COUNT(*) FILTER (WHERE estrelas_comportamental = 2),
         COUNT(*) FILTER (WHERE estrelas_comportamental = 1)
       ]::int[] AS distribuicao_comportamental,

       ARRAY[
         COUNT(*) FILTER (WHERE estrelas_economico = 5),
         COUNT(*) FILTER (WHERE estrelas_economico = 4),
         COUNT(*) FILTER (WHERE estrelas_economico = 3),
         COUNT(*) FILTER (WHERE estrelas_economico = 2),
         COUNT(*) FILTER (WHERE estrelas_economico = 1)
       ]::int[] AS distribuicao_economico

     FROM avaliacoes_profissional
     WHERE profissional_id = $1`,
    [profissionalId],
  );
  // COUNT(*) sempre devolve uma linha, mesmo com zero avaliações (os AVG
  // vêm NULL e os arrays de distribuição vêm [0,0,0,0,0] nesse caso) --
  // por isso não precisamos de "?? valorPadrao" aqui.
  return rows[0];
}
