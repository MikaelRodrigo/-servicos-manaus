-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Certidão de antecedentes criminais do profissional"
--
--  Pedido do usuário: "deixe um campo reservado para o prestador de
--  serviço [...] inserir uma certidão negativa de antecedentes criminais,
--  seu desafio também é validar esse documento se está correto e legítimo."
--
--  IMPORTANTE -- leia antes de rodar em produção:
--  Não existe API pública para confirmar a AUTENTICIDADE jurídica de uma
--  certidão (isso exige o código de verificação que só o site do órgão
--  emissor confere). O que este esquema sustenta é uma checagem
--  automática BÁSICA (formato do arquivo, palavras-chave esperadas,
--  nome/CPF do profissional aparecem no texto) seguida de APROVAÇÃO
--  MANUAL por um admin -- ver backend/src/services/checagem-documento.ts
--  e as rotas /profissionais/admin/documentos-antecedentes/*. A aprovação
--  NUNCA acontece sozinha (só a rejeição automática, para casos óbvios).
--
--  O que esta migração muda:
--
--    1) `antecedentes_verificados` -- coluna NOVA em `profissionais`
--       (BOOLEAN, padrão FALSE). Só vira TRUE quando um admin aprova um
--       documento (ver POST /profissionais/admin/documentos-antecedentes/
--       :id/aprovar). Gate usado em `buscarProximos` (mapa/busca) --
--       DIFERENTE de `telefone_verificado` (migração 17), que bloqueia
--       LOGIN: aqui o profissional consegue logar e editar o perfil
--       normalmente, só não aparece pros clientes no mapa enquanto
--       pendente.
--
--       IMPORTANTE: contas que já existiam ANTES desta migração são
--       "aposentadas" como já verificadas (mesmo espírito da migração
--       17) -- senão todo profissional de teste já cadastrado sumiria do
--       mapa da noite pro dia, sem nunca ter passado por este fluxo.
--
--    2) `documentos_antecedentes` -- tabela NOVA, uma linha por ENVIO
--       (reenvio depois de rejeição gera outra linha, histórico
--       completo). `chave_s3` guarda só a CHAVE do objeto no bucket, NÃO
--       uma URL pública -- diferente de toda foto/portfólio do app até
--       aqui: uma certidão de antecedentes criminais é um documento
--       sensível (nome completo, CPF, situação criminal), e não deve
--       ficar acessível por link direto pra qualquer um. O arquivo só é
--       lido de volta via rota autenticada, que busca do S3 no servidor e
--       transmite os bytes -- nunca por URL pública gravada no banco (ver
--       `services/armazenamento-privado.ts`).
--
--  Rodar como: psql "sua-connection-string-neon" -f 18_certidao_antecedentes_criminais.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - GATE DE VISIBILIDADE NO MAPA
-- ============================================================================

ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS antecedentes_verificados BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN profissionais.antecedentes_verificados IS
    'TRUE só depois que um admin APROVA um documento em documentos_antecedentes (nunca automático). Filtra buscarProximos (mapa) -- NÃO bloqueia login/edição de perfil, diferente de telefone_verificado (migração 17). Contas criadas ANTES desta migração foram marcadas TRUE de propósito (grandfathering).';

UPDATE profissionais SET antecedentes_verificados = TRUE WHERE antecedentes_verificados = FALSE;


-- ============================================================================
--  SEÇÃO 2 - DOCUMENTOS ENVIADOS (um por tentativa de envio)
-- ============================================================================

CREATE TABLE documentos_antecedentes (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profissional_id             UUID NOT NULL REFERENCES profissionais(profissional_id) ON DELETE CASCADE ON UPDATE CASCADE,

    -- Chave do objeto no bucket S3-compatible (ex.: "antecedentes/uuid.pdf")
    -- -- NUNCA uma URL pública. Ver comentário no topo do arquivo.
    chave_s3                    TEXT NOT NULL,
    tipo_mime                   TEXT NOT NULL,

    status                      TEXT NOT NULL DEFAULT 'PENDENTE'
                                   CHECK (status IN ('PENDENTE', 'APROVADO', 'REJEITADO')),

    -- Resultado da checagem automática (ver checagem-documento.ts) --
    -- puramente informativo pro admin decidir mais rápido, nunca aprova
    -- sozinho. `NULL` em nome/cpf_encontrado significa "não aplicável"
    -- (documento é imagem, sem extração de texto nesta etapa -- ou
    -- profissional é PJ, sem CPF individual cadastrado).
    palavras_chave_encontradas  TEXT[] NOT NULL DEFAULT '{}',
    nome_encontrado             BOOLEAN,
    cpf_encontrado              BOOLEAN,

    -- Preenchido só quando a REJEIÇÃO foi automática (nenhuma palavra-chave
    -- encontrada -- documento claramente não é uma certidão) OU quando um
    -- admin rejeita manualmente.
    motivo_rejeicao             TEXT,

    revisado_por                UUID REFERENCES admins(admin_id),
    revisado_em                 TIMESTAMPTZ,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Toda leitura do profissional é "meus documentos, do mais recente pro mais
-- antigo" -- índice composto cobre exatamente esse acesso.
CREATE INDEX idx_documentos_antecedentes_profissional
    ON documentos_antecedentes (profissional_id, created_at DESC);

-- Fila do admin é sempre "quem está PENDENTE" -- índice parcial (só indexa
-- as linhas pendentes, que são a minoria) é mais leve que um índice
-- completo por status.
CREATE INDEX idx_documentos_antecedentes_pendentes
    ON documentos_antecedentes (created_at)
    WHERE status = 'PENDENTE';

COMMENT ON TABLE documentos_antecedentes IS
    'Certidões de antecedentes criminais enviadas por profissionais (migração 18) -- uma linha por envio/reenvio. chave_s3 NUNCA é pública (ver comentário no topo do arquivo). Aprovação SEMPRE manual (admin); só a rejeição por checagem automática óbvia acontece sozinha.';


-- ============================================================================
--  SEÇÃO 3 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 18 aplicada com sucesso.';
    RAISE NOTICE ' Coluna nova: profissionais.antecedentes_verificados (contas antigas = TRUE).';
    RAISE NOTICE ' Tabela nova: documentos_antecedentes (chave S3 PRIVADA, nunca URL publica).';
    RAISE NOTICE ' PROXIMO PASSO: backend (upload + checagem + rotas admin) + Flutter.';
    RAISE NOTICE '---------------------------------------------';
END $$;
