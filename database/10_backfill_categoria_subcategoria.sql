-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Backfill de categoria/subcategoria para profissionais antigos"
--
--  Rodar como: psql "sua-connection-string-neon" -f 10_backfill_categoria_subcategoria.sql
--  Pré-requisito: migração 09 (categorias/subcategorias) já aplicada.
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - POR QUE ISTO EXISTE
--
--  A migração 09 criou `categoria_id`/`subcategoria_id` em `profissionais` e
--  passou a EXIGIR os dois no cadastro NOVO -- mas não tocou em quem já
--  estava cadastrado antes dela. Todo profissional criado antes da migração
--  09 (inclusive o seed de teste, `02_seed_teste_1.sql`) ficou com os dois
--  campos NULL, só com o `profissao`/`categoria_atuacao` (texto livre) de
--  antes.
--
--  Consequência prática: o filtro EXATO por subcategoria no mapa
--  (`GET /profissionais/proximos?subcategoria_id=...`, ver
--  `profissionais.repository.ts`) SÓ compara `p.subcategoria_id = $id` --
--  um profissional com `subcategoria_id` NULL nunca casa com nenhum filtro,
--  e por isso "sumia" de qualquer busca filtrada por especialidade, mesmo
--  aparecendo normalmente no mapa sem filtro nenhum.
--
--  Esta migração é o CONSERTO DE VERDADE (não um contorno na query): dar a
--  cada profissional antigo uma categoria/subcategoria de verdade, igual a
--  quem se cadastrou depois da migração 09.
-- ============================================================================


-- ============================================================================
--  SEÇÃO 2 - CATEGORIA/SUBCATEGORIA "OUTROS" (rede de segurança)
--
--  Nem todo texto livre antigo bate com uma das ~60 subcategorias do seed
--  (erro de digitação, profissão que não está na lista, campo em branco...).
--  Para esses casos, criamos uma categoria/subcategoria "Outros" -- ninguém
--  fica com categoria_id/subcategoria_id NULL depois desta migração, e o
--  profissional continua aparecendo em buscas SEM filtro (o que já
--  funcionava) e pode, depois, editar o próprio perfil (`PATCH
--  /profissionais/me`) para escolher a especialidade certa quando quiser.
-- ============================================================================

INSERT INTO categorias (nome) VALUES ('Outros')
ON CONFLICT (nome) DO NOTHING;

INSERT INTO subcategorias (categoria_id, nome)
SELECT c.categoria_id, 'Outros'
FROM categorias c
WHERE c.nome = 'Outros'
ON CONFLICT (categoria_id, nome) DO NOTHING;


-- ============================================================================
--  SEÇÃO 3 - BACKFILL INTELIGENTE (por nome)
--
--  Para quem tem texto livre antigo (`profissao` no PF, `categoria_atuacao`
--  no PJ), tenta achar a subcategoria cujo NOME aparece dentro desse texto
--  -- ex.: profissao = "Eletricista Residencial" casa com a subcategoria
--  "Eletricista". Usa `unaccent`/`lower` para ignorar acento e maiúscula,
--  igual ao filtro textual que já existia em `buscarProximos`.
--
--  `ORDER BY length(sc.nome) DESC LIMIT 1` (dentro do LATERAL) resolve
--  ambiguidade: se o texto livre casar com mais de uma subcategoria (raro,
--  mas possível), fica com o nome MAIS ESPECÍFICO (o mais longo) em vez de
--  um match arbitrário.
-- ============================================================================

UPDATE profissionais p
SET categoria_id    = melhor.categoria_id,
    subcategoria_id = melhor.subcategoria_id
FROM LATERAL (
    SELECT sc.subcategoria_id, sc.categoria_id
    FROM subcategorias sc
    WHERE unaccent(lower(COALESCE(p.profissao, p.categoria_atuacao, '')))
          LIKE '%' || unaccent(lower(sc.nome)) || '%'
    ORDER BY length(sc.nome) DESC
    LIMIT 1
) AS melhor
WHERE p.subcategoria_id IS NULL
  AND COALESCE(p.profissao, p.categoria_atuacao) IS NOT NULL;


-- ============================================================================
--  SEÇÃO 4 - BACKFILL FINAL (rede de segurança "Outros")
--
--  Quem sobrou -- ou nunca teve `profissao`/`categoria_atuacao` preenchido,
--  ou o texto não bateu com nenhuma subcategoria da Seção 3 -- recebe
--  "Outros" (categoria e subcategoria). Depois desta seção, NENHUM
--  profissional fica com categoria_id/subcategoria_id NULL.
-- ============================================================================

UPDATE profissionais p
SET categoria_id    = outros.categoria_id,
    subcategoria_id = outros.subcategoria_id
FROM (
    SELECT s.subcategoria_id, s.categoria_id
    FROM subcategorias s
    JOIN categorias c ON c.categoria_id = s.categoria_id
    WHERE c.nome = 'Outros' AND s.nome = 'Outros'
    LIMIT 1
) AS outros
WHERE p.subcategoria_id IS NULL;


-- ============================================================================
--  SEÇÃO 5 - VERIFICAÇÃO
-- ============================================================================

DO $$
DECLARE
    total_profissionais INT;
    sem_categoria INT;
    via_outros INT;
BEGIN
    SELECT COUNT(*) INTO total_profissionais FROM profissionais;

    SELECT COUNT(*) INTO sem_categoria
    FROM profissionais
    WHERE categoria_id IS NULL OR subcategoria_id IS NULL;

    SELECT COUNT(*) INTO via_outros
    FROM profissionais p
    JOIN subcategorias s ON s.subcategoria_id = p.subcategoria_id
    JOIN categorias c ON c.categoria_id = s.categoria_id
    WHERE c.nome = 'Outros';

    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 10 aplicada com sucesso.';
    RAISE NOTICE ' Total de profissionais: %', total_profissionais;
    RAISE NOTICE ' Ainda sem categoria/subcategoria (esperado 0): %', sem_categoria;
    RAISE NOTICE ' Caidos na rede de seguranca "Outros" (nao bateram com nada): %', via_outros;
    RAISE NOTICE ' Esses profissionais em "Outros" podem editar o proprio perfil';
    RAISE NOTICE ' (PATCH /profissionais/me) para escolher a especialidade certa.';
    RAISE NOTICE '---------------------------------------------';
END $$;
