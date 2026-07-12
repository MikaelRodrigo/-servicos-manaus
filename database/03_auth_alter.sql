-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa 4 - Autenticação: adiciona senha_hash a profissionais e clientes
--
--  Rodar como: psql "<sua-connection-string-neon>" -f 03_auth_alter.sql
--  (ou colar o conteúdo inteiro no Query Tool do pgAdmin)
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - NOVA COLUNA: senha_hash
--
--  Nunca se guarda a senha em texto puro. O que fica no banco é o HASH
--  (bcrypt), calculado com "custo" (rounds) alto o suficiente para que
--  testar todas as senhas possíveis por força bruta seja inviável.
--
--  A coluna nasce NULLABLE porque as linhas do seed (Etapa 1) já existem
--  e não têm senha. Preenchemos elas na Seção 2 e SÓ DEPOIS travamos
--  com NOT NULL na Seção 3 -- nessa ordem, ou o ALTER da Seção 3 falha.
-- ============================================================================

ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS senha_hash TEXT;
ALTER TABLE clientes      ADD COLUMN IF NOT EXISTS senha_hash TEXT;


-- ============================================================================
--  SEÇÃO 2 - BACKFILL: senha de teste para quem já existe no seed
--
--  pgcrypto (já habilitada na Etapa 1) tem crypt()/gen_salt('bf', ...),
--  que gera um hash BCRYPT de verdade -- o mesmo formato ($2a$/$2b$) que a
--  lib `bcryptjs` do Node lê e verifica. Ou seja: o hash gerado aqui dentro
--  do Postgres funciona perfeitamente no login feito pelo backend.
--
--  Senha de teste para TODOS os registros do seed: "senha123"
--  (Isto é só para os dados de teste. Nunca faça backfill assim em produção.)
-- ============================================================================

UPDATE profissionais
   SET senha_hash = crypt('senha123', gen_salt('bf', 10))
 WHERE senha_hash IS NULL;

UPDATE clientes
   SET senha_hash = crypt('senha123', gen_salt('bf', 10))
 WHERE senha_hash IS NULL;


-- ============================================================================
--  SEÇÃO 3 - TRAVAR A COLUNA
--
--  A partir de agora, todo INSERT novo (via nosso backend, na Etapa 4)
--  é OBRIGADO a mandar um senha_hash. Ninguém entra no app sem senha.
-- ============================================================================

ALTER TABLE profissionais ALTER COLUMN senha_hash SET NOT NULL;
ALTER TABLE clientes      ALTER COLUMN senha_hash SET NOT NULL;

COMMENT ON COLUMN profissionais.senha_hash IS
    'Hash BCRYPT da senha. NUNCA guardar a senha em texto puro, nunca devolver esta coluna em nenhum JSON.';
COMMENT ON COLUMN clientes.senha_hash IS
    'Hash BCRYPT da senha. NUNCA guardar a senha em texto puro, nunca devolver esta coluna em nenhum JSON.';


-- ============================================================================
--  SEÇÃO 4 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 03 aplicada com sucesso.';
    RAISE NOTICE ' Login de teste (dados do seed): senha "senha123"';
    RAISE NOTICE '---------------------------------------------';
END $$;
