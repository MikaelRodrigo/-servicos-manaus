import { pool } from '../database';

/* ============================================================================
   Camada de acesso a dados.

   Toda query SQL vive AQUI. A rota não sabe SQL, o repository não sabe HTTP.
   Quando na Etapa 4 você trocar `pg` cru por algo com cache, ou adicionar
   um teste automatizado, você mexe só neste arquivo.
   ========================================================================= */

/** O que a rota entrega para cá. Já validado, já em tipos corretos. */
export interface FiltroProximidade {
  latitude: number;
  longitude: number;
  raioMetros: number;
  /** Busca livre (fuzzy) por nome de categoria/subcategoria -- ver Seção "busca de subcategoria" no app. */
  profissao?: string;
  /**
   * Filtro EXATO por subcategoria -- alimentado pelo `BuscaSubcategoriaAutocomplete`
   * do app (cliente escolhe da lista, nunca digita livre). Quando presente,
   * tem precedência sobre `profissao`: só entra quem tem exatamente essa
   * subcategoria, sem aproximação nenhuma.
   */
  subcategoriaId?: number;
  limite: number;
  offset: number;
}

/** O que sai daqui. Espelha o SELECT abaixo, coluna por coluna. */
export interface ProfissionalProximo {
  profissional_id: string;
  tipo_pessoa: 'PF' | 'PJ';
  nome_exibicao: string;
  atuacao: string | null;
  categoria: string | null;
  email: string;
  contato: string;
  latitude: number;
  longitude: number;
  distancia_metros: number;
  url_foto_perfil: string | null;
}

/**
 * Busca profissionais dentro de um raio, ordenados do mais perto ao mais longe.
 */
export async function buscarProximos(
  filtro: FiltroProximidade,
): Promise<ProfissionalProximo[]> {
  /* ==========================================================================
     ATENÇÃO A TRÊS COISAS NESTE SQL:

     1) $1, $2, $3... são PLACEHOLDERS. O driver manda o texto do SQL e os
        valores em pacotes SEPARADOS para o Postgres. O valor jamais é
        interpretado como comando. É isto que mata o SQL Injection -- e é o
        motivo de NUNCA usarmos template literal (crase) para montar SQL.

     2) ST_MakePoint($1, $2) recebe LONGITUDE PRIMEIRO, depois latitude.
        Repare que $1 = longitude. Invertido, seu eletricista da Ponta Negra
        vai aparecer na Somália e nenhum erro será lançado.

     3) `::geography` faz o ST_DWithin medir em METROS.
        Sem o cast, o tipo é `geometry` e a distância sai em GRAUS. A busca
        "num raio de 5000" viraria "num raio de 5000 graus" -- ou seja, o
        planeta inteiro. Bug clássico, silencioso, e sem mensagem de erro.
        ======================================================================= */
  const sql = `
    SELECT
      p.profissional_id,
      p.tipo_pessoa,

      -- Custo do Single Table Design: PF tem "nome", PJ tem "razao_social".
      COALESCE(p.nome, p.razao_social)      AS nome_exibicao,

      -- Desde a migração 09, "atuacao" vem da subcategoria escolhida no
      -- cadastro (via categoria_id/subcategoria_id), não mais de texto
      -- livre. O nome da chave no JSON continua "atuacao" de propósito --
      -- é o que o app Flutter já espera, não precisou mudar nada lá.
      sc.nome                               AS atuacao,
      c.nome                                AS categoria,

      p.email,
      p.contato,
      p.latitude,
      p.longitude,
      p.url_foto_perfil,

      -- ROUND() devolve NUMERIC, que o driver 'pg' entregaria como string.
      -- O cast ::float8 garante um number no JSON.
      ROUND(
        ST_Distance(
          p.localizacao,
          ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
        )::numeric
      , 2)::float8                          AS distancia_metros

    FROM profissionais p
    LEFT JOIN subcategorias sc ON sc.subcategoria_id = p.subcategoria_id
    LEFT JOIN categorias c ON c.categoria_id = p.categoria_id

    WHERE
      -- ST_DWithin é o predicado que o índice GIST consegue usar.
      -- Ele filtra ANTES de calcular distância exata (usa a bounding box).
      --
      -- NÃO troque por "WHERE ST_Distance(...) < raio". Funciona, dá o mesmo
      -- resultado, e ignora o índice: vira Seq Scan na tabela toda.
      ST_DWithin(
        p.localizacao,
        ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
        $3
      )

      -- Profissional sem coordenada não entra no mapa.
      AND p.localizacao IS NOT NULL

      -- Filtro textual livre (legado -- mantido por compatibilidade, mas o
      -- app não digita mais texto solto: ver BuscaSubcategoriaAutocomplete,
      -- que só manda subcategoria_id exato, filtrado abaixo). Quando $4 é
      -- NULL, a condição inteira vira TRUE e o filtro não se aplica. Casa
      -- tanto contra a subcategoria ("barbeiro") quanto contra a categoria
      -- ("beleza"), para quem digitar o termo mais genérico.
      AND (
        $4::text IS NULL
        OR unaccent(lower(COALESCE(sc.nome, ''))) LIKE '%' || unaccent(lower($4::text)) || '%'
        OR unaccent(lower(COALESCE(c.nome, '')))  LIKE '%' || unaccent(lower($4::text)) || '%'
      )

      -- Filtro EXATO por subcategoria (o que o mapa usa de verdade hoje).
      -- Sem aproximação: só entra quem tem exatamente essa subcategoria_id.
      AND ($7::int IS NULL OR p.subcategoria_id = $7::int)

    ORDER BY p.localizacao <-> ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
    LIMIT $5
    OFFSET $6;
  `;

  /* O operador `<->` no ORDER BY é o "KNN". Ele também usa o índice GIST,
     diferente de `ORDER BY ST_Distance(...)`. Em uma tabela pequena a
     diferença é invisível; com 50 mil profissionais em Manaus, não é. */

  const valores = [
    filtro.longitude, // $1  <- longitude primeiro. Sempre.
    filtro.latitude, // $2
    filtro.raioMetros, // $3
    filtro.profissao ?? null, // $4
    filtro.limite, // $5
    filtro.offset, // $6
    filtro.subcategoriaId ?? null, // $7
  ];

  const { rows } = await pool.query<ProfissionalProximo>(sql, valores);
  return rows;
}

/**
 * Perfil público completo -- a "carteira de visitas" que o app mostra ao
 * tocar num pino do mapa.
 *
 * Repare que nem `email` NEM `contato` estão aqui -- de propósito. Um
 * perfil público serve para o cliente decidir se contrata; ele não precisa
 * do telefone do profissional para isso (o pedido de serviço acontece pelo
 * próprio app, via "Solicitar serviço"). Expor telefone/e-mail numa rota
 * pública sem autenticação é só dar de graça material para bots de spam
 * raspar a base inteira -- ligação indesejada é pior que e-mail de spam.
 */
export interface PerfilPublicoProfissional {
  profissional_id: string;
  tipo_pessoa: 'PF' | 'PJ';
  nome_exibicao: string;
  atuacao: string | null;
  categoria: string | null;
  descricao: string | null;
  url_foto_perfil: string | null;
  latitude: number | null;
  longitude: number | null;
  endereco_atuacao: string | null;
}

/**
 * Busca os dados públicos de UM profissional, para a tela de perfil.
 */
export async function buscarPerfilPublico(
  profissionalId: string,
): Promise<PerfilPublicoProfissional | null> {
  const { rows } = await pool.query<PerfilPublicoProfissional>(
    `SELECT
       p.profissional_id,
       p.tipo_pessoa,
       COALESCE(p.nome, p.razao_social) AS nome_exibicao,
       sc.nome                          AS atuacao,
       c.nome                           AS categoria,
       p.descricao,
       p.url_foto_perfil,
       p.latitude,
       p.longitude,
       p.endereco_atuacao
     FROM profissionais p
     LEFT JOIN subcategorias sc ON sc.subcategoria_id = p.subcategoria_id
     LEFT JOIN categorias c ON c.categoria_id = p.categoria_id
     WHERE p.profissional_id = $1`,
    [profissionalId],
  );
  return rows[0] ?? null;
}

/**
 * O que a rota de edição entrega. `undefined` num campo = "não mexa nele".
 *
 * `cep`, `latitude`, `longitude` e `enderecoAtuacao` sempre chegam JUNTOS
 * (ou todos `undefined`, ou todos preenchidos) -- são o resultado de UMA
 * consulta de geocodificação feita pela rota (ver `buscarLocalizacaoPorCep`
 * em services/cep.ts) antes de chamar esta função. O repository não sabe
 * nada sobre CEP nem sobre a API externa -- só grava o que já chegou pronto.
 */
export interface AtualizacaoPerfilProfissional {
  descricao?: string;
  urlFotoPerfil?: string;
  cep?: string;
  latitude?: number;
  longitude?: number;
  enderecoAtuacao?: string;
  /**
   * Igual ao trio cep/latitude/longitude: só existem JUNTOS (ou os dois
   * `undefined`, ou os dois preenchidos) -- a rota valida isso antes de
   * chamar esta função. Nunca um só, porque a FK composta do banco
   * (`fk_profissionais_subcategoria_categoria`, migração 09) recusaria um
   * par incoerente -- ver categoria_id/subcategoria_id em profissionais.
   */
  categoriaId?: number;
  subcategoriaId?: number;
}

/**
 * Atualiza o perfil de UM profissional -- sempre o DONO DO TOKEN (o `:id`
 * nem existe nesta função; a rota só chama isto com `req.usuario.sub`). Não
 * existe caminho para um profissional editar o perfil de outro.
 *
 * `COALESCE($2, descricao)`: se `dados.descricao` for `undefined` (o campo
 * não veio no request), o parâmetro vira SQL `NULL`, e o COALESCE mantém o
 * valor que já estava na coluna -- só substitui quando um valor de verdade é
 * passado. É "atualização parcial" sem montar SQL dinâmico, no mesmo
 * espírito do filtro opcional de `profissao` em `buscarProximos` acima.
 */
export async function atualizarPerfilProfissional(
  profissionalId: string,
  dados: AtualizacaoPerfilProfissional,
): Promise<PerfilPublicoProfissional> {
  const { rows } = await pool.query<PerfilPublicoProfissional>(
    `WITH atualizado AS (
       UPDATE profissionais
          SET descricao        = COALESCE($2, descricao),
              url_foto_perfil  = COALESCE($3, url_foto_perfil),
              cep              = COALESCE($4, cep),
              latitude         = COALESCE($5, latitude),
              longitude        = COALESCE($6, longitude),
              endereco_atuacao = COALESCE($7, endereco_atuacao),
              categoria_id     = COALESCE($8, categoria_id),
              subcategoria_id  = COALESCE($9, subcategoria_id)
        WHERE profissional_id = $1
        RETURNING *
     )
     SELECT
       p.profissional_id,
       p.tipo_pessoa,
       COALESCE(p.nome, p.razao_social) AS nome_exibicao,
       sc.nome                          AS atuacao,
       c.nome                           AS categoria,
       p.descricao,
       p.url_foto_perfil,
       p.latitude,
       p.longitude,
       p.endereco_atuacao
     FROM atualizado p
     LEFT JOIN subcategorias sc ON sc.subcategoria_id = p.subcategoria_id
     LEFT JOIN categorias c ON c.categoria_id = p.categoria_id`,
    [
      profissionalId,
      dados.descricao ?? null,
      dados.urlFotoPerfil ?? null,
      dados.cep ?? null,
      dados.latitude ?? null,
      dados.longitude ?? null,
      dados.enderecoAtuacao ?? null,
      dados.categoriaId ?? null,
      dados.subcategoriaId ?? null,
    ],
  );
  return rows[0];
}
