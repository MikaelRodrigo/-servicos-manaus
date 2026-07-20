-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Perfil do Profissional: Contato, Endereço e Portfólio Visual"
--
--  Pedido do usuário: "permitir que o prestador gerencie seus dados de
--  contato, endereço e crie um portfólio visual para ser refletido ao
--  cliente que entrar no perfil."
--
--  O que esta migração muda:
--
--    1) `contato` -- a coluna JÁ EXISTE em `profissionais` (definida desde
--       01_schema_2.sql, preenchida no cadastro) mas nunca ficou EDITÁVEL
--       depois disso -- não há ALTER aqui, só backend/rota novos (ver
--       profissionais.repository.ts/routes.ts). Citado aqui só para
--       registro de que a coluna já existia.
--
--    2) `endereco` -- coluna NOVA, texto livre (complemento/referência:
--       número, ponto de referência etc.), EXATAMENTE no mesmo espírito de
--       `clientes.endereco` (ver 06_perfil_cliente_endereco.sql). Diferente
--       de `endereco_atuacao` (preenchido automaticamente pela
--       geocodificação do CEP, ver 08_cep_profissional.sql) -- este aqui é
--       digitado livremente pelo profissional, para detalhes que um CEP
--       sozinho não cobre.
--
--    3) `portfolio_profissional` -- tabela NOVA. Fotos que o PRÓPRIO
--       profissional escolhe subir pra mostrar seu trabalho (antes/depois,
--       ambiente, ferramentas etc.), exibidas no perfil público. Diferente
--       por completo de `vw_historico_portifolio` (fotos que o CLIENTE
--       anexa numa AVALIAÇÃO, migração 05/07): aquele é histórico de
--       terceiros sobre um serviço concluído; este é uma vitrine
--       curada pelo próprio profissional, sem vínculo com nenhum serviço
--       específico.
--
--  Rodar como: psql "sua-connection-string-neon" -f 16_contato_endereco_portfolio_profissional.sql
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - ENDEREÇO (texto livre, complementar ao CEP)
-- ============================================================================

ALTER TABLE profissionais ADD COLUMN IF NOT EXISTS endereco TEXT;

COMMENT ON COLUMN profissionais.endereco IS
    'Texto livre digitado pelo profissional (número, complemento, ponto de referência) -- NÃO alimenta geocodificação nem cálculo de distância (isso é `endereco_atuacao`, derivado do CEP). Puramente informativo, mesmo espírito de clientes.endereco.';


-- ============================================================================
--  SEÇÃO 2 - PORTFÓLIO VISUAL (fotos curadas pelo próprio profissional)
-- ============================================================================

CREATE TABLE portfolio_profissional (
    id_foto         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profissional_id UUID NOT NULL,

    url_foto        TEXT NOT NULL,
    -- Legenda opcional -- "Reforma de banheiro, Adrianópolis", por exemplo.
    -- Livre, sem obrigatoriedade: uma foto sozinha já entrega valor.
    legenda         TEXT,

    -- Ordem de exibição escolhida pelo profissional (arrastar para
    -- reordenar, feature futura -- por enquanto sempre inserida no fim,
    -- ver `proximaOrdem` no repository). Não é a ORDEM DE UPLOAD
    -- necessariamente -- são conceitos que podem divergir se um dia o app
    -- ganhar reordenação manual.
    ordem           INT NOT NULL DEFAULT 0,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_portfolio_profissional
        FOREIGN KEY (profissional_id)
        REFERENCES profissionais (profissional_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

-- Toda leitura é "todas as fotos DESTE profissional, em ordem" -- índice
-- composto cobre exatamente esse acesso (WHERE profissional_id = $1 ORDER
-- BY ordem).
CREATE INDEX idx_portfolio_profissional_ordem
    ON portfolio_profissional (profissional_id, ordem);

COMMENT ON TABLE portfolio_profissional IS
    'Galeria de fotos que o PRÓPRIO profissional escolhe subir para mostrar seu trabalho -- diferente de vw_historico_portifolio (fotos anexadas pelo CLIENTE numa avaliação). Exibida no perfil público (GET /profissionais/:id/portfolio-fotos) e gerenciada pelo dono (POST/DELETE /profissionais/me/portfolio-fotos).';


-- ============================================================================
--  SEÇÃO 3 - VERIFICAÇÃO
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 16 aplicada com sucesso.';
    RAISE NOTICE ' Coluna nova: profissionais.endereco (texto livre).';
    RAISE NOTICE ' Tabela nova: portfolio_profissional.';
    RAISE NOTICE ' PROXIMO PASSO: backend (rotas/repository) + Flutter';
    RAISE NOTICE ' (tela de editar perfil + perfil publico).';
    RAISE NOTICE '---------------------------------------------';
END $$;
