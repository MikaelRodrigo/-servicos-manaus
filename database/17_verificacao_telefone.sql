-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Verificação de telefone por SMS"
--
--  Pedido do usuário: "preciso que seja enviado um SMS para confirmar o
--  número telefônico do usuário quando se cadastrar no meu app."
--
--  O que esta migração muda:
--
--    1) `telefone_verificado` -- coluna NOVA em `clientes` E `profissionais`
--       (BOOLEAN, padrão FALSE). A partir de agora, toda conta CRIADA DAQUI
--       PRA FRENTE nasce com `telefone_verificado = FALSE` e só consegue
--       fazer login (POST /auth/login) depois de confirmar um código
--       recebido por SMS -- ver `ErroTelefoneNaoVerificado` em
--       backend/src/utils/validacao.ts e o bloqueio dentro da rota de login
--       em backend/src/routes/auth.routes.ts.
--
--       IMPORTANTE: contas que já existiam ANTES desta migração são
--       "aposentadas" como já verificadas (ver UPDATE na Seção 1, abaixo) --
--       senão toda conta de teste que você já usa no dia a dia ficaria
--       bloqueada no próximo login, sem nunca ter passado por este fluxo.
--       Só cadastros NOVOS, feitos depois de rodar esta migração, exigem o
--       código SMS.
--
--       `admins` (migração 15) fica DE FORA -- não tem coluna `contato`
--       nem `telefone_verificado`: conta de admin é criada por INSERT
--       manual, não por autocadastro, então a verificação por SMS não se
--       aplica a ela (ver a checagem "papel !== 'admin'" na rota de login).
--
--    2) `codigos_verificacao_telefone` -- tabela NOVA. Um código de 6
--       dígitos por linha, com expiração e contador de tentativas. Guarda
--       só o HASH do código (SHA-256, ver `utils/sms.ts`/
--       `verificacao-telefone.repository.ts` no backend) -- nunca o código
--       em texto puro, mesmo espírito de nunca guardar senha em texto puro.
--
--       SEM foreign key para `clientes`/`profissionais`: `usuario_id`
--       aponta para UMA das duas tabelas dependendo de `papel` (o mesmo
--       dilema de `transacoes.cliente_id`/`profissional_id`, migração 15 --
--       só que aqui é UMA coluna só servindo as duas tabelas, então uma FK
--       de verdade não é possível: o Postgres exige que uma FK aponte para
--       uma única tabela). A garantia de integridade fica por conta do
--       código da aplicação (a rota só insere depois de confirmar que o
--       `usuario_id` existe na tabela certa).
--
--  Rodar como: psql "sua-connection-string-neon" -f 17_verificacao_telefone.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - TELEFONE VERIFICADO (clientes e profissionais)
-- ============================================================================

ALTER TABLE clientes ADD COLUMN IF NOT EXISTS telefone_verificado BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS telefone_verificado BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN clientes.telefone_verificado IS
    'TRUE depois que a pessoa confirma o código SMS enviado no cadastro (ver codigos_verificacao_telefone). Contas criadas ANTES desta migração foram marcadas TRUE de propósito (grandfathering) -- ver UPDATE logo abaixo.';
COMMENT ON COLUMN profissionais.telefone_verificado IS
    'Mesma ideia de clientes.telefone_verificado -- ver comentário lá.';

-- Aposenta as contas que já existiam: elas nunca passaram por este fluxo
-- (a coluna não existia ainda), então não é justo bloqueá-las no próximo
-- login. Só quem se cadastrar A PARTIR DE AGORA nasce com FALSE de verdade.
UPDATE clientes SET telefone_verificado = TRUE WHERE telefone_verificado = FALSE;
UPDATE profissionais SET telefone_verificado = TRUE WHERE telefone_verificado = FALSE;


-- ============================================================================
--  SEÇÃO 2 - CÓDIGOS DE VERIFICAÇÃO (um por SMS enviado)
-- ============================================================================

CREATE TABLE codigos_verificacao_telefone (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 'cliente' ou 'profissional' -- diz em QUAL tabela `usuario_id` vive.
    -- Sem FK real possível (ver comentário no topo do arquivo).
    papel           TEXT NOT NULL CHECK (papel IN ('cliente', 'profissional')),
    usuario_id      UUID NOT NULL,

    -- SHA-256 do código de 6 dígitos, nunca o código em texto puro (ver
    -- utils/sms.ts no backend). Comparação rápida o bastante para um código
    -- de vida curta -- não precisa do custo de bcrypt aqui.
    codigo_hash     TEXT NOT NULL,

    -- Quantas vezes alguém tentou confirmar ESTE código e errou. Barra
    -- força-bruta: acima de um teto (ver MAX_TENTATIVAS_CODIGO no
    -- repository), o código vira inválido mesmo dentro da validade.
    tentativas      INT NOT NULL DEFAULT 0,

    expira_em       TIMESTAMPTZ NOT NULL,
    -- NULL enquanto não confirmado. Preenchido no momento em que o código
    -- é aceito -- um código já usado nunca pode ser reaproveitado, mesmo
    -- que ainda esteja dentro da validade.
    usado_em        TIMESTAMPTZ,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Toda leitura é "o código mais recente deste usuário" (WHERE papel = $1
-- AND usuario_id = $2 ORDER BY created_at DESC LIMIT 1) -- índice composto
-- cobre exatamente esse acesso, já na ordem certa.
CREATE INDEX idx_codigos_verificacao_usuario
    ON codigos_verificacao_telefone (papel, usuario_id, created_at DESC);

COMMENT ON TABLE codigos_verificacao_telefone IS
    'Códigos de verificação de telefone por SMS (migração 17) -- um cadastro/reenvio gera uma linha nova, nunca sobrescreve a anterior (histórico completo fica no banco). Ver services/sms.ts (modo simulado/real) e repositories/verificacao-telefone.repository.ts.';


-- ============================================================================
--  SEÇÃO 3 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 17 aplicada com sucesso.';
    RAISE NOTICE ' Coluna nova: clientes.telefone_verificado (contas antigas = TRUE).';
    RAISE NOTICE ' Coluna nova: profissionais.telefone_verificado (contas antigas = TRUE).';
    RAISE NOTICE ' Tabela nova: codigos_verificacao_telefone.';
    RAISE NOTICE ' PROXIMO PASSO: backend (services/sms.ts + rotas) + Flutter';
    RAISE NOTICE ' (tela de confirmacao de codigo apos cadastro/login).';
    RAISE NOTICE '---------------------------------------------';
END $$;
