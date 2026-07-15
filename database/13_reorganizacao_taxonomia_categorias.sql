-- ============================================================================
--  APP DE SERVIÇOS GEOLOCALIZADOS - MANAUS/AM
--  Etapa "Reorganização da taxonomia de categorias e subcategorias"
--
--  Rodar como: psql "sua-connection-string-neon" -f 13_reorganizacao_taxonomia_categorias.sql
--  Pré-requisito: migração 09 (categorias/subcategorias) já aplicada.
-- ============================================================================


-- ============================================================================
--  SEÇÃO 1 - POR QUE ISTO EXISTE
--
--  Pedido explícito do usuário: revisão completa da lista de categorias e
--  subcategorias criada na migração 09, com três tipos de mudança:
--
--  1. RENOMEAR nomes -- várias categorias/subcategorias ganham rótulos mais
--     descritivos (ex.: "Frete" -> "Motorista de Frete / Carreto"). Não
--     muda NENHUM id, só o texto exibido -- profissionais já vinculados a
--     essas subcategorias continuam vinculados, sem precisar tocar em
--     `profissionais`.
--
--  2. MOVER subcategorias de categoria -- "Chaveiro", "Jardineiro" e
--     "Piscineiro" saem de "Serviços Gerais e Pet" (rebatizada "Outros
--     Serviços") e passam a viver em "Manutenção e Reforma" (rebatizada
--     "Manutenção e Reformas (Lar)"), que faz mais sentido tematicamente.
--     Isso PRECISA atualizar `subcategorias.categoria_id` E, em cascata,
--     `profissionais.categoria_id` de qualquer profissional já vinculado a
--     uma dessas três subcategorias -- ver comentário grande na Seção 3
--     sobre por que a ordem das operações importa aqui (a FK composta
--     `fk_profissionais_subcategoria_categoria`, da migração 09, não é
--     DEFERRABLE, então as duas tabelas não podem ficar temporariamente
--     incoerentes entre uma UPDATE e outra).
--
--  3. NOVA subcategoria -- "Limpeza de Ar-Condicionado", em "Manutenção e
--     Reformas (Lar)". Não existia NENHUMA opção de climatização/HVAC no
--     seed original.
--
--  Todas as operações usam WHERE por nome ANTIGO exato -- rodar esta
--  migração duas vezes é seguro (a segunda vez, nenhuma linha bate mais nos
--  nomes antigos, então tudo vira no-op).
-- ============================================================================


BEGIN;


-- ============================================================================
--  SEÇÃO 2 - RENOMEAR AS DUAS CATEGORIAS
-- ============================================================================

UPDATE categorias SET nome = 'Manutenção e Reformas (Lar)' WHERE nome = 'Manutenção e Reforma';
UPDATE categorias SET nome = 'Outros Serviços'             WHERE nome = 'Serviços Gerais e Pet';


-- ============================================================================
--  SEÇÃO 3 - MOVER Chaveiro / Jardineiro / Piscineiro PARA
--            "Manutenção e Reformas (Lar)"
--
--  A FK composta `fk_profissionais_subcategoria_categoria` (ver migração 09)
--  exige, a cada UPDATE em `profissionais`, que o par
--  (subcategoria_id, categoria_id) exista em `subcategorias`. Ela NÃO é
--  DEFERRABLE -- então não dá pra fazer isso em duas UPDATEs soltas: mudar
--  `subcategorias` primeiro invalidaria instantaneamente qualquer
--  profissional já apontando pro par antigo; mudar `profissionais` primeiro
--  apontaria pro par NOVO antes dele existir em `subcategorias`. A solução:
--  remover a FK, fazer as duas UPDATEs (em qualquer ordem, já sem
--  fiscalização), e recriar a FK no final -- o próprio `ADD CONSTRAINT`
--  revalida a tabela inteira, então qualquer inconsistência real (não
--  esperada aqui) ainda derrubaria a migração com erro, em vez de passar
--  batido.
-- ============================================================================

ALTER TABLE profissionais DROP CONSTRAINT IF EXISTS fk_profissionais_subcategoria_categoria;

UPDATE subcategorias
SET categoria_id = (SELECT categoria_id FROM categorias WHERE nome = 'Manutenção e Reformas (Lar)')
WHERE nome IN ('Chaveiro', 'Jardineiro', 'Piscineiro')
  AND categoria_id = (SELECT categoria_id FROM categorias WHERE nome = 'Outros Serviços');

UPDATE profissionais p
SET categoria_id = s.categoria_id
FROM subcategorias s
WHERE p.subcategoria_id = s.subcategoria_id
  AND s.nome IN ('Chaveiro', 'Jardineiro', 'Piscineiro');

ALTER TABLE profissionais
    ADD CONSTRAINT fk_profissionais_subcategoria_categoria
    FOREIGN KEY (subcategoria_id, categoria_id)
    REFERENCES subcategorias (subcategoria_id, categoria_id);


-- ============================================================================
--  SEÇÃO 4 - NOVA SUBCATEGORIA: Limpeza de Ar-Condicionado
-- ============================================================================

INSERT INTO subcategorias (categoria_id, nome)
SELECT c.categoria_id, 'Limpeza de Ar-Condicionado'
FROM categorias c
WHERE c.nome = 'Manutenção e Reformas (Lar)'
ON CONFLICT (categoria_id, nome) DO NOTHING;


-- ============================================================================
--  SEÇÃO 5 - RENOMEAR SUBCATEGORIAS (só o rótulo -- mesmo id, mesma
--            categoria; nenhuma linha de `profissionais` precisa mudar)
-- ============================================================================

-- Manutenção e Reformas (Lar)
UPDATE subcategorias s SET nome = 'Pedreiro / Alvenaria'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Manutenção e Reformas (Lar)' AND s.nome = 'Pedreiro';
UPDATE subcategorias s SET nome = 'Marceneiro / Montador de Móveis'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Manutenção e Reformas (Lar)' AND s.nome = 'Marceneiro';

-- Logística e Transporte
UPDATE subcategorias s SET nome = 'Motorista de Frete / Carreto'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Logística e Transporte' AND s.nome = 'Frete';
UPDATE subcategorias s SET nome = 'Motoboy / Entregador'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Logística e Transporte' AND s.nome = 'Motoboy';
UPDATE subcategorias s SET nome = 'Transporte de Pequenos Volumes'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Logística e Transporte' AND s.nome = 'Entrega de Pequenos Volumes';

-- Beleza e Bem-Estar
UPDATE subcategorias s SET nome = 'Manicure e Pedicure'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Beleza e Bem-Estar' AND s.nome = 'Manicure/Pedicure';

-- Tecnologia e Serviços Digitais
UPDATE subcategorias s SET nome = 'Desenvolvedor / Programador'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Tecnologia e Serviços Digitais' AND s.nome = 'Desenvolvedor';
UPDATE subcategorias s SET nome = 'Social Media / Gestor de Redes Sociais'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Tecnologia e Serviços Digitais' AND s.nome = 'Social Media';
UPDATE subcategorias s SET nome = 'Gestor de Tráfego Pago'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Tecnologia e Serviços Digitais' AND s.nome = 'Gestor de Tráfego';
UPDATE subcategorias s SET nome = 'Criador de Sites'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Tecnologia e Serviços Digitais' AND s.nome = 'Criação de Sites';
UPDATE subcategorias s SET nome = 'Suporte em Informática / Formatação'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Tecnologia e Serviços Digitais' AND s.nome = 'Suporte em TI';
UPDATE subcategorias s SET nome = 'Manutenção de Smartphones'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Tecnologia e Serviços Digitais' AND s.nome = 'Manutenção de Celulares';

-- Educação e Consultoria
UPDATE subcategorias s SET nome = 'Professor Particular (Idiomas, Reforço, Música)'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Educação e Consultoria' AND s.nome = 'Professor Particular';
UPDATE subcategorias s SET nome = 'Coach (Carreira, Relacionamento, Fitness)'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Educação e Consultoria' AND s.nome = 'Coach';

-- Alimentação e Eventos
UPDATE subcategorias s SET nome = 'Confeiteira / Bolo Caseiro'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Alimentação e Eventos' AND s.nome = 'Confeiteira';
UPDATE subcategorias s SET nome = 'Buffet / Cozinheiro Autônomo'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Alimentação e Eventos' AND s.nome = 'Buffet/Cozinheiro';
UPDATE subcategorias s SET nome = 'Cerimonialista / Organizador de Eventos'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Alimentação e Eventos' AND s.nome = 'Cerimonialista';

-- Outros Serviços (ex-"Serviços Gerais e Pet")
UPDATE subcategorias s SET nome = 'Pet Sitter / Passeador de Cães'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Outros Serviços' AND s.nome = 'Pet Sitter';
UPDATE subcategorias s SET nome = 'Diarista / Faxineiro'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Outros Serviços' AND s.nome = 'Diarista';
UPDATE subcategorias s SET nome = 'Passadeira de Roupas'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Outros Serviços' AND s.nome = 'Passadeira';
UPDATE subcategorias s SET nome = 'Lavagem de Estofados / Automotiva'
    FROM categorias c WHERE s.categoria_id = c.categoria_id
    AND c.nome = 'Outros Serviços' AND s.nome = 'Lavagem de Estofados';


COMMIT;


-- ============================================================================
--  SEÇÃO 6 - VERIFICAÇÃO
-- ============================================================================

DO $$
DECLARE
    total_manutencao INT;
    total_outros_servicos INT;
BEGIN
    SELECT COUNT(*) INTO total_manutencao
    FROM subcategorias s JOIN categorias c ON c.categoria_id = s.categoria_id
    WHERE c.nome = 'Manutenção e Reformas (Lar)';

    SELECT COUNT(*) INTO total_outros_servicos
    FROM subcategorias s JOIN categorias c ON c.categoria_id = s.categoria_id
    WHERE c.nome = 'Outros Serviços';

    RAISE NOTICE '---------------------------------------------';
    RAISE NOTICE ' Migracao 13 aplicada com sucesso.';
    RAISE NOTICE ' "Manutencao e Reformas (Lar)": % subcategorias (era 10, +Chaveiro +Jardineiro +Piscineiro +Limpeza de Ar-Condicionado = 14)', total_manutencao;
    RAISE NOTICE ' "Outros Servicos" (ex-Servicos Gerais e Pet): % subcategorias (era 10, -Chaveiro -Jardineiro -Piscineiro = 7)', total_outros_servicos;
    RAISE NOTICE '---------------------------------------------';
END $$;
