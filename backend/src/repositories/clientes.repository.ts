import { pool } from '../database';

/* ============================================================================
   Camada de acesso a dados do CLIENTE -- espelha profissionais.repository.ts
   (mesmo padrão: interface "o que sai daqui", SELECT/UPDATE com COALESCE
   para atualização parcial). Ver comentários mais detalhados lá; aqui só
   repetimos o que é específico de `clientes`.
   ========================================================================= */

/**
 * Perfil PRIVADO do cliente -- só o próprio cliente vê isso (rota exige
 * `exigirAutenticacao` + `exigirPapel('cliente')`, e o ID usado é sempre
 * `req.usuario.sub`, nunca um `:id` da URL). Por isso, diferente do perfil
 * PÚBLICO do profissional, aqui `email` pode aparecer sem problema -- não
 * existe risco de scraping quando só o dono do token acessa.
 */
export interface PerfilCliente {
  cliente_id: string;
  tipo_pessoa: 'PF' | 'PJ';
  nome_exibicao: string;
  email: string;
  contato: string;
  endereco: string | null;
  url_foto_perfil: string | null;
  latitude: number | null;
  longitude: number | null;
}

/**
 * Busca os dados do PRÓPRIO cliente logado -- usado por GET /clientes/me.
 */
export async function buscarMeuPerfil(clienteId: string): Promise<PerfilCliente | null> {
  const { rows } = await pool.query<PerfilCliente>(
    `SELECT
       cliente_id,
       tipo_pessoa,
       COALESCE(nome, razao_social) AS nome_exibicao,
       email,
       contato,
       endereco,
       url_foto_perfil,
       latitude,
       longitude
     FROM clientes
     WHERE cliente_id = $1`,
    [clienteId],
  );
  return rows[0] ?? null;
}

/** O que a rota de edição entrega. `undefined` num campo = "não mexa nele". */
export interface AtualizacaoPerfilCliente {
  contato?: string;
  endereco?: string;
  urlFotoPerfil?: string;
}

/**
 * Atualiza `contato`, `endereco` e/ou `url_foto_perfil` de UM cliente --
 * sempre o DONO DO TOKEN (mesma regra de `atualizarPerfilProfissional`: o
 * `:id` não existe aqui, a rota só chama isto com `req.usuario.sub`).
 *
 * `COALESCE($n, coluna)`: campo `undefined` vira parâmetro `NULL`, e o
 * COALESCE preserva o valor que já estava gravado -- atualização parcial
 * sem montar SQL dinâmico.
 */
export async function atualizarMeuPerfil(
  clienteId: string,
  dados: AtualizacaoPerfilCliente,
): Promise<PerfilCliente> {
  const { rows } = await pool.query<PerfilCliente>(
    `UPDATE clientes
        SET contato          = COALESCE($2, contato),
            endereco         = COALESCE($3, endereco),
            url_foto_perfil  = COALESCE($4, url_foto_perfil)
      WHERE cliente_id = $1
      RETURNING
        cliente_id,
        tipo_pessoa,
        COALESCE(nome, razao_social) AS nome_exibicao,
        email,
        contato,
        endereco,
        url_foto_perfil,
        latitude,
        longitude`,
    [clienteId, dados.contato ?? null, dados.endereco ?? null, dados.urlFotoPerfil ?? null],
  );
  return rows[0];
}
