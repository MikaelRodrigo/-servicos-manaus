-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "CEP define localização do profissional no mapa"
--
--  Rodar como: psql "sua-connection-string-neon" -f 08_cep_profissional.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - COLUNA cep + MUDANÇA DE SIGNIFICADO DE endereco_atuacao
--
--  Até a migração 06, `endereco_atuacao` era texto livre digitado pelo
--  profissional, só informativo, sem nenhuma ligação com `latitude`/
--  `longitude`. A partir de agora, o fluxo muda: o profissional digita o
--  CEP (aqui, `cep`), o backend consulta um serviço de geocodificação
--  (BrasilAPI) e grava, de UMA VEZ SÓ:
--    - `cep`               -> o CEP bruto informado (só dígitos, 8 caracteres)
--    - `latitude`/`longitude` -> a coordenada resolvida a partir do CEP,
--                                que passa a alimentar a busca por
--                                proximidade (ST_DWithin, ver
--                                profissionais.repository.ts)
--    - `endereco_atuacao`  -> texto formatado (rua/bairro/cidade-UF)
--                                devolvido pela consulta, agora AUTOMÁTICO
--                                em vez de digitado à mão
--
--  Por que reaproveitar a coluna `endereco_atuacao` em vez de criar uma
--  nova? Porque o CONTRATO com o app (nome do campo no JSON, `PATCH
--  /profissionais/me` -> RETURNING) continua o mesmo -- só a ORIGEM do
--  valor muda (de "digitado pelo usuário" para "derivado do CEP"). Menos
--  uma migração de dado, menos um campo pra manter sincronizado.
--
--  IMPORTANTE: sem esta migração, TODO profissional cadastrado até hoje
--  tem `latitude`/`longitude` NULL (a tela de cadastro nunca captura
--  coordenadas -- ver PROGRESSO.md), então NINGUÉM aparece na busca por
--  proximidade do mapa. Esta etapa não é só um "extra" -- ela é o que
--  finalmente dá a um profissional real uma forma de aparecer no mapa.
-- ============================================================================

ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS cep TEXT;

COMMENT ON COLUMN profissionais.cep IS
    'CEP bruto (8 dígitos) informado pelo profissional -- fonte de latitude/longitude/endereco_atuacao via geocodificação (BrasilAPI). Nunca editado diretamente pelo app, só através do fluxo de "atualizar CEP".';

COMMENT ON COLUMN profissionais.endereco_atuacao IS
    'Endereço/região de atuação do profissional. Desde a migração 08, é derivado automaticamente do CEP (rua/bairro/cidade-UF), não mais texto livre digitado. Só informativo -- quem alimenta a busca por proximidade é latitude/longitude.';


-- ============================================================================
--  SEÇÃO 2 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 08 aplicada com sucesso.';
    RAISE NOTICE ' Coluna nova: profissionais.cep';
    RAISE NOTICE ' endereco_atuacao passa a ser derivado do CEP (ver comentario da coluna).';
    RAISE NOTICE '---------------------------------------------';
END $$;
