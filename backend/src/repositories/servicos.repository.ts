import { pool } from '../database';
import { StatusServico } from '../utils/validacao';

/* ============================================================================
   O QUE ESTE ARQUIVO FAZ

   `servicos` é a tabela-ponte do sistema inteiro: sem um serviço CONCLUIDO,
   ninguém avalia ninguém (o schema já garante isso com um trigger). Este
   repository implementa a MÁQUINA DE ESTADOS do serviço:

     SOLICITADO --(profissional aceita)--> ACEITO
     SOLICITADO --(profissional recusa)--> RECUSADO
     ACEITO     --(profissional inicia)--> EM_ANDAMENTO
     EM_ANDAMENTO --(profissional conclui)--> CONCLUIDO
     SOLICITADO | ACEITO | EM_ANDAMENTO --(cliente OU profissional cancela)--> CANCELADO

   Cada função de transição faz um UPDATE ... WHERE id_servico = $1 AND
   status = 'ESTADO_ATUAL_ESPERADO' -- isso é uma ATUALIZAÇÃO ATÔMICA
   CONDICIONAL. Ela resolve, de graça, um problema clássico de concorrência
   (TOCTOU -- "time of check to time of use"): se dois profissionais
   diferentes (ou duas abas do mesmo app) tentassem aceitar o MESMO serviço
   ao mesmo tempo, só o primeiro UPDATE encontraria a linha ainda com status
   'SOLICITADO'; o segundo não atualiza nenhuma linha (rowCount = 0), e a
   rota (servicos.routes.ts) sabe que precisa recusar com um erro claro, em
   vez de deixar os dois "vencerem".
   ========================================================================= */

export interface Servico {
  id_servico: string;
  cliente_id: string;
  profissional_id: string;
  status: StatusServico;
  descricao: string | null;
  /** Especialidade contratada -- ver migração 12. Sempre presente em serviços novos. */
  categoria_id: number | null;
  categoria_nome: string | null;
  subcategoria_id: number | null;
  subcategoria_nome: string | null;
  data: string;
  data_conclusao: string | null;
  created_at: string;
  updated_at: string;
  cliente_nome: string;
  profissional_nome: string;
}

const SELECT_SERVICO_BASE = `
  SELECT
    s.id_servico,
    s.cliente_id,
    s.profissional_id,
    s.status,
    s.descricao,
    s.categoria_id,
    cat.nome AS categoria_nome,
    s.subcategoria_id,
    sub.nome AS subcategoria_nome,
    s.data,
    s.data_conclusao,
    s.created_at,
    s.updated_at,
    COALESCE(c.nome, c.razao_social) AS cliente_nome,
    COALESCE(p.nome, p.razao_social) AS profissional_nome
  FROM servicos s
  JOIN clientes c      ON c.cliente_id      = s.cliente_id
  JOIN profissionais p ON p.profissional_id = s.profissional_id
  LEFT JOIN categorias cat    ON cat.categoria_id    = s.categoria_id
  LEFT JOIN subcategorias sub ON sub.subcategoria_id = s.subcategoria_id
`;

/** Busca um serviço por id, já com os nomes de exibição do cliente e do profissional. */
export async function buscarServicoPorId(idServico: string): Promise<Servico | null> {
  const { rows } = await pool.query<Servico>(
    `${SELECT_SERVICO_BASE} WHERE s.id_servico = $1`,
    [idServico],
  );
  return rows[0] ?? null;
}

export interface FiltroListaServicos {
  status?: StatusServico;
  limite: number;
  offset: number;
}

/** Serviços em que a pessoa é a CLIENTE. Usado por GET /servicos/meus. */
export async function listarServicosDoCliente(
  clienteId: string,
  filtro: FiltroListaServicos,
): Promise<Servico[]> {
  const { rows } = await pool.query<Servico>(
    `${SELECT_SERVICO_BASE}
      WHERE s.cliente_id = $1
        AND ($2::status_servico_enum IS NULL OR s.status = $2::status_servico_enum)
      ORDER BY s.data DESC
      LIMIT $3 OFFSET $4`,
    [clienteId, filtro.status ?? null, filtro.limite, filtro.offset],
  );
  return rows;
}

/** Serviços em que a pessoa é a PROFISSIONAL. Usado por GET /servicos/meus. */
export async function listarServicosDoProfissional(
  profissionalId: string,
  filtro: FiltroListaServicos,
): Promise<Servico[]> {
  const { rows } = await pool.query<Servico>(
    `${SELECT_SERVICO_BASE}
      WHERE s.profissional_id = $1
        AND ($2::status_servico_enum IS NULL OR s.status = $2::status_servico_enum)
      ORDER BY s.data DESC
      LIMIT $3 OFFSET $4`,
    [profissionalId, filtro.status ?? null, filtro.limite, filtro.offset],
  );
  return rows;
}

/**
 * Cria o serviço (o cliente "solicita"). O status nasce 'SOLICITADO' pelo
 * DEFAULT da coluna no banco -- não precisamos (nem devemos) escrever isso
 * aqui, é o schema quem manda nessa regra.
 *
 * `categoriaId`/`subcategoriaId` -- QUAL especialidade do profissional está
 * sendo contratada (ver migração 12). A rota (servicos.routes.ts) exige os
 * dois em todo serviço NOVO; aqui eles chegam sempre juntos. Se o par não
 * bater com uma linha real de `subcategorias`, ou se a subcategoria não for
 * de fato uma tag do profissional (ver CHECK via trigger não existente --
 * hoje isso é validado a mais, na rota, contra `profissional_subcategorias`),
 * o Postgres recusa com FOREIGN KEY VIOLATION.
 *
 * Se `profissional_id` não existir, o Postgres recusa com FOREIGN KEY
 * VIOLATION (código 23503) -- é a rota (servicos.routes.ts) quem traduz
 * isso para um 404 amigável.
 */
export async function criarServico(dados: {
  clienteId: string;
  profissionalId: string;
  descricao?: string;
  categoriaId: number;
  subcategoriaId: number;
}): Promise<Servico> {
  const { rows } = await pool.query<{ id_servico: string }>(
    `INSERT INTO servicos (cliente_id, profissional_id, descricao, categoria_id, subcategoria_id)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id_servico`,
    [
      dados.clienteId,
      dados.profissionalId,
      dados.descricao ?? null,
      dados.categoriaId,
      dados.subcategoriaId,
    ],
  );

  // Reconsultamos para devolver também cliente_nome/profissional_nome --
  // o INSERT sozinho não tem acesso a essas colunas (são de OUTRA tabela).
  const servico = await buscarServicoPorId(rows[0].id_servico);
  // Não pode ser null: acabamos de inserir esta linha nesta mesma transação implícita.
  return servico as Servico;
}

/**
 * true se o UPDATE encontrou e alterou a linha; false se o estado/dono não bateram.
 *
 * Repare que `colunaDono` é interpolado DIRETO na string SQL (`${colunaDono}`),
 * não vira `$N`. Isso pareceria quebrar a regra de ouro ("nunca concatene
 * SQL") -- mas não quebra, porque `colunaDono` NUNCA vem do usuário. O tipo
 * `'cliente_id' | 'profissional_id'` é decidido em TEMPO DE COMPILAÇÃO pelas
 * funções abaixo (aceitarServico, cancelarServicoComoCliente, etc.), nunca
 * por `req.body` ou `req.query`. Regra prática: placeholder ($N) é para
 * VALORES; interpolação de string só é aceitável para nomes de coluna/tabela
 * que o PRÓPRIO CÓDIGO escolhe, nunca para algo que atravessou a rede.
 */
async function atualizarStatusCondicional(
  idServico: string,
  colunaDono: 'cliente_id' | 'profissional_id',
  donoId: string,
  statusAtualEsperado: StatusServico | StatusServico[],
  novoStatus: StatusServico,
  marcarConclusao = false,
): Promise<boolean> {
  const listaStatusEsperados = Array.isArray(statusAtualEsperado)
    ? statusAtualEsperado
    : [statusAtualEsperado];

  const sql = `
    UPDATE servicos
       SET status = $1::status_servico_enum
           ${marcarConclusao ? ', data_conclusao = NOW()' : ''}
     WHERE id_servico = $2
       AND ${colunaDono} = $3
       AND status = ANY($4::status_servico_enum[])
  `;

  const { rowCount } = await pool.query(sql, [
    novoStatus,
    idServico,
    donoId,
    listaStatusEsperados,
  ]);

  return (rowCount ?? 0) > 0;
}

// ---------------------------------------------------------------------------
// TRANSIÇÕES -- todas exigidas pelo PROFISSIONAL dono do serviço,
// exceto o cancelamento, que qualquer um dos dois lados pode fazer.
// ---------------------------------------------------------------------------

export function aceitarServico(idServico: string, profissionalId: string): Promise<boolean> {
  return atualizarStatusCondicional(
    idServico,
    'profissional_id',
    profissionalId,
    'SOLICITADO',
    'ACEITO',
  );
}

export function recusarServico(idServico: string, profissionalId: string): Promise<boolean> {
  return atualizarStatusCondicional(
    idServico,
    'profissional_id',
    profissionalId,
    'SOLICITADO',
    'RECUSADO',
  );
}

export function iniciarServico(idServico: string, profissionalId: string): Promise<boolean> {
  return atualizarStatusCondicional(
    idServico,
    'profissional_id',
    profissionalId,
    'ACEITO',
    'EM_ANDAMENTO',
  );
}

export function concluirServico(idServico: string, profissionalId: string): Promise<boolean> {
  return atualizarStatusCondicional(
    idServico,
    'profissional_id',
    profissionalId,
    'EM_ANDAMENTO',
    'CONCLUIDO',
    /* marcarConclusao */ true,
  );
}

const STATUS_CANCELAVEIS: StatusServico[] = ['SOLICITADO', 'ACEITO', 'EM_ANDAMENTO'];

export function cancelarServicoComoCliente(idServico: string, clienteId: string): Promise<boolean> {
  return atualizarStatusCondicional(
    idServico,
    'cliente_id',
    clienteId,
    STATUS_CANCELAVEIS,
    'CANCELADO',
  );
}

export function cancelarServicoComoProfissional(
  idServico: string,
  profissionalId: string,
): Promise<boolean> {
  return atualizarStatusCondicional(
    idServico,
    'profissional_id',
    profissionalId,
    STATUS_CANCELAVEIS,
    'CANCELADO',
  );
}
