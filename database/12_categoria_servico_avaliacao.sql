-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Histórico por Especialidade" -- vincula cada SERVIÇO a uma
--  categoria/subcategoria, para segmentar avaliações/portfólio por área.
--
--  Rodar como: psql "sua-connection-string-neon" -f 12_categoria_servico_avaliacao.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - POR QUE ISTO EXISTE
--
--  Até aqui, um SERVIÇO não sabia "de que tipo" ele era -- só ligava um
--  cliente a um profissional, sem dizer se era um trabalho de eletricista,
--  de encanador, etc. Isso não era um problema enquanto cada profissional
--  tinha só UMA especialidade (categoria_id/subcategoria_id, migração 09).
--  Mas desde a migração 11 (tags de especialidade, N:N), um profissional
--  pode atender em VÁRIAS áreas -- e aí faz diferença saber qual delas foi
--  contratada num serviço específico: a nota de "Eletricista" não deveria
--  se misturar com a nota de "Pintor" do MESMO profissional no histórico
--  que o cliente vê.
--
--  Esta migração adiciona `categoria_id`/`subcategoria_id` em `servicos` --
--  o CLIENTE escolhe, no momento de solicitar, qual das especialidades do
--  profissional (a lista de tags dele, migração 11) está contratando. A
--  partir daí, a categoria "flui" sozinha para a avaliação e para o
--  portfólio público, porque os dois já são ligados a `servicos` via
--  `id_servico` -- não precisamos duplicar a categoria em mais tabela
--  nenhuma, só JUNTAR através de `servicos` (mesmo espírito de todo o
--  resto do schema: nunca duplicar um dado que já dá pra buscar via JOIN).
--
--  As colunas nascem NULAS (mesmo padrão de categoria_id/subcategoria_id em
--  `profissionais`, migração 09): não dá pra exigir NOT NULL de cara sem
--  quebrar os serviços que já existem no banco. O backend, a partir de
--  agora, passa a EXIGIR as duas em todo POST /servicos novo -- a coluna
--  nula no schema é só para não travar a migração dos dados antigos, não é
--  "opcional" do ponto de vista do produto.
-- ============================================================================


-- ============================================================================
--  SEÇÃO 2 - COLUNAS NOVAS EM servicos + FK COMPOSTA
--
--  Mesmíssimo padrão da migração 09 (profissionais.categoria_id/subcategoria_id):
--  FK composta contra subcategorias(subcategoria_id, categoria_id), não uma
--  FK simples -- é o que impede gravar um par incoerente (categoria "Beleza",
--  subcategoria "Pedreiro") sem precisar de trigger nem validação repetida
--  no backend.
-- ============================================================================

ALTER TABLE servicos
    ADD COLUMN IF NOT EXISTS categoria_id    INT REFERENCES categorias (categoria_id),
    ADD COLUMN IF NOT EXISTS subcategoria_id INT;

ALTER TABLE servicos
    ADD CONSTRAINT fk_servicos_subcategoria_categoria
    FOREIGN KEY (subcategoria_id, categoria_id)
    REFERENCES subcategorias (subcategoria_id, categoria_id);

-- Mesma regra "ou tem os dois, ou não tem nenhum" já usada em profissionais
-- (chk_prof_categoria_completa, migração 09) e em latitude/longitude
-- (chk_prof_coords_completas, 01_schema_2.sql).
ALTER TABLE servicos
    ADD CONSTRAINT chk_servico_categoria_completa CHECK (
        (categoria_id IS NULL AND subcategoria_id IS NULL)
        OR
        (categoria_id IS NOT NULL AND subcategoria_id IS NOT NULL)
    );

-- Índice para o filtro "só as avaliações desta especialidade" no portfólio
-- (GET /profissionais/:id/portfolio?subcategoria_id=...).
CREATE INDEX IF NOT EXISTS idx_servicos_subcategoria_id
    ON servicos (subcategoria_id) WHERE subcategoria_id IS NOT NULL;

COMMENT ON COLUMN servicos.categoria_id IS
    'Categoria do serviço contratado -- escolhida pelo cliente, dentre as tags de especialidade do profissional (migração 11), no momento de solicitar. Nula só em serviços anteriores a esta migração (ver backfill na Seção 3).';
COMMENT ON COLUMN servicos.subcategoria_id IS
    'Subcategoria do serviço contratado -- ver comentário de categoria_id. A FK composta garante coerência com o par (subcategoria_id, categoria_id).';


-- ============================================================================
--  SEÇÃO 3 - BACKFILL dos serviços que já existem
--
--  Não temos como saber retroativamente QUAL especialidade foi contratada
--  num serviço antigo (a informação nunca foi capturada). O melhor
--  substituto disponível é a categoria/subcategoria PRINCIPAL do
--  profissional que prestou o serviço (profissionais.categoria_id/
--  subcategoria_id) -- mesma lógica de "melhor aproximação disponível" já
--  usada no backfill da migração 10.
-- ============================================================================

UPDATE servicos s
SET categoria_id    = p.categoria_id,
    subcategoria_id = p.subcategoria_id
FROM profissionais p
WHERE s.profissional_id = p.profissional_id
  AND s.subcategoria_id IS NULL
  AND p.subcategoria_id IS NOT NULL;


-- ============================================================================
--  SEÇÃO 4 - VIEW vw_historico_portifolio COM CATEGORIA/SUBCATEGORIA
--
--  `DROP VIEW` + `CREATE VIEW` (não `CREATE OR REPLACE`) -- mesmo motivo
--  documentado nas migrações 05/07: mantemos o padrão em toda alteração de
--  view deste projeto.
-- ============================================================================

DROP VIEW IF EXISTS vw_historico_portifolio;

CREATE VIEW vw_historico_portifolio AS
SELECT
    s.profissional_id,
    s.id_servico,
    ap.id                                 AS avaliacao_id,
    ap.cliente_id,

    s.subcategoria_id,
    sc.nome                               AS subcategoria_nome,
    s.categoria_id,
    c2.nome                               AS categoria_nome,

    COALESCE(c.nome, c.razao_social)      AS nome_cliente,
    c.tipo_pessoa                         AS tipo_cliente,
    c.url_foto_perfil                     AS url_foto_cliente,

    ap.comentario,

    COALESCE(fotos.urls, ARRAY[]::text[]) AS urls_fotos,

    ap.estrelas_tecnico,
    ap.estrelas_comportamental,
    ap.estrelas_economico,

    ROUND(
        ( ap.estrelas_tecnico
        + ap.estrelas_comportamental
        + ap.estrelas_economico
        )::numeric / 3
    , 2)                                   AS media_estrelas,

    COALESCE(curtidas.total, 0)           AS total_curtidas,

    s.data_conclusao,
    ap.created_at                         AS data_avaliacao

FROM servicos s
    INNER JOIN avaliacoes_profissional ap ON ap.id_servico = s.id_servico
    INNER JOIN clientes c                 ON c.cliente_id  = ap.cliente_id
    LEFT JOIN subcategorias sc            ON sc.subcategoria_id = s.subcategoria_id
    LEFT JOIN categorias c2               ON c2.categoria_id    = s.categoria_id

    LEFT JOIN LATERAL (
        SELECT array_agg(f.url_foto ORDER BY f.ordem, f.created_at) AS urls
        FROM avaliacoes_profissional_fotos f
        WHERE f.avaliacao_id = ap.id
    ) fotos ON TRUE

    LEFT JOIN LATERAL (
        SELECT COUNT(*)::int AS total
        FROM avaliacoes_profissional_curtidas cur
        WHERE cur.avaliacao_id = ap.id
    ) curtidas ON TRUE

WHERE s.status = 'CONCLUIDO'

ORDER BY ap.created_at DESC;


-- ============================================================================
--  SEÇÃO 5 - VERIFICAÇÃO
-- ============================================================================

DO $$
DECLARE
    total_servicos           INT;
    servicos_sem_categoria   INT;
    total_avaliacoes         INT;
    avaliacoes_sem_categoria INT;
BEGIN
    SELECT COUNT(*) INTO total_servicos FROM servicos;
    SELECT COUNT(*) INTO servicos_sem_categoria FROM servicos WHERE subcategoria_id IS NULL;
    SELECT COUNT(*) INTO total_avaliacoes FROM vw_historico_portifolio;
    SELECT COUNT(*) INTO avaliacoes_sem_categoria FROM vw_historico_portifolio WHERE subcategoria_id IS NULL;

    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 12 aplicada com sucesso.';
    RAISE NOTICE ' Total de servicos: %', total_servicos;
    RAISE NOTICE ' Servicos sem categoria apos backfill: % (esperado: so quem prestou servico para um profissional sem categoria propria, raro)', servicos_sem_categoria;
    RAISE NOTICE ' Total de itens no portfolio (avaliacoes concluidas): %', total_avaliacoes;
    RAISE NOTICE ' Itens do portfolio sem categoria: %', avaliacoes_sem_categoria;
    RAISE NOTICE '---------------------------------------------';
END $$;
