-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Remoção do Pagar.me + Modelo de Intermediação com Pix Próprio"
--
--  Pedido explícito do usuário (duas mensagens, resumidas aqui):
--
--    1) Remover TODA dependência/integração/lógica do Pagar.me.
--
--    2) O fluxo de dinheiro muda por completo: o profissional avalia o
--       serviço PRESENCIALMENTE e insere um valor no app; o cliente
--       confirma (ou recusa) esse valor; ao confirmar, uma chave de
--       pagamento (Pix/Boleto) é gerada NO CELULAR DO PROFISSIONAL,
--       associada à CONTA BANCÁRIA DELE (não da plataforma) -- o cliente
--       paga direto para o profissional. Esse valor fica "retido na
--       fonte" (congelado, visível como tal para o profissional) até o
--       CLIENTE confirmar o término do serviço, ponto em que 8,9% é
--       descontado para a conta da plataforma (mesmo banco do
--       profissional) e o restante já está, na prática, disponível para
--       ele (nunca "saiu" da conta dele). A geração/retenção/desconto de
--       verdade depende de uma API PIX PRÓPRIA que o usuário vai
--       construir separadamente ("Eu criarei uma api, integrada a minha
--       conta pix jurídica que aceita alto fluxos") -- ainda não existe
--       hoje, então esta migração modela o BANCO para esse fluxo, e o
--       backend (próxima etapa) isola a chamada a essa API futura atrás
--       de uma interface clara, com um modo simulado para desenvolvimento.
--
--  ESCOPO: derruba tudo que era específico do Pagar.me (tabelas
--  `retencoes_escrow` e `eventos_webhook_pagamento`, colunas
--  `id_pedido_gateway`/`id_cobranca_gateway`/`id_transacao_gateway` em
--  `transacoes`, `id_recebedor_gateway` em `profissionais`) e recria
--  `transacoes` do zero para o novo fluxo (proposta -> confirmação ->
--  pagamento retido -> liberação). `disputas_transacao`, `creditos_usuario`
--  e `notas_fiscais` são preservadas (não dependiam do Pagar.me), só
--  reconectadas à nova `transacoes`. Cria também `admins` + o papel
--  `admin` no JWT (Etapa 2 do pedido: "crie a conta do adm para
--  gerenciar" -- necessário para marcar a comissão como conciliada e
--  para o futuro dashboard).
--
--  Por que DROP TABLE (não uma sequência de ALTER)? `transacoes` não tem
--  nenhum dado real em produção (o módulo nunca chegou a ter UI no
--  Flutter, confirmado antes desta migração) -- reescrever do zero é mais
--  simples e mais seguro que uma cadeia de ALTER/DROP COLUMN para uma
--  reformulação desse tamanho. `DROP TABLE ... CASCADE` deixa
--  `disputas_transacao`/`creditos_usuario`/`notas_fiscais` INTACTAS (só
--  derruba a FK delas para `transacoes`, que a Seção 5 recria) -- não
--  apaga as tabelas em si.
--
--  Rodar como: psql "sua-connection-string-neon" -f 15_remocao_pagarme_modelo_intermediacao.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - DERRUBAR TUDO QUE ERA ESPECÍFICO DO PAGAR.ME
-- ============================================================================

-- Log de webhook do gateway -- sem gateway, sem webhook.
DROP TABLE IF EXISTS eventos_webhook_pagamento CASCADE;

-- "Escrow" era o dinheiro retido pelo GATEWAY. No novo modelo, quem retém é
-- a própria conta bancária do profissional (via a futura API Pix própria)
-- -- não existe mais uma conta separada da plataforma segurando o valor.
-- O estado "retido" agora é só um STATUS de `transacoes` (Seção 4), não
-- precisa de uma tabela à parte.
DROP TABLE IF EXISTS retencoes_escrow CASCADE;

-- Subconta do Pagar.me ("recipient") -- não existe mais Split via gateway.
-- `chave_pix` PERMANECE (Seção 2 de 14_pagamentos_escrow_split.sql) -- ela
-- vira, se possível, ainda MAIS central: é para onde a cobrança Pix da
-- Seção 5 abaixo é gerada.
ALTER TABLE profissionais DROP COLUMN IF EXISTS id_recebedor_gateway;

-- `transacoes` é redesenhada do zero na Seção 5. O CASCADE aqui derruba
-- automaticamente as FKs de `disputas_transacao`, `creditos_usuario` e
-- `notas_fiscais` que apontavam para ela -- as TABELAS em si sobrevivem
-- (CASCADE de DROP TABLE só remove objetos DEPENDENTES da tabela dropada,
-- nunca a tabela que só tem uma FK apontando para ela). A Seção 6 recria
-- essas três FKs contra a nova `transacoes`.
DROP TABLE IF EXISTS transacoes CASCADE;

DROP TYPE IF EXISTS status_transacao_enum;
DROP TYPE IF EXISTS status_escrow_enum;
-- Recriado na Seção 4 com mais opções -- não estava mais limitado ao que
-- um gateway de cartão/Pix processava, agora é só informativo.
DROP TYPE IF EXISTS metodo_pagamento_enum;


-- ============================================================================
--  SEÇÃO 2 - PAPEL ADMIN
--
--  Pedido explícito: "Se for necessário crie a conta do adm para fazer
--  gerenciar". É necessário: marcar a comissão como conciliada e (no
--  futuro) ver o dashboard de saldo exigem alguém além de cliente/
--  profissional. Mesma filosofia do resto do schema (Single Table Design
--  por papel, ver `profissionais`/`clientes` na Etapa 1) -- só que aqui a
--  tabela é bem mais enxuta: admin não navega o mapa, não avalia, não tem
--  perfil público. Sem auto-cadastro (não existe rota POST /auth/cadastro/
--  admin) -- a PRIMEIRA conta é criada por INSERT manual (ver instrução no
--  final desta seção), o backend nunca vai expor um jeito de qualquer
--  pessoa virar admin sozinha.
-- ============================================================================

CREATE TABLE admins (
    admin_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome          VARCHAR(150) NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,
    senha_hash    TEXT NOT NULL,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_admin_email_formato CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

CREATE TRIGGER trg_admins_updated_at
    BEFORE UPDATE ON admins
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON TABLE admins IS
    'Contas de administrador (gerenciar conciliação de comissão, dashboard). Sem auto-cadastro -- primeira conta via INSERT manual, ver comentário de exemplo no final deste arquivo.';


-- ============================================================================
--  SEÇÃO 3 - TIPOS ENUMERADOS NOVOS
-- ============================================================================

-- Ciclo de vida completo do novo fluxo (proposta -> confirmação ->
-- pagamento -> retenção -> liberação), substituindo o antigo
-- (PENDENTE/AUTORIZADA/FALHOU/EM_DISPUTA/LIBERADA/REEMBOLSADA, pensado
-- para um checkout automático via gateway).
CREATE TYPE status_transacao_enum AS ENUM (
    'AGUARDANDO_CONFIRMACAO_CLIENTE', -- profissional propôs um valor; cliente ainda não respondeu
    'RECUSADA',                       -- cliente recusou o valor proposto (fim de linha -- nova proposta = nova linha)
    'AGUARDANDO_PAGAMENTO',           -- cliente confirmou; chave Pix/boleto gerada, aguardando o cliente pagar
    'RETIDA',                         -- API Pix própria confirmou o pagamento -- dinheiro na conta do profissional, CONGELADO
    'LIBERADA',                       -- cliente confirmou término do serviço -- retenção liberada, comissão a caminho da plataforma
    'CANCELADA'                       -- cancelada antes da liberação (ex.: serviço cancelado por qualquer lado)
);

-- Livre de amarras de gateway agora -- era PIX/CARTAO (o que o Pagar.me
-- processava); o profissional pode gerar qualquer um destes na própria
-- conta.
CREATE TYPE metodo_pagamento_enum AS ENUM ('PIX', 'BOLETO', 'OUTRO');

-- Pedido explícito literal: "status_repasse (pendente/concluído)".
-- REINTERPRETADO para este modelo invertido de fluxo de dinheiro: aqui a
-- plataforma NÃO paga o profissional (ele já fica com o dinheiro desde a
-- retenção) -- é a COMISSÃO da plataforma (os 8,9%) que precisa ser
-- CONFIRMADA como recebida na conta da empresa. `status_repasse` =
-- PENDENTE até um admin conferir que a comissão caiu; CONCLUIDO depois de
-- conciliado. Ver `transacoes.status_repasse` na Seção 5 -- só passa a
-- fazer sentido depois que `status = 'LIBERADA'`.
CREATE TYPE status_repasse_enum AS ENUM ('PENDENTE', 'CONCLUIDO');


-- ============================================================================
--  SEÇÃO 4 - TABELA: transacoes (redesenhada do zero)
--
--  Uma linha por TENTATIVA de proposta de valor de um serviço -- mesmo
--  espírito de "uma linha por tentativa" da versão anterior: se o cliente
--  RECUSA um valor, o profissional pode propor outro, e o histórico das
--  duas tentativas fica preservado (não é um UPDATE por cima da recusada).
--
--  Quem propõe é sempre `servicos.profissional_id` -- não duplicamos essa
--  informação aqui (mesmo motivo de nunca duplicar o que já dá pra buscar
--  via JOIN, repetido em todo o resto deste schema).
-- ============================================================================

CREATE TABLE transacoes (
    id_transacao     UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_servico       UUID NOT NULL,

    status            status_transacao_enum NOT NULL DEFAULT 'AGUARDANDO_CONFIRMACAO_CLIENTE',

    -- ---------- Valor e cálculo automático (pedido explícito) ----------
    -- "O sistema deve ser capaz de registrar a entrada total, calcular
    -- automaticamente a minha parte e o valor a ser pago ao prestador."
    valor_total                NUMERIC(10, 2) NOT NULL,

    -- Percentual USADO nesta transação -- gravado por linha (não lido de
    -- uma constante global no momento da leitura) para o histórico
    -- contábil continuar correto mesmo se a taxa mudar no futuro. 8.9 é o
    -- valor combinado agora; DEFAULT aqui é só conveniência de INSERT, o
    -- backend sempre grava o percentual vigente explicitamente.
    taxa_comissao_percentual   NUMERIC(5, 2) NOT NULL DEFAULT 8.9,

    -- GERADAS pelo banco -- pedido explícito ("calcular automaticamente"):
    -- nunca escritas à mão, sempre derivadas de valor_total e do
    -- percentual, então as três colunas NUNCA podem ficar "fora de
    -- sincronia" entre si (diferente da versão anterior, em que
    -- taxa_plataforma/valor_repasse eram calculados em código e podiam,
    -- em tese, divergir do valor_total se algum bug escrevesse errado).
    taxa_comissao   NUMERIC(10, 2) GENERATED ALWAYS AS (
                        ROUND(valor_total * taxa_comissao_percentual / 100, 2)
                    ) STORED,
    valor_repasse   NUMERIC(10, 2) GENERATED ALWAYS AS (
                        valor_total - ROUND(valor_total * taxa_comissao_percentual / 100, 2)
                    ) STORED,

    -- ---------- Proposta e resposta do cliente ----------
    proposto_em       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    respondido_em     TIMESTAMPTZ, -- preenchido quando o cliente confirma OU recusa

    -- ---------- Cobrança Pix/Boleto (gerada na conta do PROFISSIONAL) ----------
    metodo_pagamento       metodo_pagamento_enum, -- só definido na confirmação (cliente escolhe)
    -- "Copia e cola" do Pix (ou linha digitável do boleto) mostrado ao
    -- cliente -- devolvido pela API Pix própria (ainda a construir, ver
    -- comentário no topo do arquivo); nulo até `AGUARDANDO_PAGAMENTO`.
    chave_cobranca          TEXT,
    -- ID da cobrança do lado da API Pix própria -- é o que o webhook dela
    -- (quando existir) usa para dizer "esta cobrança foi paga". UNIQUE
    -- pela mesma razão de idempotência de sempre (nunca duas transações
    -- apontando para a mesma cobrança externa).
    id_cobranca_externa     TEXT UNIQUE,

    pago_em                 TIMESTAMPTZ, -- confirmado pela API própria -- transacao vira RETIDA
    liberado_em             TIMESTAMPTZ, -- cliente confirmou término -- transacao vira LIBERADA

    -- ---------- Conciliação da comissão (pedido explícito: status_repasse) ----------
    status_repasse                    status_repasse_enum NOT NULL DEFAULT 'PENDENTE',
    repasse_confirmado_em             TIMESTAMPTZ,
    repasse_confirmado_por_admin_id   UUID,
    -- Anotação livre para conciliação contábil -- ID do Pix/comprovante da
    -- comissão recebida, o texto que você quiser guardar para bater com o
    -- extrato do banco depois.
    referencia_repasse                TEXT,

    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ======================= CHAVES ESTRANGEIRAS =======================

    CONSTRAINT fk_transacoes_servico
        FOREIGN KEY (id_servico)
        REFERENCES servicos (id_servico)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_transacoes_admin_conciliacao
        FOREIGN KEY (repasse_confirmado_por_admin_id)
        REFERENCES admins (admin_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- ======================= CONSTRAINTS =======================

    CONSTRAINT chk_transacao_valor_total_positivo CHECK (valor_total > 0),
    CONSTRAINT chk_transacao_percentual_coerente CHECK (
        taxa_comissao_percentual >= 0 AND taxa_comissao_percentual <= 100
    ),

    -- Completude condicional bidirecional -- mesmo padrão de
    -- `chk_servico_conclusao` (01_schema_2.sql): só RECUSADA/CANCELADA
    -- têm `respondido_em`... na verdade RECUSADA sempre tem, as demais
    -- (AGUARDANDO_PAGAMENTO em diante) também tiveram uma confirmação --
    -- só `AGUARDANDO_CONFIRMACAO_CLIENTE` nasce sem resposta ainda.
    CONSTRAINT chk_transacao_resposta_coerente CHECK (
        (status = 'AGUARDANDO_CONFIRMACAO_CLIENTE' AND respondido_em IS NULL)
        OR
        (status <> 'AGUARDANDO_CONFIRMACAO_CLIENTE' AND respondido_em IS NOT NULL)
    ),

    CONSTRAINT chk_transacao_pagamento_completo CHECK (
        (status = ANY(ARRAY['RETIDA','LIBERADA']::status_transacao_enum[])
            AND pago_em IS NOT NULL AND metodo_pagamento IS NOT NULL)
        OR
        (status <> ALL(ARRAY['RETIDA','LIBERADA']::status_transacao_enum[]) AND pago_em IS NULL)
    ),

    CONSTRAINT chk_transacao_liberacao_completa CHECK (
        (status = 'LIBERADA' AND liberado_em IS NOT NULL)
        OR
        (status <> 'LIBERADA' AND liberado_em IS NULL)
    ),

    -- status_repasse só faz sentido (CONCLUIDO) depois de LIBERADA -- não
    -- dá para conciliar uma comissão que ainda nem foi gerada.
    CONSTRAINT chk_transacao_repasse_apos_liberacao CHECK (
        status_repasse = 'PENDENTE'
        OR (status_repasse = 'CONCLUIDO' AND status = 'LIBERADA' AND repasse_confirmado_em IS NOT NULL)
    )
);

CREATE INDEX idx_transacoes_servico       ON transacoes (id_servico);
CREATE INDEX idx_transacoes_status        ON transacoes (status);
CREATE INDEX idx_transacoes_status_repasse ON transacoes (status_repasse) WHERE status = 'LIBERADA';

CREATE TRIGGER trg_transacoes_updated_at
    BEFORE UPDATE ON transacoes
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON TABLE transacoes IS
    'Uma linha por proposta de valor de um serviço. O profissional propõe (avaliação presencial), o cliente confirma/recusa, e -- se confirmado -- uma cobrança Pix/boleto é gerada na conta do PRÓPRIO profissional (não da plataforma). taxa_comissao/valor_repasse são sempre derivados (GENERATED) de valor_total, nunca escritos à mão.';
COMMENT ON COLUMN transacoes.status_repasse IS
    'Conciliação da COMISSÃO da plataforma (não um repasse ao profissional -- ele já fica com o dinheiro desde a retenção). PENDENTE até um admin confirmar que os 8,9% caíram na conta da empresa.';


-- ============================================================================
--  SEÇÃO 5 - RECONECTAR disputas_transacao / creditos_usuario / notas_fiscais
--
--  As três tabelas sobreviveram ao DROP TABLE transacoes CASCADE (Seção 1)
--  -- só perderam a FK que apontava para a `transacoes` antiga. Recriando
--  aqui, contra a `transacoes` nova (mesmo nome de coluna, `id_transacao`
--  UUID, então a FK é idêntica em formato à anterior).
-- ============================================================================

ALTER TABLE disputas_transacao
    ADD CONSTRAINT fk_disputa_transacao
    FOREIGN KEY (id_transacao)
    REFERENCES transacoes (id_transacao)
    ON DELETE RESTRICT
    ON UPDATE CASCADE;

ALTER TABLE creditos_usuario
    ADD CONSTRAINT fk_credito_transacao
    FOREIGN KEY (id_transacao)
    REFERENCES transacoes (id_transacao)
    ON DELETE SET NULL
    ON UPDATE CASCADE;

ALTER TABLE notas_fiscais
    ADD CONSTRAINT fk_nota_fiscal_transacao
    FOREIGN KEY (id_transacao)
    REFERENCES transacoes (id_transacao)
    ON DELETE SET NULL
    ON UPDATE CASCADE;


-- ============================================================================
--  SEÇÃO 6 - VERIFICAÇÃO
--
--  Depois de rodar esta migração, crie sua primeira conta de admin com um
--  INSERT manual (troque o e-mail e gere o hash da senha com bcrypt --
--  o MESMO algoritmo usado pelo backend, ver backend/src/utils/senha.ts --
--  nunca insira senha em texto puro aqui):
--
--    node -e "require('bcryptjs').hash('sua-senha-aqui', 10).then(console.log)"
--
--    INSERT INTO admins (nome, email, senha_hash)
--    VALUES ('Seu Nome', 'voce@example.com', 'COLE_O_HASH_GERADO_ACIMA');
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 15 aplicada com sucesso.';
    RAISE NOTICE ' Removido: retencoes_escrow, eventos_webhook_pagamento,';
    RAISE NOTICE ' colunas *_gateway (transacoes e profissionais).';
    RAISE NOTICE ' Criado: tabela admins, transacoes redesenhada';
    RAISE NOTICE ' (proposta -> confirmacao -> retencao -> liberacao),';
    RAISE NOTICE ' status_repasse_enum.';
    RAISE NOTICE ' PROXIMO PASSO MANUAL: criar a primeira conta admin';
    RAISE NOTICE ' (ver instrucoes no comentario da Secao 6 deste arquivo).';
    RAISE NOTICE '---------------------------------------------';
END $$;
