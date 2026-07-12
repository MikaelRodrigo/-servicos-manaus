-- ============================================================================
--  SEED DE TESTE - Coordenadas reais de Manaus/AM
--  Rodar DEPOIS do 01_schema.sql:
--    psql -U postgres -d servicos_manaus -f 02_seed_teste.sql
-- ============================================================================

-- ---------------------------------------------------------------------------
--  1) Um profissional PF (eletricista, no Centro de Manaus)
-- ---------------------------------------------------------------------------
INSERT INTO profissionais (
    tipo_pessoa, email, contato, latitude, longitude,
    nome, profissao, data_nascimento, cpf, identidade
) VALUES (
    'PF', 'joao.eletricista@email.com', '5592988887777',
    -3.130130, -60.023400,               -- Teatro Amazonas, Centro
    'João da Silva', 'Eletricista', '1990-05-14', '12345678901', '1234567-8'
);

-- ---------------------------------------------------------------------------
--  2) Um profissional PJ (empresa de ar-condicionado, na Ponta Negra)
-- ---------------------------------------------------------------------------
INSERT INTO profissionais (
    tipo_pessoa, email, contato, latitude, longitude,
    razao_social, categoria_atuacao, data_criacao, cnpj
) VALUES (
    'PJ', 'contato@refrigeracaoam.com.br', '559233334444',
    -3.081940, -60.098610,               -- Ponta Negra
    'Refrigeração Amazonas LTDA', 'Climatização', '2015-03-01', '12345678000199'
);

-- ---------------------------------------------------------------------------
--  3) Um cliente PF (Adrianópolis)
-- ---------------------------------------------------------------------------
INSERT INTO clientes (
    tipo_pessoa, email, contato, latitude, longitude, nome, cpf
) VALUES (
    'PF', 'maria@email.com', '5592999998888',
    -3.101940, -60.012500,
    'Maria Souza', '98765432100'
);


-- ============================================================================
--  TESTE A - As constraints estão vivas?
--  Cada bloco abaixo DEVE dar erro. Descomente um de cada vez para conferir.
-- ============================================================================

-- (A1) PJ com CPF preenchido -> viola chk_prof_coerencia_tipo
-- INSERT INTO profissionais (tipo_pessoa, email, contato, razao_social, cnpj, cpf)
-- VALUES ('PJ', 'x@x.com', '5592', 'Empresa X', '99999999000199', '11122233344');

-- (A2) Nota 6 estrelas -> viola chk_avalprof_tecnico
-- (rode depois de ter um serviço concluído)

-- (A3) Latitude 200 -> viola chk_prof_latitude
-- INSERT INTO profissionais (tipo_pessoa, email, contato, latitude, longitude, nome, cpf, data_nascimento)
-- VALUES ('PF', 'y@y.com', '5592', 200, -60, 'Teste', '11122233355', '1990-01-01');


-- ============================================================================
--  TESTE B - O índice espacial funciona?
--  "Quais profissionais estão a até 5 km do Teatro Amazonas?"
--
--  ST_DWithin com o tipo GEOGRAPHY recebe a distância em METROS.
--  (Se fosse GEOMETRY, seria em graus -- outra pegadinha clássica.)
-- ============================================================================

SELECT
    COALESCE(nome, razao_social) AS profissional,
    COALESCE(profissao, categoria_atuacao) AS atuacao,
    ROUND(
        ST_Distance(
            localizacao,
            ST_SetSRID(ST_MakePoint(-60.023400, -3.130130), 4326)::geography
        )::numeric
    , 0) AS distancia_metros
FROM profissionais
WHERE ST_DWithin(
    localizacao,
    ST_SetSRID(ST_MakePoint(-60.023400, -3.130130), 4326)::geography,
    5000                                  -- raio: 5.000 metros
)
ORDER BY distancia_metros ASC;

-- Esperado: só o João aparece. A empresa da Ponta Negra fica a ~11 km.
-- Troque 5000 por 15000 e ela aparece.


-- ============================================================================
--  TESTE C - O índice está sendo USADO mesmo?
--  Procure por "Index Scan using idx_profissionais_localizacao" na saída.
--  (Com 2 linhas na tabela o Postgres pode preferir Seq Scan -- é normal,
--   ele só usa índice quando compensa. Vale conferir depois do seed grande.)
-- ============================================================================

EXPLAIN ANALYZE
SELECT profissional_id FROM profissionais
WHERE ST_DWithin(
    localizacao,
    ST_SetSRID(ST_MakePoint(-60.023400, -3.130130), 4326)::geography,
    5000
);
