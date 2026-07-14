-- ============================================================================
--  DIAGNÓSTICO: quais migrações 07-10 já foram aplicadas no banco?
--  Rodar no SQL Editor do Neon (console.neon.tech) e conferir o resultado.
-- ============================================================================

SELECT
    -- Migração 07 (view com foto do cliente no portfólio)
    EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_name = 'vw_historico_portifolio'
    ) AS view_portfolio_existe,
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'vw_historico_portifolio' AND column_name = 'url_foto_cliente'
    ) AS migracao_07_aplicada,

    -- Migração 08 (CEP do profissional)
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profissionais' AND column_name = 'cep'
    ) AS migracao_08_aplicada,

    -- Migração 09 (categorias/subcategorias + FK composta)
    EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_name = 'categorias'
    ) AS tabela_categorias_existe,
    EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_name = 'subcategorias'
    ) AS tabela_subcategorias_existe,
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profissionais' AND column_name = 'subcategoria_id'
    ) AS coluna_subcategoria_id_existe,
    EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_profissionais_subcategoria_categoria'
    ) AS fk_composta_existe,
    EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_prof_categoria_completa'
    ) AS check_categoria_completa_existe,

    -- Migração 10 (backfill -- indireto: existe algum profissional sem categoria?)
    (SELECT COUNT(*) FROM profissionais WHERE categoria_id IS NULL) AS profissionais_sem_categoria,
    (SELECT COUNT(*) FROM profissionais) AS total_profissionais;
