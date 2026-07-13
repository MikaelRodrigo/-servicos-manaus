-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Perfil do Cliente + Endereço de Atuação" - foto/endereço do cliente
--  e endereço de atuação padrão do profissional
--
--  Rodar como: psql "sua-connection-string-neon" -f 06_perfil_cliente_endereco.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - PERFIL DO CLIENTE (foto + endereço fixo)
--
--  Até aqui `clientes` não tinha nem foto de perfil nem endereço em texto --
--  só `latitude`/`longitude` (usadas para localizar o cliente no mapa quando
--  ele abre um serviço). `endereco` é o texto livre digitado pelo cliente
--  ("Rua X, 123, bairro Y") -- não tenta geocodificar nem substituir
--  latitude/longitude, é só o dado legível por humano que aparece no perfil.
--
--  Mesma lógica de `url_foto_perfil` já usada em `profissionais` (migração
--  04): nasce NULLABLE, `null` = "ainda não preencheu".
-- ============================================================================

ALTER TABLE clientes ADD COLUMN IF NOT EXISTS url_foto_perfil TEXT;
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS endereco TEXT;

COMMENT ON COLUMN clientes.url_foto_perfil IS
    'Foto pública de perfil do cliente. Mesma convenção de profissionais.url_foto_perfil.';
COMMENT ON COLUMN clientes.endereco IS
    'Endereço fixo do cliente, em texto livre (não geocodificado). Preenchido/editado pelo próprio cliente no perfil.';


-- ============================================================================
--  SEÇÃO 2 - ENDEREÇO DE ATUAÇÃO PADRÃO DO PROFISSIONAL
--
--  O profissional já tem `latitude`/`longitude` (usadas para a busca por
--  proximidade via PostGIS), mas nenhum texto legível que diga pra um
--  cliente novo, em palavras, onde ele fica ("Atua na zona Centro-Sul,
--  próximo ao Shopping X"). `endereco_atuacao` é exatamente isso: texto
--  livre, opcional, só para dar contexto ao cliente -- não alimenta o
--  cálculo de distância nem substitui latitude/longitude.
-- ============================================================================

ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS endereco_atuacao TEXT;

COMMENT ON COLUMN profissionais.endereco_atuacao IS
    'Endereço/região de atuação padrão do profissional, em texto livre. Só informativo -- não é usado no cálculo de distância (isso continua vindo de latitude/longitude).';


-- ============================================================================
--  SEÇÃO 3 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 06 aplicada com sucesso.';
    RAISE NOTICE ' Colunas novas: clientes.url_foto_perfil, clientes.endereco, profissionais.endereco_atuacao';
    RAISE NOTICE '---------------------------------------------';
END $$;
