-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Foto do cliente no portfólio" - associa a foto de perfil do
--  cliente às avaliações que ele fez para profissionais
--
--  Rodar como: psql "sua-connection-string-neon" -f 07_foto_cliente_portfolio.sql
--
--  PRÉ-REQUISITO: migração 06 já aplicada (é ela que cria a coluna
--  clientes.url_foto_perfil que esta migração passa a expor na view).
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - VIEW vw_historico_portifolio COM url_foto_cliente
--
--  Até aqui a view só devolvia `nome_cliente` (e as iniciais dele viravam
--  um avatar de "bolinha com letra" no app, ver `_CartaoPortfolio` no
--  Flutter). Agora que `clientes.url_foto_perfil` existe (migração 06),
--  a view passa a expor essa URL também -- o app troca o avatar de
--  iniciais pela foto de verdade quando ela existir, e mantém o fallback
--  de iniciais quando o cliente não tiver preenchido foto (`NULL`).
--
--  `DROP VIEW` + `CREATE VIEW` (não `CREATE OR REPLACE VIEW`) pelo MESMO
--  motivo documentado na migração 05: ainda que `url_foto_cliente` entre
--  no FINAL da lista de colunas (o que `CREATE OR REPLACE VIEW` até
--  aceitaria), mantemos o padrão DROP+CREATE em toda alteração de view
--  deste projeto para não depender de acertar, de cabeça, quais mudanças
--  o Postgres aceita ou não em CREATE OR REPLACE.
-- ============================================================================

DROP VIEW IF EXISTS vw_historico_portifolio;

CREATE VIEW vw_historico_portifolio AS
SELECT
    s.profissional_id,
    s.id_servico,
    ap.id                                 AS avaliacao_id,
    ap.cliente_id,

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
--  SEÇÃO 2 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 07 aplicada com sucesso.';
    RAISE NOTICE ' View atualizada: vw_historico_portifolio (nova coluna url_foto_cliente)';
    RAISE NOTICE '---------------------------------------------';
END $$;
