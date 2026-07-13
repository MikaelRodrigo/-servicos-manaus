-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Seleção de Categoria em Cascata"
--
--  Rodar como: psql "sua-connection-string-neon" -f 09_categorias_subcategorias.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - POR QUE ISTO EXISTE
--
--  Até aqui, `profissionais.profissao` (PF) e `profissionais.categoria_atuacao`
--  (PJ) eram TEXTO LIVRE -- cada profissional digitava o que quisesse
--  ("Eletricista", "eletricista", "Elétrico", "Eletrecista"...). Isso quebra
--  qualquer filtro/agrupamento no app (a busca do mapa faz um LIKE torto em
--  cima disso) e não dá pra montar um seletor de categorias de verdade sem
--  uma lista fixa por trás.
--
--  Esta migração cria duas tabelas de referência (PAI/FILHO):
--    - `categorias`     -- ex.: "Beleza e Bem-Estar"
--    - `subcategorias`  -- ex.: "Barbeiro", sempre presa a UMA categoria
--
--  E troca as duas colunas de texto livre por DUAS colunas de chave
--  estrangeira em `profissionais`: `categoria_id` e `subcategoria_id`. O
--  profissional passa a ESCOLHER de uma lista fechada (nunca mais digitar),
--  e o banco garante a integridade da relação pai-filho -- ver a FK composta
--  na Seção 3.
--
--  `profissao`/`categoria_atuacao` NÃO são apagadas (dado histórico de quem
--  já se cadastrou antes desta migração), só deixam de ser usadas pelo
--  fluxo de cadastro a partir de agora -- ver COMMENT ON COLUMN no final.
-- ============================================================================


-- ============================================================================
--  SEÇÃO 2 - TABELAS categorias / subcategorias
-- ============================================================================

CREATE TABLE IF NOT EXISTS categorias (
    categoria_id  SERIAL PRIMARY KEY,
    nome          VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS subcategorias (
    subcategoria_id  SERIAL PRIMARY KEY,
    categoria_id     INT NOT NULL REFERENCES categorias (categoria_id) ON DELETE RESTRICT,
    nome             VARCHAR(100) NOT NULL,

    -- Mesmo nome de subcategoria pode existir em categorias diferentes no
    -- futuro (ex.: "Suporte em TI" hoje só existe em uma, mas a regra vale
    -- por categoria, não globalmente) -- então a unicidade é composta.
    CONSTRAINT uq_subcategorias_categoria_nome UNIQUE (categoria_id, nome),

    -- Esta UNIQUE (aparentemente redundante, já que subcategoria_id já é
    -- PRIMARY KEY sozinho) existe só para servir de ALVO da FK composta que
    -- `profissionais` vai declarar na Seção 3. É o truque padrão do Postgres
    -- para forçar coerência pai-filho: uma FK composta (subcategoria_id,
    -- categoria_id) só pode apontar para uma UNIQUE/PK que tenha essas duas
    -- colunas juntas.
    CONSTRAINT uq_subcategorias_id_categoria UNIQUE (subcategoria_id, categoria_id)
);

CREATE INDEX IF NOT EXISTS idx_subcategorias_categoria_id ON subcategorias (categoria_id);


-- ============================================================================
--  SEÇÃO 3 - COLUNAS NOVAS EM profissionais + FK COMPOSTA
--
--  Por que FK composta (subcategoria_id, categoria_id) e não só uma FK
--  simples em subcategoria_id?
--
--  Uma FK simples garantiria só que `subcategoria_id` existe em algum lugar
--  de `subcategorias` -- mas NADA impediria salvar `categoria_id` = "Beleza
--  e Bem-Estar" junto com `subcategoria_id` = "Pedreiro" (que pertence a
--  "Manutenção e Reforma"). A FK composta, apontando para a UNIQUE
--  (subcategoria_id, categoria_id) da Seção 2, faz o Postgres RECUSAR esse
--  par incoerente automaticamente -- é a "integridade dos dados no banco"
--  pedida para este recurso, sem precisar de trigger nem de validação
--  redundante no backend.
-- ============================================================================

ALTER TABLE profissionais
    ADD COLUMN IF NOT EXISTS categoria_id    INT REFERENCES categorias (categoria_id),
    ADD COLUMN IF NOT EXISTS subcategoria_id INT;

ALTER TABLE profissionais
    ADD CONSTRAINT fk_profissionais_subcategoria_categoria
    FOREIGN KEY (subcategoria_id, categoria_id)
    REFERENCES subcategorias (subcategoria_id, categoria_id);

-- Mesma regra de "ou tem os dois, ou não tem nenhum" já usada para
-- latitude/longitude (chk_prof_coords_completas, ver 01_schema_2.sql).
ALTER TABLE profissionais
    ADD CONSTRAINT chk_prof_categoria_completa CHECK (
        (categoria_id IS NULL AND subcategoria_id IS NULL)
        OR
        (categoria_id IS NOT NULL AND subcategoria_id IS NOT NULL)
    );

CREATE INDEX IF NOT EXISTS idx_profissionais_categoria_id    ON profissionais (categoria_id)    WHERE categoria_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profissionais_subcategoria_id ON profissionais (subcategoria_id) WHERE subcategoria_id IS NOT NULL;

COMMENT ON COLUMN profissionais.categoria_id IS
    'Categoria (pai) de atuação, escolhida de uma lista fechada -- ver tabela categorias. Substitui profissao/categoria_atuacao (texto livre) a partir da migração 09.';
COMMENT ON COLUMN profissionais.subcategoria_id IS
    'Subcategoria (filho) de atuação, escolhida de uma lista fechada FILTRADA pela categoria_id -- ver tabela subcategorias. A FK composta garante que o par (subcategoria_id, categoria_id) seja sempre coerente.';

COMMENT ON COLUMN profissionais.profissao IS
    'DEPRECADO desde a migração 09 -- era texto livre digitado por PF. O cadastro agora usa categoria_id/subcategoria_id. Coluna mantida só por compatibilidade com cadastros antigos, nunca mais escrita pelo backend.';
COMMENT ON COLUMN profissionais.categoria_atuacao IS
    'DEPRECADO desde a migração 09 -- era texto livre digitado por PJ. O cadastro agora usa categoria_id/subcategoria_id. Coluna mantida só por compatibilidade com cadastros antigos, nunca mais escrita pelo backend.';


-- ============================================================================
--  SEÇÃO 4 - SEED: as 7 categorias e suas subcategorias
-- ============================================================================

INSERT INTO categorias (nome) VALUES
    ('Manutenção e Reforma'),
    ('Logística e Transporte'),
    ('Beleza e Bem-Estar'),
    ('Tecnologia e Serviços Digitais'),
    ('Educação e Consultoria'),
    ('Alimentação e Eventos'),
    ('Serviços Gerais e Pet')
ON CONFLICT (nome) DO NOTHING;

INSERT INTO subcategorias (categoria_id, nome)
SELECT c.categoria_id, s.nome
FROM categorias c
JOIN (VALUES
    ('Manutenção e Reforma', 'Pedreiro'),
    ('Manutenção e Reforma', 'Pintor'),
    ('Manutenção e Reforma', 'Encanador'),
    ('Manutenção e Reforma', 'Eletricista'),
    ('Manutenção e Reforma', 'Vidraceiro'),
    ('Manutenção e Reforma', 'Marceneiro'),
    ('Manutenção e Reforma', 'Gesseiro'),
    ('Manutenção e Reforma', 'Serralheiro'),
    ('Manutenção e Reforma', 'Telhadista'),
    ('Manutenção e Reforma', 'Impermeabilizador'),

    ('Logística e Transporte', 'Frete'),
    ('Logística e Transporte', 'Mudanças'),
    ('Logística e Transporte', 'Motoboy'),
    ('Logística e Transporte', 'Entrega de Pequenos Volumes'),
    ('Logística e Transporte', 'Taxista'),
    ('Logística e Transporte', 'Motorista de Aplicativo'),

    ('Beleza e Bem-Estar', 'Cabeleireiro'),
    ('Beleza e Bem-Estar', 'Barbeiro'),
    ('Beleza e Bem-Estar', 'Manicure/Pedicure'),
    ('Beleza e Bem-Estar', 'Design de Sobrancelhas'),
    ('Beleza e Bem-Estar', 'Maquiadora'),
    ('Beleza e Bem-Estar', 'Depiladora'),
    ('Beleza e Bem-Estar', 'Massoterapeuta'),
    ('Beleza e Bem-Estar', 'Esteticista'),
    ('Beleza e Bem-Estar', 'Personal Trainer'),

    ('Tecnologia e Serviços Digitais', 'Desenvolvedor'),
    ('Tecnologia e Serviços Digitais', 'Designer Gráfico'),
    ('Tecnologia e Serviços Digitais', 'Social Media'),
    ('Tecnologia e Serviços Digitais', 'Gestor de Tráfego'),
    ('Tecnologia e Serviços Digitais', 'Redator/Copywriter'),
    ('Tecnologia e Serviços Digitais', 'Edição de Vídeo'),
    ('Tecnologia e Serviços Digitais', 'Criação de Sites'),
    ('Tecnologia e Serviços Digitais', 'Suporte em TI'),
    ('Tecnologia e Serviços Digitais', 'Manutenção de Celulares'),

    ('Educação e Consultoria', 'Professor Particular'),
    ('Educação e Consultoria', 'Consultor Financeiro'),
    ('Educação e Consultoria', 'Coach'),
    ('Educação e Consultoria', 'Contador'),
    ('Educação e Consultoria', 'Advogado'),
    ('Educação e Consultoria', 'Arquiteto'),
    ('Educação e Consultoria', 'Tradutor'),

    ('Alimentação e Eventos', 'Fotógrafo'),
    ('Alimentação e Eventos', 'Confeiteira'),
    ('Alimentação e Eventos', 'Buffet/Cozinheiro'),
    ('Alimentação e Eventos', 'Cerimonialista'),
    ('Alimentação e Eventos', 'Garçom/Copeira'),
    ('Alimentação e Eventos', 'DJ/Músico'),

    ('Serviços Gerais e Pet', 'Pet Sitter'),
    ('Serviços Gerais e Pet', 'Adestrador'),
    ('Serviços Gerais e Pet', 'Artesão'),
    ('Serviços Gerais e Pet', 'Costureira'),
    ('Serviços Gerais e Pet', 'Diarista'),
    ('Serviços Gerais e Pet', 'Passadeira'),
    ('Serviços Gerais e Pet', 'Lavagem de Estofados'),
    ('Serviços Gerais e Pet', 'Chaveiro'),
    ('Serviços Gerais e Pet', 'Jardineiro'),
    ('Serviços Gerais e Pet', 'Piscineiro')
) AS s(categoria_nome, nome) ON s.categoria_nome = c.nome
ON CONFLICT (categoria_id, nome) DO NOTHING;


-- ============================================================================
--  SEÇÃO 5 - VERIFICAÇÃO
-- ============================================================================

DO $$
DECLARE
    total_categorias INT;
    total_subcategorias INT;
BEGIN
    SELECT COUNT(*) INTO total_categorias FROM categorias;
    SELECT COUNT(*) INTO total_subcategorias FROM subcategorias;

    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 09 aplicada com sucesso.';
    RAISE NOTICE ' Categorias cadastradas: %', total_categorias;
    RAISE NOTICE ' Subcategorias cadastradas: %', total_subcategorias;
    RAISE NOTICE ' Colunas novas: profissionais.categoria_id, profissionais.subcategoria_id';
    RAISE NOTICE ' profissao/categoria_atuacao seguem no banco, mas deprecadas (ver COMMENT).';
    RAISE NOTICE '---------------------------------------------';
END $$;
