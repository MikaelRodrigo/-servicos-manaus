-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa 1 - Schema do Banco de Dados
--
--  Requisitos: PostgreSQL 14+  |  PostGIS 3.x
--  Rodar como: psql -U postgres -d servicos_manaus -f 01_schema.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 0 - EXTENSÕES
-- ============================================================================

-- PostGIS: adiciona os tipos geometry/geography e funções como ST_DWithin.
CREATE EXTENSION IF NOT EXISTS postgis;

-- pgcrypto: fornece gen_random_uuid() para as chaves primárias.
-- (No PG 13+ o gen_random_uuid() já é nativo, mas a extensão não atrapalha.)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- unaccent: permite buscar "servico" e achar "serviço". Vai ser útil na Etapa 4.
CREATE EXTENSION IF NOT EXISTS unaccent;


-- ============================================================================
--  SEÇÃO 1 - TIPOS ENUMERADOS
--
--  Por que ENUM e não VARCHAR + CHECK?
--  ENUM ocupa 4 bytes, é validado pelo banco, e o Prisma (Etapa 2) gera
--  automaticamente um enum TypeScript a partir dele. Ganho de tipagem grátis.
-- ============================================================================

CREATE TYPE tipo_pessoa_enum AS ENUM ('PF', 'PJ');

CREATE TYPE status_servico_enum AS ENUM (
    'SOLICITADO',    -- cliente pediu, profissional ainda não respondeu
    'ACEITO',        -- profissional aceitou
    'EM_ANDAMENTO',  -- profissional deu início
    'CONCLUIDO',     -- terminou -> LIBERA as avaliações
    'CANCELADO',     -- cancelado por qualquer uma das partes
    'RECUSADO'       -- profissional negou a solicitação
);


-- ============================================================================
--  SEÇÃO 2 - FUNÇÃO UTILITÁRIA (trigger de updated_at)
--
--  Toda tabela terá created_at e updated_at. O created_at o DEFAULT resolve.
--  O updated_at precisa de um trigger, senão você teria que lembrar de
--  atualizar na mão em TODO UPDATE do backend. Ninguém lembra.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_atualiza_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
--  SEÇÃO 3 - TABELA: profissionais
--
--  Single Table Design: PF e PJ na mesma tabela, discriminados por
--  tipo_pessoa. As colunas de cada tipo são anuláveis.
--
--  ATENÇÃO: colunas anuláveis sem CHECK = banco sujo. A constraint
--  chk_prof_coerencia_tipo garante que um 'PJ' NUNCA tenha CPF preenchido
--  e um 'PF' NUNCA tenha CNPJ. O banco recusa o INSERT.
-- ============================================================================

CREATE TABLE profissionais (
    profissional_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    tipo_pessoa         tipo_pessoa_enum NOT NULL,

    -- ---------- Campos comuns a PF e PJ ----------
    email               VARCHAR(255) NOT NULL UNIQUE,
    contato             VARCHAR(20)  NOT NULL,   -- ex: 5592988887777 (só dígitos)

    latitude            DOUBLE PRECISION,
    longitude           DOUBLE PRECISION,

    -- ---------- Campos exclusivos de PF ----------
    nome                VARCHAR(150),
    profissao           VARCHAR(100),
    data_nascimento     DATE,
    cpf                 CHAR(11) UNIQUE,
    identidade          VARCHAR(20),             -- RG: tem letra em alguns estados
    url_foto_com_rg     TEXT,                    -- selfie segurando o documento

    -- ---------- Campos exclusivos de PJ ----------
    razao_social        VARCHAR(200),
    categoria_atuacao   VARCHAR(100),
    data_criacao        DATE,                    -- data de abertura da empresa
    cnpj                CHAR(14) UNIQUE,
    url_foto            TEXT,                    -- logo / fachada

    -- ---------- Auditoria ----------
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ---------- COLUNA GERADA: a mágica do mapa ----------
    -- O Postgres calcula esta coluna sozinho a partir de latitude/longitude.
    -- Você NUNCA faz INSERT nela. É ela que recebe o índice espacial GIST.
    -- Repare na ordem: ST_MakePoint(LONGITUDE, LATITUDE). Trocar a ordem é o
    -- erro nº 1 de quem começa com PostGIS -- seu profissional de Manaus vai
    -- aparecer no meio do Oceano Índico.
    -- SRID 4326 = o padrão do GPS (WGS 84), o mesmo que o celular devolve.
    localizacao GEOGRAPHY(POINT, 4326)
        GENERATED ALWAYS AS (
            ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
        ) STORED,

    -- ======================= CONSTRAINTS =======================

    -- Regra de ouro do Single Table Design.
    CONSTRAINT chk_prof_coerencia_tipo CHECK (
        (
            tipo_pessoa = 'PF'
            AND nome            IS NOT NULL
            AND cpf             IS NOT NULL
            AND data_nascimento IS NOT NULL
            -- e nada de PJ:
            AND razao_social IS NULL
            AND cnpj         IS NULL
            AND data_criacao IS NULL
        )
        OR
        (
            tipo_pessoa = 'PJ'
            AND razao_social IS NOT NULL
            AND cnpj         IS NOT NULL
            -- e nada de PF:
            AND nome            IS NULL
            AND cpf             IS NULL
            AND data_nascimento IS NULL
            AND identidade      IS NULL
            AND url_foto_com_rg IS NULL
        )
    ),

    -- CPF/CNPJ guardados só com dígitos. Formatação é problema do front-end.
    -- (Isto valida o FORMATO, não o dígito verificador. Esse fica no backend.)
    CONSTRAINT chk_prof_cpf_digitos  CHECK (cpf  IS NULL OR cpf  ~ '^[0-9]{11}$'),
    CONSTRAINT chk_prof_cnpj_digitos CHECK (cnpj IS NULL OR cnpj ~ '^[0-9]{14}$'),

    -- Coordenadas válidas.
    CONSTRAINT chk_prof_latitude  CHECK (latitude  IS NULL OR latitude  BETWEEN  -90 AND  90),
    CONSTRAINT chk_prof_longitude CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),

    -- Ou tem as duas coordenadas, ou não tem nenhuma. Meio ponto não existe.
    CONSTRAINT chk_prof_coords_completas CHECK (
        (latitude IS NULL AND longitude IS NULL)
        OR
        (latitude IS NOT NULL AND longitude IS NOT NULL)
    ),

    CONSTRAINT chk_prof_email_formato CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

-- Índice espacial. SEM ELE, buscar "profissionais num raio de 5km" faz um
-- Seq Scan na tabela inteira. Com ele, o Postgres usa uma R-Tree.
CREATE INDEX idx_profissionais_localizacao ON profissionais USING GIST (localizacao);

-- Filtros comuns na tela de busca.
CREATE INDEX idx_profissionais_profissao ON profissionais (profissao) WHERE profissao IS NOT NULL;
CREATE INDEX idx_profissionais_categoria ON profissionais (categoria_atuacao) WHERE categoria_atuacao IS NOT NULL;

CREATE TRIGGER trg_profissionais_updated_at
    BEFORE UPDATE ON profissionais
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON COLUMN profissionais.localizacao IS
    'Coluna GERADA a partir de latitude/longitude. Nunca escrever diretamente.';
COMMENT ON COLUMN profissionais.url_foto_com_rg IS
    'DADO PESSOAL SENSIVEL (LGPD). Bucket PRIVADO, acesso via URL assinada.';


-- ============================================================================
--  SEÇÃO 4 - TABELA: clientes
--
--  Mesma estratégia. O cliente não precisa de profissao/identidade.
-- ============================================================================

CREATE TABLE clientes (
    cliente_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    tipo_pessoa         tipo_pessoa_enum NOT NULL,

    -- ---------- Campos comuns ----------
    email               VARCHAR(255) NOT NULL UNIQUE,
    contato             VARCHAR(20)  NOT NULL,

    latitude            DOUBLE PRECISION,
    longitude           DOUBLE PRECISION,

    -- ---------- Exclusivos de PF ----------
    nome                VARCHAR(150),
    cpf                 CHAR(11) UNIQUE,
    url_foto_com_rg     TEXT,

    -- ---------- Exclusivos de PJ ----------
    razao_social        VARCHAR(200),
    data_criacao        DATE,
    cnpj                CHAR(14) UNIQUE,
    url_foto            TEXT,

    -- ---------- Auditoria ----------
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ---------- Coluna gerada ----------
    localizacao GEOGRAPHY(POINT, 4326)
        GENERATED ALWAYS AS (
            ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
        ) STORED,

    -- ======================= CONSTRAINTS =======================

    CONSTRAINT chk_cli_coerencia_tipo CHECK (
        (
            tipo_pessoa = 'PF'
            AND nome IS NOT NULL
            AND cpf  IS NOT NULL
            AND razao_social IS NULL
            AND cnpj         IS NULL
            AND data_criacao IS NULL
        )
        OR
        (
            tipo_pessoa = 'PJ'
            AND razao_social IS NOT NULL
            AND cnpj         IS NOT NULL
            AND nome            IS NULL
            AND cpf             IS NULL
            AND url_foto_com_rg IS NULL
        )
    ),

    CONSTRAINT chk_cli_cpf_digitos  CHECK (cpf  IS NULL OR cpf  ~ '^[0-9]{11}$'),
    CONSTRAINT chk_cli_cnpj_digitos CHECK (cnpj IS NULL OR cnpj ~ '^[0-9]{14}$'),

    CONSTRAINT chk_cli_latitude  CHECK (latitude  IS NULL OR latitude  BETWEEN  -90 AND  90),
    CONSTRAINT chk_cli_longitude CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),

    CONSTRAINT chk_cli_coords_completas CHECK (
        (latitude IS NULL AND longitude IS NULL)
        OR
        (latitude IS NOT NULL AND longitude IS NOT NULL)
    ),

    CONSTRAINT chk_cli_email_formato CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

CREATE INDEX idx_clientes_localizacao ON clientes USING GIST (localizacao);

CREATE TRIGGER trg_clientes_updated_at
    BEFORE UPDATE ON clientes
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();


-- ============================================================================
--  SEÇÃO 5 - TABELA: servicos
--
--  É a tabela-ponte. Todo o resto do sistema gira em torno dela: sem um
--  serviço concluído, ninguém avalia ninguém.
-- ============================================================================

CREATE TABLE servicos (
    id_servico          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    cliente_id          UUID NOT NULL,
    profissional_id     UUID NOT NULL,

    status              status_servico_enum NOT NULL DEFAULT 'SOLICITADO',

    descricao           TEXT,
    data                TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- data da solicitação
    data_conclusao      TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ======================= CHAVES ESTRANGEIRAS =======================
    --
    -- ON DELETE RESTRICT: você NÃO apaga um cliente que tem histórico de
    -- serviços. Perderia a rastreabilidade das avaliações. Para "sair do
    -- app", o correto é um soft delete (coluna deleted_at) -- Etapa 3.

    CONSTRAINT fk_servicos_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES clientes (cliente_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_servicos_profissional
        FOREIGN KEY (profissional_id)
        REFERENCES profissionais (profissional_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- ---------------------------------------------------------------
    -- ESTE UNIQUE PARECE REDUNDANTE (id_servico já é PK), MAS NÃO É.
    --
    -- Ele existe para servir de ALVO de uma Foreign Key COMPOSTA vinda das
    -- tabelas de avaliação. Sem ele, o Postgres recusa aquela FK.
    -- O efeito: torna FISICAMENTE IMPOSSÍVEL uma avaliação apontar para o
    -- serviço #1 mas com o cliente do serviço #2. O banco garante, não o
    -- seu código Node. Veja a Seção 6.
    -- ---------------------------------------------------------------
    CONSTRAINT uq_servicos_triade UNIQUE (id_servico, cliente_id, profissional_id),

    -- Só um serviço concluído tem data de conclusão, e vice-versa.
    CONSTRAINT chk_servico_conclusao CHECK (
        (status = 'CONCLUIDO' AND data_conclusao IS NOT NULL)
        OR
        (status <> 'CONCLUIDO' AND data_conclusao IS NULL)
    ),

    CONSTRAINT chk_servico_datas CHECK (
        data_conclusao IS NULL OR data_conclusao >= data
    )
);

CREATE INDEX idx_servicos_cliente      ON servicos (cliente_id);
CREATE INDEX idx_servicos_profissional ON servicos (profissional_id);
CREATE INDEX idx_servicos_status       ON servicos (status);

CREATE TRIGGER trg_servicos_updated_at
    BEFORE UPDATE ON servicos
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();


-- ============================================================================
--  SEÇÃO 6 - TABELA: avaliacoes_profissional  (o CLIENTE avalia o PRESTADOR)
-- ============================================================================

CREATE TABLE avaliacoes_profissional (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_servico               UUID NOT NULL,
    cliente_id               UUID NOT NULL,
    profissional_id          UUID NOT NULL,

    estrelas_tecnico         SMALLINT NOT NULL,
    estrelas_comportamental  SMALLINT NOT NULL,
    estrelas_economico       SMALLINT NOT NULL,

    comentario               TEXT,
    url_foto_servico         TEXT,

    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ======================= CONSTRAINTS =======================

    -- FK COMPOSTA. Aponta para uq_servicos_triade.
    -- Impede que a avaliação minta sobre quem prestou/contratou o serviço.
    -- ON DELETE CASCADE: se o serviço for removido, a avaliação vai junto.
    CONSTRAINT fk_avalprof_servico_triade
        FOREIGN KEY (id_servico, cliente_id, profissional_id)
        REFERENCES servicos (id_servico, cliente_id, profissional_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    -- Um serviço recebe UMA avaliação do cliente. Só uma.
    CONSTRAINT uq_avalprof_por_servico UNIQUE (id_servico),

    -- As três notas, de 1 a 5.
    CONSTRAINT chk_avalprof_tecnico        CHECK (estrelas_tecnico        BETWEEN 1 AND 5),
    CONSTRAINT chk_avalprof_comportamental CHECK (estrelas_comportamental BETWEEN 1 AND 5),
    CONSTRAINT chk_avalprof_economico      CHECK (estrelas_economico      BETWEEN 1 AND 5)
);

CREATE INDEX idx_avalprof_profissional ON avaliacoes_profissional (profissional_id);
CREATE INDEX idx_avalprof_cliente      ON avaliacoes_profissional (cliente_id);

CREATE TRIGGER trg_avalprof_updated_at
    BEFORE UPDATE ON avaliacoes_profissional
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();


-- ============================================================================
--  SEÇÃO 7 - TABELA: avaliacoes_cliente  (o PRESTADOR avalia o CLIENTE)
-- ============================================================================

CREATE TABLE avaliacoes_cliente (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_servico               UUID NOT NULL,
    cliente_id               UUID NOT NULL,
    profissional_id          UUID NOT NULL,

    estrelas_clareza         SMALLINT NOT NULL,   -- clareza do que foi pedido
    estrelas_comportamental  SMALLINT NOT NULL,
    estrelas_pagamento       SMALLINT NOT NULL,   -- pagou em dia?

    comentario               TEXT,                -- não estava no escopo, mas simetria ajuda

    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_avalcli_servico_triade
        FOREIGN KEY (id_servico, cliente_id, profissional_id)
        REFERENCES servicos (id_servico, cliente_id, profissional_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT uq_avalcli_por_servico UNIQUE (id_servico),

    CONSTRAINT chk_avalcli_clareza        CHECK (estrelas_clareza        BETWEEN 1 AND 5),
    CONSTRAINT chk_avalcli_comportamental CHECK (estrelas_comportamental BETWEEN 1 AND 5),
    CONSTRAINT chk_avalcli_pagamento      CHECK (estrelas_pagamento      BETWEEN 1 AND 5)
);

CREATE INDEX idx_avalcli_cliente      ON avaliacoes_cliente (cliente_id);
CREATE INDEX idx_avalcli_profissional ON avaliacoes_cliente (profissional_id);

CREATE TRIGGER trg_avalcli_updated_at
    BEFORE UPDATE ON avaliacoes_cliente
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();


-- ============================================================================
--  SEÇÃO 8 - TRIGGER DE REGRA DE NEGÓCIO
--
--  Um CHECK não consegue olhar outra tabela. Como garantir que ninguém
--  avalie um serviço que ainda está 'EM_ANDAMENTO'? Com um trigger.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_valida_servico_concluido()
RETURNS TRIGGER AS $$
DECLARE
    v_status status_servico_enum;
BEGIN
    SELECT status INTO v_status
    FROM servicos
    WHERE id_servico = NEW.id_servico;

    IF v_status <> 'CONCLUIDO' THEN
        RAISE EXCEPTION
            'Nao e possivel avaliar: o servico % esta com status %, e nao CONCLUIDO.',
            NEW.id_servico, v_status
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_avalprof_exige_concluido
    BEFORE INSERT ON avaliacoes_profissional
    FOR EACH ROW EXECUTE FUNCTION fn_valida_servico_concluido();

CREATE TRIGGER trg_avalcli_exige_concluido
    BEFORE INSERT ON avaliacoes_cliente
    FOR EACH ROW EXECUTE FUNCTION fn_valida_servico_concluido();


-- ============================================================================
--  SEÇÃO 9 - VIEW: vw_historico_portifolio
--
--  O portfólio público do profissional. Junta serviço + avaliação + cliente.
--
--  Detalhes:
--  - INNER JOIN em avaliacoes_profissional: serviço sem avaliação não vira
--    portfólio.
--  - COALESCE(nome, razao_social): o "nome do cliente" muda conforme PF/PJ.
--    Este é exatamente o preço que se paga pelo Single Table Design.
--  - Incluí profissional_id: sem ele a view é inútil, você não conseguiria
--    filtrar de quem é o portfólio.
--  - media_estrelas: cortesia, evita fazer a conta no Flutter.
-- ============================================================================

CREATE OR REPLACE VIEW vw_historico_portifolio AS
SELECT
    s.profissional_id,
    s.id_servico,
    ap.cliente_id,

    COALESCE(c.nome, c.razao_social)  AS nome_cliente,
    c.tipo_pessoa                     AS tipo_cliente,

    ap.comentario,
    ap.url_foto_servico,

    ap.estrelas_tecnico,
    ap.estrelas_comportamental,
    ap.estrelas_economico,

    ROUND(
        ( ap.estrelas_tecnico
        + ap.estrelas_comportamental
        + ap.estrelas_economico
        )::numeric / 3
    , 2)                              AS media_estrelas,

    s.data_conclusao,
    ap.created_at                     AS data_avaliacao

FROM servicos s
    INNER JOIN avaliacoes_profissional ap ON ap.id_servico = s.id_servico
    INNER JOIN clientes c                 ON c.cliente_id  = ap.cliente_id

WHERE s.status = 'CONCLUIDO'

ORDER BY ap.created_at DESC;


COMMENT ON VIEW vw_historico_portifolio IS
    'Portfolio publico do profissional. Filtrar sempre por profissional_id.';


-- ============================================================================
--  SEÇÃO 10 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Schema criado com sucesso.';
    RAISE NOTICE ' PostGIS versao: %', postgis_version();
    RAISE NOTICE '---------------------------------------------';
END $$;
