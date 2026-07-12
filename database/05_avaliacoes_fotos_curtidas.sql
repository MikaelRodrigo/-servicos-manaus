-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Portfólio estilo Shopee" - múltiplas fotos por avaliação + curtidas
--
--  Rodar como: psql "sua-connection-string-neon" -f 05_avaliacoes_fotos_curtidas.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - MÚLTIPLAS FOTOS POR AVALIAÇÃO
--
--  Até aqui, `avaliacoes_profissional.url_foto_servico` guardava NO MÁXIMO
--  uma foto por avaliação. O portfólio público (a "vitrine" que convence um
--  cliente novo a contratar) fica muito mais rico com várias fotos, então
--  criamos uma tabela FILHA (1 avaliação -> N fotos) em vez de continuar
--  espremendo tudo numa coluna só.
--
--  Por que tabela nova em vez de, por exemplo, um array de texto na própria
--  coluna? Porque cada foto pode um dia precisar de metadados próprios
--  (ordem de exibição, quem denunciou, data de upload individual) -- um
--  array de TEXT não comporta isso sem gambiarra. Uma tabela comporta.
-- ============================================================================

CREATE TABLE IF NOT EXISTS avaliacoes_profissional_fotos (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    avaliacao_id  UUID NOT NULL
        REFERENCES avaliacoes_profissional (id)
        ON DELETE CASCADE,

    url_foto      TEXT NOT NULL,

    -- Ordem de exibição na galeria (0 = primeira). Não é a ordem de upload
    -- necessariamente -- fica aqui já pensando numa futura tela de
    -- reordenar fotos, mesmo que hoje a gente só grave na ordem de envio.
    ordem         SMALLINT NOT NULL DEFAULT 0,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_avalprof_fotos_avaliacao
    ON avaliacoes_profissional_fotos (avaliacao_id);

COMMENT ON TABLE avaliacoes_profissional_fotos IS
    'Fotos do portfólio de uma avaliação (cliente avaliando profissional). Substitui a antiga coluna única avaliacoes_profissional.url_foto_servico -- 1 avaliação pode ter várias fotos agora.';

-- ----------------------------------------------------------------------------
-- Migra os dados que já existiam na coluna antiga para a tabela nova, ANTES
-- de remover a coluna. Sem isso, fotos que usuários já enviaram (avaliações
-- de teste, por exemplo) desapareceriam do portfólio.
-- ----------------------------------------------------------------------------
INSERT INTO avaliacoes_profissional_fotos (avaliacao_id, url_foto, ordem)
SELECT id, url_foto_servico, 0
FROM avaliacoes_profissional
WHERE url_foto_servico IS NOT NULL
  -- Idempotência: se a migração já rodou antes, não duplica as fotos.
  AND NOT EXISTS (
      SELECT 1 FROM avaliacoes_profissional_fotos f
      WHERE f.avaliacao_id = avaliacoes_profissional.id
  );

-- A coluna antiga só suportava uma foto -- depois da migração dos dados
-- acima, ela vira redundante e sai do schema. Toda foto agora mora em
-- avaliacoes_profissional_fotos.
ALTER TABLE avaliacoes_profissional DROP COLUMN IF EXISTS url_foto_servico;


-- ============================================================================
--  SEÇÃO 2 - CURTIDAS ("Útil") EM AVALIAÇÕES
--
--  Qualquer pessoa AUTENTICADA (cliente OU profissional -- o portfólio é
--  visto por quem ainda está decidindo se contrata) pode marcar uma
--  avaliação como "útil", uma vez cada. Sem contar duas vezes o voto da
--  mesma pessoa: PRIMARY KEY (avaliacao_id, usuario_id) garante isso no
--  nível do banco, não só na aplicação.
--
--  POR QUE NÃO TEM FOREIGN KEY em usuario_id?
--  Porque "usuário" aqui pode ser um cliente OU um profissional -- duas
--  tabelas diferentes (não existe uma tabela `usuarios` unificada neste
--  schema, ver Single Table Design em `clientes`/`profissionais`). Postgres
--  não tem "FK polimórfica" nativa. A alternativa correta seria criar uma
--  tabela `usuarios` central só com os IDs -- mudança grande demais para
--  esta etapa. Optamos por confiar na aplicação para gravar um ID válido
--  (o `sub` do JWT, que SEMPRE veio de um cadastro real) e documentar essa
--  limitação aqui, explicitamente, em vez de fingir que não existe.
-- ============================================================================

DO $$
BEGIN
    CREATE TYPE papel_avaliador_enum AS ENUM ('cliente', 'profissional');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS avaliacoes_profissional_curtidas (
    avaliacao_id   UUID NOT NULL
        REFERENCES avaliacoes_profissional (id)
        ON DELETE CASCADE,

    usuario_id     UUID NOT NULL,
    usuario_papel  papel_avaliador_enum NOT NULL,

    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (avaliacao_id, usuario_id)
);

CREATE INDEX IF NOT EXISTS idx_avalprof_curtidas_avaliacao
    ON avaliacoes_profissional_curtidas (avaliacao_id);

COMMENT ON TABLE avaliacoes_profissional_curtidas IS
    'Um registro por (avaliação, usuário que curtiu) -- o botão "Útil" do portfólio. Sem FK em usuario_id de propósito: ver comentário acima (não existe tabela usuarios unificada).';


-- ============================================================================
--  SEÇÃO 3 - VIEW vw_historico_portifolio ATUALIZADA
--
--  Precisa expor: o ID da própria avaliação (para o botão "Útil" saber em
--  que curtir), o array de fotos (LEFT JOIN LATERAL + array_agg, em vez de
--  uma coluna só) e o total de curtidas.
--
--  `CREATE OR REPLACE VIEW` -- não precisa dropar a antiga, só redefinir.
-- ============================================================================

CREATE OR REPLACE VIEW vw_historico_portifolio AS
SELECT
    s.profissional_id,
    s.id_servico,
    ap.id                                 AS avaliacao_id,
    ap.cliente_id,

    COALESCE(c.nome, c.razao_social)      AS nome_cliente,
    c.tipo_pessoa                         AS tipo_cliente,

    ap.comentario,

    -- Array de URLs, já na ordem de exibição. Sem foto nenhuma, vira um
    -- array vazio (nunca NULL) -- mais fácil de tratar no backend/Flutter
    -- do que ficar checando NULL vs. array vazio em dois lugares.
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

    -- LATERAL: a subquery pode referenciar `ap.id` da linha externa --
    -- um JOIN comum não permite isso. Uma linha por avaliação, sempre
    -- (ON TRUE), com o array já pronto.
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
--  SEÇÃO 4 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 05 aplicada com sucesso.';
    RAISE NOTICE ' Tabelas novas: avaliacoes_profissional_fotos, avaliacoes_profissional_curtidas';
    RAISE NOTICE ' Coluna removida: avaliacoes_profissional.url_foto_servico (dados migrados antes)';
    RAISE NOTICE ' View atualizada: vw_historico_portifolio (avaliacao_id, urls_fotos, total_curtidas)';
    RAISE NOTICE '---------------------------------------------';
END $$;
