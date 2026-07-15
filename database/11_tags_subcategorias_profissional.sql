-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Tags de Especialidade" (múltiplas subcategorias por profissional)
--
--  Rodar como: psql "sua-connection-string-neon" -f 11_tags_subcategorias_profissional.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - POR QUE ISTO EXISTE
--
--  Até aqui, cada profissional tinha UMA ÚNICA categoria/subcategoria
--  (profissionais.categoria_id/subcategoria_id, migração 09) -- escolhida no
--  cadastro e trocável na edição de perfil, mas sempre uma coisa só. Na
--  prática, muitos profissionais atendem em MAIS DE UMA especialidade (ex.:
--  "Eletricista" e "Instalação de Ar-Condicionado").
--
--  Esta migração cria uma tabela de junção N:N: um profissional passa a
--  poder ter VÁRIAS subcategorias ("tags"), e aparece na busca de QUALQUER
--  uma delas.
--
--  `profissionais.categoria_id`/`subcategoria_id` NÃO são removidas -- elas
--  continuam sendo a escolha OBRIGATÓRIA feita no CADASTRO (auth.routes.ts,
--  via `SeletorCategoriaCascata` no app), e essa escolha inicial vira
--  automaticamente a PRIMEIRA tag do profissional (ver Seção 3, backfill, e
--  o `WITH` novo em `criarProfissionalPF`/`criarProfissionalPJ` no backend a
--  partir de agora). A partir desta migração, porém, a BUSCA por
--  proximidade (`buscarProximos`) e o perfil público passam a olhar para a
--  tabela de junção abaixo, não mais só para a coluna única -- um
--  profissional que adicionar tags novas depois do cadastro (tela de editar
--  perfil) passa a aparecer também nas buscas por essas subcategorias novas.
-- ============================================================================


-- ============================================================================
--  SEÇÃO 2 - TABELA profissional_subcategorias
-- ============================================================================

CREATE TABLE IF NOT EXISTS profissional_subcategorias (
    profissional_id  UUID NOT NULL REFERENCES profissionais (profissional_id) ON DELETE CASCADE,
    subcategoria_id  INT  NOT NULL REFERENCES subcategorias (subcategoria_id) ON DELETE RESTRICT,
    criado_em        TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (profissional_id, subcategoria_id)
);

-- A PRIMARY KEY composta já cria um índice em (profissional_id, subcategoria_id)
-- -- cobre "quais tags tem esse profissional". Falta um índice na ordem
-- INVERSA, para "quais profissionais têm essa subcategoria" -- é exatamente
-- o que a busca por proximidade e o filtro exato do mapa fazem.
CREATE INDEX IF NOT EXISTS idx_profissional_subcategorias_subcategoria_id
    ON profissional_subcategorias (subcategoria_id);

COMMENT ON TABLE profissional_subcategorias IS
    'Tags de especialidade (N:N) -- um profissional pode ter várias subcategorias. Passa a ser a fonte da busca por proximidade a partir da migração 11; profissionais.categoria_id/subcategoria_id continuam existindo só como registro da escolha obrigatória feita no cadastro (e viram automaticamente a primeira tag).';


-- ============================================================================
--  SEÇÃO 3 - BACKFILL: a categoria/subcategoria única de cada profissional
--  vira a primeira tag dele.
-- ============================================================================

INSERT INTO profissional_subcategorias (profissional_id, subcategoria_id)
SELECT p.profissional_id, p.subcategoria_id
FROM profissionais p
WHERE p.subcategoria_id IS NOT NULL
ON CONFLICT (profissional_id, subcategoria_id) DO NOTHING;


-- ============================================================================
--  SEÇÃO 4 - VERIFICAÇÃO
-- ============================================================================

DO $$
DECLARE
    total_profissionais    INT;
    total_tags              INT;
    profissionais_sem_tag   INT;
BEGIN
    SELECT COUNT(*) INTO total_profissionais FROM profissionais;
    SELECT COUNT(*) INTO total_tags FROM profissional_subcategorias;
    SELECT COUNT(*) INTO profissionais_sem_tag
    FROM profissionais p
    WHERE NOT EXISTS (
        SELECT 1 FROM profissional_subcategorias ps WHERE ps.profissional_id = p.profissional_id
    );

    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 11 aplicada com sucesso.';
    RAISE NOTICE ' Total de profissionais: %', total_profissionais;
    RAISE NOTICE ' Total de tags (profissional_subcategorias): %', total_tags;
    RAISE NOTICE ' Profissionais sem NENHUMA tag: % (esperado: 0)', profissionais_sem_tag;
    RAISE NOTICE '---------------------------------------------';
END $$;
