-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Perfil do Profissional" - descrição + foto pública de perfil
--
--  Rodar como: psql "sua-connection-string-neon" -f 04_perfil_profissional.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - NOVAS COLUNAS
--
--  Por que uma coluna NOVA (`url_foto_perfil`) e não reaproveitar
--  `url_foto_com_rg` ou `url_foto`?
--
--  - `url_foto_com_rg` (só PF) é a selfie segurando o documento -- DADO
--    SENSÍVEL sob a LGPD, usado uma vez para verificar o cadastro. Nunca,
--    em hipótese nenhuma, pode virar a foto pública de perfil.
--  - `url_foto` (só PJ, no schema original) nasceu pensada como "logo ou
--    fachada da empresa" -- mais estreita que "foto de perfil".
--  - `url_foto_perfil` é NOVA, existe para os DOIS tipos (PF e PJ), e é
--    especificamente a foto que aparece na busca/mapa/perfil público.
--
--  `descricao` é o "sobre mim" que o profissional escreve -- não existia
--  nenhuma coluna parecida no schema original.
--
--  As duas nascem NULLABLE: ninguém tem valor ainda (não existe tela de
--  editar perfil construída até este ponto), e nada no fluxo atual quebra
--  por elas estarem vazias -- a tela de perfil no app trata `null` como
--  "profissional ainda não preencheu".
-- ============================================================================

ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS descricao TEXT;
ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS url_foto_perfil TEXT;

COMMENT ON COLUMN profissionais.descricao IS
    'Texto livre "sobre mim" do profissional. Público -- aparece no perfil.';
COMMENT ON COLUMN profissionais.url_foto_perfil IS
    'Foto pública de perfil (PF ou PJ). NUNCA confundir com url_foto_com_rg (privada, verificação de cadastro).';


-- ============================================================================
--  SEÇÃO 2 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 04 aplicada com sucesso.';
    RAISE NOTICE ' Colunas novas: profissionais.descricao, profissionais.url_foto_perfil';
    RAISE NOTICE '---------------------------------------------';
END $$;
