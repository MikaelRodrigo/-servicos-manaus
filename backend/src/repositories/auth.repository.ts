import { pool } from '../database';

/* ============================================================================
   Por que este repository fala com DUAS tabelas (clientes e profissionais)
   em vez de uma tabela "usuarios" única?

   Porque o schema da Etapa 1 já decidiu isso: cliente e profissional são
   entidades diferentes, com colunas diferentes (profissao/categoria_atuacao
   só existe em profissionais, por exemplo). O "papel" da pessoa não é uma
   coluna -- é a tabela em que ela está. Uma mesma pessoa PODE, inclusive,
   ter uma conta de cliente E uma de profissional com o mesmo e-mail; são
   linhas em tabelas diferentes, o UNIQUE(email) de cada tabela não colide
   entre si.
   ========================================================================= */

export interface UsuarioAutenticavel {
  id: string;
  email: string;
  senha_hash: string;
  nome_exibicao: string;
}

/**
 * Reexportado por conveniência: quem já importava `PG_UNIQUE_VIOLATION`
 * daqui (auth.routes.ts) continua funcionando. A partir da Etapa "Serviços"
 * a fonte da verdade é `utils/erros-postgres.ts` -- é lá que também mora
 * `PG_FOREIGN_KEY_VIOLATION`, usado por `servicos.repository.ts`.
 */
export { PG_UNIQUE_VIOLATION } from '../utils/erros-postgres';

// ---------------------------------------------------------------------------
// LOGIN: buscar por e-mail
// ---------------------------------------------------------------------------

export async function buscarClientePorEmail(email: string): Promise<UsuarioAutenticavel | null> {
  const { rows } = await pool.query<UsuarioAutenticavel>(
    `SELECT cliente_id AS id, email, senha_hash, COALESCE(nome, razao_social) AS nome_exibicao
       FROM clientes
      WHERE email = $1`,
    [email],
  );
  return rows[0] ?? null;
}

export async function buscarProfissionalPorEmail(
  email: string,
): Promise<UsuarioAutenticavel | null> {
  const { rows } = await pool.query<UsuarioAutenticavel>(
    `SELECT profissional_id AS id, email, senha_hash, COALESCE(nome, razao_social) AS nome_exibicao
       FROM profissionais
      WHERE email = $1`,
    [email],
  );
  return rows[0] ?? null;
}

// ---------------------------------------------------------------------------
// CADASTRO: clientes
// ---------------------------------------------------------------------------

export interface DadosClientePF {
  email: string;
  senhaHash: string;
  contato: string;
  nome: string;
  cpf: string;
  latitude?: number;
  longitude?: number;
}

export interface DadosClientePJ {
  email: string;
  senhaHash: string;
  contato: string;
  razaoSocial: string;
  cnpj: string;
  dataCriacao?: string;
  latitude?: number;
  longitude?: number;
}

export async function criarClientePF(dados: DadosClientePF): Promise<{ id: string }> {
  const { rows } = await pool.query<{ cliente_id: string }>(
    `INSERT INTO clientes (tipo_pessoa, email, senha_hash, contato, nome, cpf, latitude, longitude)
     VALUES ('PF', $1, $2, $3, $4, $5, $6, $7)
     RETURNING cliente_id`,
    [
      dados.email,
      dados.senhaHash,
      dados.contato,
      dados.nome,
      dados.cpf,
      dados.latitude ?? null,
      dados.longitude ?? null,
    ],
  );
  return { id: rows[0].cliente_id };
}

export async function criarClientePJ(dados: DadosClientePJ): Promise<{ id: string }> {
  const { rows } = await pool.query<{ cliente_id: string }>(
    `INSERT INTO clientes (tipo_pessoa, email, senha_hash, contato, razao_social, cnpj, data_criacao, latitude, longitude)
     VALUES ('PJ', $1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING cliente_id`,
    [
      dados.email,
      dados.senhaHash,
      dados.contato,
      dados.razaoSocial,
      dados.cnpj,
      dados.dataCriacao ?? null,
      dados.latitude ?? null,
      dados.longitude ?? null,
    ],
  );
  return { id: rows[0].cliente_id };
}

// ---------------------------------------------------------------------------
// CADASTRO: profissionais
// ---------------------------------------------------------------------------

export interface DadosProfissionalPF {
  email: string;
  senhaHash: string;
  contato: string;
  nome: string;
  cpf: string;
  dataNascimento: string;
  /** IDs de categorias/subcategorias.repository.ts (migração 09) -- sempre juntos, sempre obrigatórios. */
  categoriaId: number;
  subcategoriaId: number;
  latitude?: number;
  longitude?: number;
}

export interface DadosProfissionalPJ {
  email: string;
  senhaHash: string;
  contato: string;
  razaoSocial: string;
  cnpj: string;
  /** IDs de categorias/subcategorias.repository.ts (migração 09) -- sempre juntos, sempre obrigatórios. */
  categoriaId: number;
  subcategoriaId: number;
  dataCriacao?: string;
  latitude?: number;
  longitude?: number;
}

export async function criarProfissionalPF(
  dados: DadosProfissionalPF,
): Promise<{ id: string }> {
  const { rows } = await pool.query<{ profissional_id: string }>(
    `INSERT INTO profissionais
       (tipo_pessoa, email, senha_hash, contato, nome, cpf, data_nascimento, categoria_id, subcategoria_id, latitude, longitude)
     VALUES ('PF', $1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     RETURNING profissional_id`,
    [
      dados.email,
      dados.senhaHash,
      dados.contato,
      dados.nome,
      dados.cpf,
      dados.dataNascimento,
      dados.categoriaId,
      dados.subcategoriaId,
      dados.latitude ?? null,
      dados.longitude ?? null,
    ],
  );
  return { id: rows[0].profissional_id };
}

export async function criarProfissionalPJ(
  dados: DadosProfissionalPJ,
): Promise<{ id: string }> {
  const { rows } = await pool.query<{ profissional_id: string }>(
    `INSERT INTO profissionais
       (tipo_pessoa, email, senha_hash, contato, razao_social, cnpj, categoria_id, subcategoria_id, data_criacao, latitude, longitude)
     VALUES ('PJ', $1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
     RETURNING profissional_id`,
    [
      dados.email,
      dados.senhaHash,
      dados.contato,
      dados.razaoSocial,
      dados.cnpj,
      dados.categoriaId,
      dados.subcategoriaId,
      dados.dataCriacao ?? null,
      dados.latitude ?? null,
      dados.longitude ?? null,
    ],
  );
  return { id: rows[0].profissional_id };
}
