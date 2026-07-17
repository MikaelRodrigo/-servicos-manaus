-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Pagamento com Retenção (Escrow) + Split" -- modelagem de banco
--  para o fluxo de pagamento especificado: autorização/retenção na etapa
--  do checkout, liberação (split) só depois da confirmação do cliente, com
--  disputa/mediação e cashback.
--
--  Gateway escolhido: Pagar.me (campos de integração nomeados a partir da
--  API dele -- "recipient" para a subconta do split, "charge"/"order" para
--  os IDs do lado do gateway). Troca de gateway no futuro não deveria
--  quebrar este schema: os `id_*_gateway` são só TEXT opcionais, sem
--  nenhuma lógica de negócio amarrada ao formato específico de nenhum
--  provedor.
--
--  ESCOPO DESTA MIGRAÇÃO: só modelagem de banco (tabelas, enums,
--  constraints, índices). NENHUMA chamada ao gateway, rota de API, ou
--  handler de webhook é criada aqui -- isso é a próxima etapa (services/
--  routes do backend), fora do escopo deste arquivo.
--
--  Nomenclatura: a especificação original nomeou as tabelas em inglês
--  (`Transactions`, `Escrow_Hold`, `User_Credits`) -- traduzidas aqui para
--  o padrão 100% português já usado em TODAS as migrações anteriores
--  (`profissionais`, `clientes`, `servicos`, `avaliacoes_profissional`),
--  por consistência com o resto do schema.
--
--  Rodar como: psql "sua-connection-string-neon" -f 14_pagamentos_escrow_split.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - POR QUE ISTO EXISTE
--
--  Até aqui, `servicos.status` (status_servico_enum: SOLICITADO -> ACEITO ->
--  EM_ANDAMENTO -> CONCLUIDO) descreve só o ciclo de vida da EXECUÇÃO do
--  serviço -- não existe noção nenhuma de dinheiro no schema. O fluxo
--  pedido introduz um ciclo de vida PARALELO, o do PAGAMENTO (autorizado ->
--  retido em Escrow -> liberado/repassado ao profissional), que PRECEDE e
--  CONDICIONA a execução (o profissional só pode "Iniciar" um serviço
--  pago, nunca antes).
--
--  Em vez de sobrecarregar `status_servico_enum` com estados de pagamento
--  (o que misturaria dois conceitos independentes na mesma coluna, e
--  quebraria toda a lógica existente que já lê esse enum), o pagamento
--  ganha sua PRÓPRIA tabela (`transacoes`), ligada a `servicos` por
--  `id_servico` -- mesmo espírito de `avaliacoes_profissional`/
--  `avaliacoes_cliente` na Etapa 1: nunca duplicar o que já dá para buscar
--  via JOIN, e nunca misturar dois ciclos de vida numa coluna só. O
--  backend, na próxima etapa, é quem decide (nas ROTAS, não no banco)
--  bloquear a transição de `servicos.status` para 'EM_ANDAMENTO' até
--  `transacoes.status = 'AUTORIZADA'` existir para aquele serviço.
-- ============================================================================


-- ============================================================================
--  SEÇÃO 2 - TIPOS ENUMERADOS
-- ============================================================================

-- Ciclo de vida do PAGAMENTO em si (Etapas A e D do fluxo pedido).
-- 'FALHOU' e 'EM_DISPUTA' não estavam no checklist original (que só listava
-- pending/captured/released/refunded), mas são exigidos pelo PRÓPRIO fluxo
-- descrito: a Etapa A cita um webhook `payment_failed`, e a Etapa C
-- descreve `REPORT_ISSUE` "travando o fluxo de liberação" -- sem um estado
-- próprio para isso, não haveria como distinguir "ainda em execução
-- normal" de "liberação bloqueada por disputa" só olhando a transação.
CREATE TYPE status_transacao_enum AS ENUM (
    'PENDENTE',     -- Order_ID criado, aguardando o cliente pagar (Etapa A)
    'AUTORIZADA',   -- gateway confirmou o recebimento; valor retido no Escrow da plataforma, NÃO no profissional
    'FALHOU',       -- gateway recusou/expirou (webhook payment_failed)
    'EM_DISPUTA',   -- cliente acionou REPORT_ISSUE; liberação travada até mediação (Etapa C)
    'LIBERADA',     -- CONFIRM_SERVICE do cliente -> Transfer/Split executado (Etapa D)
    'REEMBOLSADA'   -- devolvido ao cliente (cancelamento ou disputa resolvida a favor do cliente)
);

-- PIX não tem parcela; cartão pode ter (a "taxa de antecipação/parcelamento"
-- citada na Etapa A só existe quando o método é cartão).
CREATE TYPE metodo_pagamento_enum AS ENUM ('PIX', 'CARTAO');

-- Espelha o status da transação-mãe, mas é um conceito separado de
-- propósito: uma transação pode ficar 'AUTORIZADA' por um tempo antes do
-- Escrow correspondente sequer existir como linha (ver Seção 4) -- não é
-- redundante, é sequencial.
CREATE TYPE status_escrow_enum AS ENUM ('RETIDO', 'LIBERADO', 'REEMBOLSADO');

CREATE TYPE status_disputa_enum AS ENUM (
    'ABERTA',
    'EM_MEDIACAO',
    'RESOLVIDA_CLIENTE',
    'RESOLVIDA_PROFISSIONAL'
);

CREATE TYPE status_nota_fiscal_enum AS ENUM ('PENDENTE', 'EMITIDA', 'ERRO');


-- ============================================================================
--  SEÇÃO 3 - COLUNAS NOVAS EM profissionais (destino do Split)
--
--  "Conta Virtual (Split de Pagamento): O gateway deve criar subcontas
--  para os profissionais" + "Recipient: Conta PIX do profissional"
--  (Etapa D). Duas colunas novas, as DUAS nulas (backfill retroativo é
--  impossível -- nenhum profissional existente jamais forneceu isso; cada
--  um precisa cadastrar/a plataforma precisa criar a subconta dele
--  individualmente, num fluxo à parte, fora desta migração).
-- ============================================================================

ALTER TABLE profissionais
    ADD COLUMN IF NOT EXISTS chave_pix            VARCHAR(140),
    ADD COLUMN IF NOT EXISTS id_recebedor_gateway  TEXT UNIQUE;

COMMENT ON COLUMN profissionais.chave_pix IS
    'Chave PIX de destino do repasse (Transfer_Amount, Etapa D). Aceita qualquer formato de chave (CPF/CNPJ/e-mail/telefone/aleatória) -- validação de formato fica no backend, não no banco.';
COMMENT ON COLUMN profissionais.id_recebedor_gateway IS
    'ID da subconta ("recipient") criada no gateway (Pagar.me) para este profissional -- é o que permite o Split de Pagamento nativo da API. Nulo até a subconta ser criada (fluxo de onboarding financeiro, fora desta migração).';


-- ============================================================================
--  SEÇÃO 4 - TABELA: transacoes
--
--  Uma linha por TENTATIVA de pagamento de um `servicos.id_servico`
--  (Order_ID do fluxo pedido). Não é UNIQUE em id_servico de propósito:
--  uma autorização que falha (`FALHOU`) pode ser seguida de uma nova
--  tentativa, e queremos o HISTÓRICO das duas, não só a última.
-- ============================================================================

CREATE TABLE transacoes (
    id_transacao         UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_servico           UUID NOT NULL,

    status                status_transacao_enum NOT NULL DEFAULT 'PENDENTE',
    metodo_pagamento      metodo_pagamento_enum NOT NULL,
    parcelas               SMALLINT NOT NULL DEFAULT 1,

    -- ---------- Valores (Etapa A: "calcular a taxa de antecipação/
    -- parcelamento e somar ao valor final antes do charge") ----------
    valor_servico          NUMERIC(10, 2) NOT NULL,
    taxa_parcelamento      NUMERIC(10, 2) NOT NULL DEFAULT 0,
    -- Gerada pelo banco (nunca escrita à mão) -- é exatamente o valor
    -- cobrado do cliente no gateway (`amount` do charge), soma das duas
    -- colunas acima. Ter o Postgres calculando evita as duas ficarem
    -- "fora de sincronia" com o valor real do charge.
    valor_total_cobrado    NUMERIC(10, 2) GENERATED ALWAYS AS (valor_servico + taxa_parcelamento) STORED,

    -- ---------- Split (Etapa D) ----------
    -- Taxa da plataforma É conhecida desde a autorização (regra de
    -- negócio fixa), mas o valor de repasse só é CALCULADO/CONGELADO no
    -- momento da liberação -- fica NULL até lá de propósito (só existe de
    -- verdade depois que a liberação acontece).
    taxa_plataforma             NUMERIC(10, 2) NOT NULL DEFAULT 0,
    valor_repasse_profissional  NUMERIC(10, 2),

    -- ---------- IDs do lado do gateway (Pagar.me) ----------
    -- TEXT, não UUID -- o formato do ID é decidido pelo gateway, não por
    -- nós. UNIQUE em cada um: é o que garante, no nível do banco, que um
    -- webhook duplicado (reentrega, comum em qualquer gateway) nunca gera
    -- uma segunda linha para o MESMO pagamento -- ver também
    -- `eventos_webhook_pagamento` (Seção 7), que ataca o mesmo problema
    -- de um ângulo diferente (idempotência do EVENTO, não da transação).
    id_pedido_gateway       TEXT UNIQUE,
    id_cobranca_gateway     TEXT UNIQUE,
    id_transacao_gateway    TEXT UNIQUE,

    autorizada_em           TIMESTAMPTZ,
    liberada_em              TIMESTAMPTZ,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ======================= CHAVES ESTRANGEIRAS =======================

    -- ON DELETE RESTRICT: mesmo motivo de `fk_servicos_cliente` na Etapa 1
    -- -- histórico financeiro nunca pode ser apagado junto com o serviço.
    CONSTRAINT fk_transacoes_servico
        FOREIGN KEY (id_servico)
        REFERENCES servicos (id_servico)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    -- ======================= CONSTRAINTS =======================

    CONSTRAINT chk_transacao_valor_servico_positivo CHECK (valor_servico > 0),
    CONSTRAINT chk_transacao_taxa_parcelamento_nao_negativa CHECK (taxa_parcelamento >= 0),
    CONSTRAINT chk_transacao_taxa_plataforma_nao_negativa CHECK (taxa_plataforma >= 0),
    CONSTRAINT chk_transacao_repasse_nao_negativo CHECK (
        valor_repasse_profissional IS NULL OR valor_repasse_profissional >= 0
    ),

    -- PIX nunca parcela; cartão parcela em pelo menos 1x.
    CONSTRAINT chk_transacao_parcelas_coerentes CHECK (
        (metodo_pagamento = 'PIX' AND parcelas = 1)
        OR
        (metodo_pagamento = 'CARTAO' AND parcelas >= 1)
    ),

    -- Só uma transação LIBERADA tem repasse calculado e timestamp de
    -- liberação -- e NENHUMA outra tem, nos dois sentidos (mesmo padrão
    -- bidirecional de `chk_servico_conclusao`, Etapa 1: lá também se exige
    -- tanto "só CONCLUIDO tem data_conclusao" quanto "todo CONCLUIDO tem
    -- data_conclusao").
    CONSTRAINT chk_transacao_liberacao_completa CHECK (
        (status = 'LIBERADA' AND liberada_em IS NOT NULL AND valor_repasse_profissional IS NOT NULL)
        OR
        (status <> 'LIBERADA' AND liberada_em IS NULL AND valor_repasse_profissional IS NULL)
    )
);

CREATE INDEX idx_transacoes_servico ON transacoes (id_servico);
CREATE INDEX idx_transacoes_status  ON transacoes (status);

CREATE TRIGGER trg_transacoes_updated_at
    BEFORE UPDATE ON transacoes
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON TABLE transacoes IS
    'Uma linha por tentativa de pagamento de um serviço (Order_ID do fluxo de checkout). O dinheiro em si só se move de verdade em duas ocasiões: autorização (cliente -> Escrow da plataforma) e liberação (Escrow -> PIX do profissional, via Split do gateway).';
COMMENT ON COLUMN transacoes.valor_total_cobrado IS
    'Coluna GERADA (valor_servico + taxa_parcelamento). Nunca escrever diretamente -- é o valor real do charge no gateway.';


-- ============================================================================
--  SEÇÃO 5 - TABELA: retencoes_escrow (Escrow_Hold)
--
--  "O valor pago pelo cliente não vai para a conta do profissional
--  instantaneamente; ele é bloqueado na conta Escrow da plataforma até
--  que o evento de liberação seja acionado." Uma linha por transação
--  autorizada -- é o registro explícito de QUANTO está retido e DESDE
--  QUANDO, separado da transação em si para deixar auditável o momento
--  exato da retenção e da liberação (não só o status "final").
-- ============================================================================

CREATE TABLE retencoes_escrow (
    id_retencao        UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- UNIQUE: 1:1 com a transação -- cada transação autorizada retém
    -- exatamente UM valor no Escrow (nunca duas retenções para a mesma
    -- autorização).
    id_transacao       UUID NOT NULL UNIQUE,

    valor_retido        NUMERIC(10, 2) NOT NULL,
    status               status_escrow_enum NOT NULL DEFAULT 'RETIDO',

    retido_em            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    liberado_em          TIMESTAMPTZ,

    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_retencao_transacao
        FOREIGN KEY (id_transacao)
        REFERENCES transacoes (id_transacao)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT chk_retencao_valor_positivo CHECK (valor_retido > 0),

    CONSTRAINT chk_retencao_liberacao_completa CHECK (
        (status IN ('LIBERADO', 'REEMBOLSADO') AND liberado_em IS NOT NULL)
        OR
        (status = 'RETIDO' AND liberado_em IS NULL)
    )
);

CREATE INDEX idx_retencoes_escrow_status ON retencoes_escrow (status);

CREATE TRIGGER trg_retencoes_escrow_updated_at
    BEFORE UPDATE ON retencoes_escrow
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON TABLE retencoes_escrow IS
    'Registro de quanto está retido na conta Escrow da plataforma, e desde/até quando -- 1:1 com uma transacao AUTORIZADA.';


-- ============================================================================
--  SEÇÃO 6 - TABELA: disputas_transacao (mediação da Etapa C)
--
--  "O cliente deve ter a opção REPORT_ISSUE. Se acionada, o fluxo de
--  liberação trava e abre um ticket para mediação, retendo o valor."
--  Uma linha por chamado aberto.
--
--  Removido de propósito: o cálculo automático de dano (desconto de 30%
--  do profissional / reembolso de 20% extra da plataforma) que uma versão
--  anterior desta migração incluía aqui -- decisão explícita de tirar essa
--  funcionalidade da estrutura de banco. A resolução da disputa (Etapa C)
--  continua existindo (`status`, `resolucao_observacao`, `resolvido_em`),
--  só sem nenhum valor de ajuste automático embutido no schema.
-- ============================================================================

CREATE TABLE disputas_transacao (
    id_disputa               UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_transacao             UUID NOT NULL,
    -- Denormalizado de propósito (mesmo motivo de `servicos.categoria_id`
    -- na migração 12): consultas por serviço ("todas as disputas deste
    -- atendimento") não deveriam depender de passar por `transacoes`.
    id_servico               UUID NOT NULL,
    aberto_por_cliente_id    UUID NOT NULL,

    motivo                    TEXT NOT NULL,
    status                     status_disputa_enum NOT NULL DEFAULT 'ABERTA',

    resolucao_observacao      TEXT,
    resolvido_em               TIMESTAMPTZ,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_disputa_transacao
        FOREIGN KEY (id_transacao)
        REFERENCES transacoes (id_transacao)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_disputa_servico
        FOREIGN KEY (id_servico)
        REFERENCES servicos (id_servico)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_disputa_cliente
        FOREIGN KEY (aberto_por_cliente_id)
        REFERENCES clientes (cliente_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT chk_disputa_resolucao_completa CHECK (
        (status IN ('RESOLVIDA_CLIENTE', 'RESOLVIDA_PROFISSIONAL') AND resolvido_em IS NOT NULL)
        OR
        (status IN ('ABERTA', 'EM_MEDIACAO') AND resolvido_em IS NULL)
    )
);

CREATE INDEX idx_disputas_transacao_status  ON disputas_transacao (status);
CREATE INDEX idx_disputas_transacao_servico ON disputas_transacao (id_servico);

CREATE TRIGGER trg_disputas_transacao_updated_at
    BEFORE UPDATE ON disputas_transacao
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON TABLE disputas_transacao IS
    'Ticket de mediação aberto pelo cliente via REPORT_ISSUE -- enquanto aberto/em mediação, a transacao correspondente deve permanecer em status EM_DISPUTA (regra aplicada pelo backend, não pelo banco).';


-- ============================================================================
--  SEÇÃO 7 - TABELA: eventos_webhook_pagamento
--
--  Não estava no checklist original, mas é o que faz o requisito "Webhook
--  (O gatilho): O sistema precisa de Webhooks ativos para escutar eventos
--  do gateway" funcionar de forma SEGURA: todo gateway de pagamento pode
--  reentregar o mesmo evento mais de uma vez (falha de rede, timeout do
--  lado do backend, etc.) -- sem um registro do que já foi processado, um
--  webhook duplicado processaria a mesma autorização/liberação DUAS
--  vezes. `id_evento_externo UNIQUE` é a trava de idempotência: a segunda
--  tentativa de INSERT do mesmo evento falha no banco, então o handler do
--  backend sabe (pelo erro de UNIQUE) que já tratou aquele evento antes.
-- ============================================================================

CREATE TABLE eventos_webhook_pagamento (
    id_evento             UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    gateway                 TEXT NOT NULL DEFAULT 'pagarme',
    -- ex.: 'payment_authorized', 'payment_failed' -- os nomes de evento
    -- citados no fluxo pedido. TEXT (não ENUM) de propósito: o catálogo de
    -- eventos de um gateway muda com mais frequência do que uma migração
    -- de banco deveria acompanhar.
    tipo_evento             TEXT NOT NULL,
    id_evento_externo       TEXT NOT NULL UNIQUE,

    payload                  JSONB NOT NULL,

    id_transacao             UUID,

    processado_em            TIMESTAMPTZ,
    erro_processamento       TEXT,

    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ON DELETE SET NULL: o evento em si (payload bruto do gateway) tem
    -- valor de auditoria PRÓPRIO -- não deveria desaparecer se a transação
    -- ligada a ele for removida (o que, na prática, nunca acontece, dado o
    -- ON DELETE RESTRICT em `transacoes`, mas o SET NULL é a postura
    -- correta mesmo assim).
    CONSTRAINT fk_evento_webhook_transacao
        FOREIGN KEY (id_transacao)
        REFERENCES transacoes (id_transacao)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);

CREATE INDEX idx_eventos_webhook_transacao   ON eventos_webhook_pagamento (id_transacao) WHERE id_transacao IS NOT NULL;
CREATE INDEX idx_eventos_webhook_nao_processado ON eventos_webhook_pagamento (created_at) WHERE processado_em IS NULL;

COMMENT ON TABLE eventos_webhook_pagamento IS
    'Log bruto de todo webhook recebido do gateway, com trava de idempotencia (id_evento_externo UNIQUE) contra reentregas duplicadas.';


-- ============================================================================
--  SEÇÃO 8 - TABELA: creditos_usuario (User_Credits / cashback)
--
--  "Cashback: o backend gera uma entrada na tabela User_Credits (Moedas)
--  vinculada ao User_ID do cliente." Desenho de EXTRATO (ledger): cada
--  linha é um lançamento IMUTÁVEL (nunca um UPDATE de valor), a mesma
--  lógica contábil de um extrato bancário -- o "saldo" do cliente é a SOMA
--  das linhas, calculada por query, nunca guardada como um número solto
--  que pode dessincronizar.
-- ============================================================================

CREATE TABLE creditos_usuario (
    id_credito       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    cliente_id        UUID NOT NULL,
    -- Origem do crédito -- nulo permite lançamentos futuros sem uma
    -- transação por trás (ex.: uma promoção manual), mesmo que hoje só o
    -- cashback de serviço concluído gere linhas aqui.
    id_transacao       UUID,

    valor               NUMERIC(10, 2) NOT NULL,
    motivo               TEXT NOT NULL DEFAULT 'cashback_servico',

    -- Preenchido quando o crédito é gasto -- a LÓGICA de gasto (abater de
    -- uma cobrança futura) é do backend, fora do escopo desta migração;
    -- aqui só existe o campo que marca "já foi usado".
    utilizado_em         TIMESTAMPTZ,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ON DELETE CASCADE (diferente do RESTRICT usado em `servicos`/
    -- `transacoes`): isto não é um registro de AUDITORIA de um evento que
    -- já aconteceu no mundo real (como um serviço prestado) -- é o SALDO
    -- ativo de um cliente específico. Se a conta do cliente for removida,
    -- não há razão de negócio para manter linhas de crédito órfãs.
    CONSTRAINT fk_credito_cliente
        FOREIGN KEY (cliente_id)
        REFERENCES clientes (cliente_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_credito_transacao
        FOREIGN KEY (id_transacao)
        REFERENCES transacoes (id_transacao)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    -- Só créditos POSITIVOS por enquanto -- um mecanismo de débito
    -- (estorno de cashback, por exemplo) exigiria repensar esta constraint
    -- quando for implementado; V1 é só acúmulo.
    CONSTRAINT chk_credito_valor_positivo CHECK (valor > 0)
);

CREATE INDEX idx_creditos_usuario_cliente ON creditos_usuario (cliente_id);
CREATE INDEX idx_creditos_usuario_nao_utilizados ON creditos_usuario (cliente_id) WHERE utilizado_em IS NULL;

CREATE TRIGGER trg_creditos_usuario_updated_at
    BEFORE UPDATE ON creditos_usuario
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON TABLE creditos_usuario IS
    'Extrato (ledger) de cashback do cliente -- o saldo disponivel e SUM(valor) WHERE utilizado_em IS NULL, nunca um numero solto guardado em outro lugar.';


-- ============================================================================
--  SEÇÃO 9 - TABELA: notas_fiscais (Automação Fiscal)
--
--  "Integrar API de emissão de nota fiscal (ex: eNotas ou prefeitura
--  local) via webhook na finalização do serviço." Uma linha por tentativa
--  de emissão -- `id_externo_provedor` guarda o ID do lado do eNotas (ou
--  equivalente), pro backend conseguir consultar o status/reemitir sem
--  duplicar.
-- ============================================================================

CREATE TABLE notas_fiscais (
    id_nota                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    id_servico               UUID NOT NULL,
    id_transacao              UUID,

    status                     status_nota_fiscal_enum NOT NULL DEFAULT 'PENDENTE',
    numero_nota                TEXT,
    id_externo_provedor        TEXT UNIQUE,
    url_pdf                     TEXT,
    erro                         TEXT,

    emitida_em                   TIMESTAMPTZ,

    created_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_nota_fiscal_servico
        FOREIGN KEY (id_servico)
        REFERENCES servicos (id_servico)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_nota_fiscal_transacao
        FOREIGN KEY (id_transacao)
        REFERENCES transacoes (id_transacao)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    CONSTRAINT chk_nota_fiscal_emissao_completa CHECK (
        (status = 'EMITIDA' AND emitida_em IS NOT NULL AND numero_nota IS NOT NULL)
        OR
        (status <> 'EMITIDA' AND emitida_em IS NULL AND numero_nota IS NULL)
    )
);

CREATE INDEX idx_notas_fiscais_servico ON notas_fiscais (id_servico);
CREATE INDEX idx_notas_fiscais_status  ON notas_fiscais (status);

CREATE TRIGGER trg_notas_fiscais_updated_at
    BEFORE UPDATE ON notas_fiscais
    FOR EACH ROW EXECUTE FUNCTION fn_atualiza_updated_at();

COMMENT ON TABLE notas_fiscais IS
    'Uma linha por tentativa de emissao de nota fiscal via provedor externo (ex.: eNotas), disparada pelo backend na finalizacao do servico (CONFIRM_SERVICE).';


-- ============================================================================
--  SEÇÃO 10 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 14 aplicada com sucesso.';
    RAISE NOTICE ' Tabelas criadas: transacoes, retencoes_escrow,';
    RAISE NOTICE ' disputas_transacao, eventos_webhook_pagamento,';
    RAISE NOTICE ' creditos_usuario, notas_fiscais.';
    RAISE NOTICE ' Colunas novas em profissionais: chave_pix, id_recebedor_gateway.';
    RAISE NOTICE ' PRÓXIMA ETAPA (fora desta migração): rotas/services do';
    RAISE NOTICE ' backend para autorização, captura, split e webhooks do gateway.';
    RAISE NOTICE '---------------------------------------------';
END $$;
