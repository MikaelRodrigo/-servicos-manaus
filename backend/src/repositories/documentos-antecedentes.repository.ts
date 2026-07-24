import { pool } from '../database';

/* ============================================================================
   Certidão de antecedentes criminais (migração 18 --
   18_certidao_antecedentes_criminais.sql).

   `chave_s3` NUNCA sai deste repository para uma resposta JSON comum --
   só as funções `buscarChaveParaDono`/`buscarChaveParaAdmin` (usadas pelas
   duas rotas "/arquivo", que transmitem os bytes) leem essa coluna. Ver
   comentário no topo da migração sobre por que este documento não usa URL
   pública.
   ========================================================================= */

export type StatusDocumentoAntecedentes = 'PENDENTE' | 'APROVADO' | 'REJEITADO';

/** Formato devolvido pra quem só precisa saber O STATUS (o próprio profissional, ou a listagem do admin) -- sem `chave_s3`. */
export interface DocumentoAntecedentes {
  id: string;
  profissional_id: string;
  status: StatusDocumentoAntecedentes;
  palavras_chave_encontradas: string[];
  nome_encontrado: boolean | null;
  cpf_encontrado: boolean | null;
  motivo_rejeicao: string | null;
  revisado_em: string | null;
  created_at: string;
}

const COLUNAS_SEM_CHAVE = `
  id, profissional_id, status, palavras_chave_encontradas,
  nome_encontrado, cpf_encontrado, motivo_rejeicao, revisado_em, created_at
`;

/**
 * Dados do PRÓPRIO profissional usados na checagem automática (nome/CPF
 * JÁ CADASTRADOS -- nunca digitados de novo no envio do documento). `cpf`
 * vem `null` para profissional PJ: o schema (`database/01_schema_2.sql`)
 * não guarda CPF de responsável legal para pessoa jurídica, só CNPJ da
 * empresa -- e antecedentes criminais é um conceito de PESSOA FÍSICA. Para
 * PJ, a checagem de nome/CPF fica "não aplicável" (ver checagem-documento.ts)
 * e o documento vai direto pra revisão manual.
 */
export async function buscarDadosParaChecagem(
  profissionalId: string,
): Promise<{ nome: string; cpf: string | null } | null> {
  const { rows } = await pool.query<{ nome: string; cpf: string | null }>(
    `SELECT COALESCE(nome, razao_social) AS nome, cpf
       FROM profissionais
      WHERE profissional_id = $1`,
    [profissionalId],
  );
  return rows[0] ?? null;
}

/**
 * Grava um envio novo (cadastro inicial ou reenvio depois de rejeição --
 * cada chamada INSERE uma linha nova, nunca sobrescreve, ver comentário da
 * tabela na migração). SEMPRE reseta `profissionais.antecedentes_verificados`
 * para `FALSE` -- um envio novo, seja qual for o resultado da checagem
 * automática, nunca deve deixar o profissional visível no mapa "de
 * herança" de uma aprovação de um documento ANTERIOR. Só volta a `TRUE`
 * quando ESTE envio for aprovado por um admin (ver `aprovarDocumento`).
 */
export async function inserirDocumento(dados: {
  profissionalId: string;
  chaveS3: string;
  tipoMime: string;
  status: StatusDocumentoAntecedentes;
  palavrasChaveEncontradas: string[];
  nomeEncontrado: boolean | null;
  cpfEncontrado: boolean | null;
  motivoRejeicao: string | null;
}): Promise<DocumentoAntecedentes> {
  const { rows } = await pool.query<DocumentoAntecedentes>(
    `INSERT INTO documentos_antecedentes
       (profissional_id, chave_s3, tipo_mime, status, palavras_chave_encontradas, nome_encontrado, cpf_encontrado, motivo_rejeicao)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING ${COLUNAS_SEM_CHAVE}`,
    [
      dados.profissionalId,
      dados.chaveS3,
      dados.tipoMime,
      dados.status,
      dados.palavrasChaveEncontradas,
      dados.nomeEncontrado,
      dados.cpfEncontrado,
      dados.motivoRejeicao,
    ],
  );

  await pool.query(
    `UPDATE profissionais SET antecedentes_verificados = FALSE WHERE profissional_id = $1`,
    [dados.profissionalId],
  );

  return rows[0];
}

/** O envio MAIS RECENTE do profissional logado -- usado por `GET /profissionais/me/documento-antecedentes`. `null` se ele nunca enviou nenhum. */
export async function buscarUltimoDocumento(
  profissionalId: string,
): Promise<DocumentoAntecedentes | null> {
  const { rows } = await pool.query<DocumentoAntecedentes>(
    `SELECT ${COLUNAS_SEM_CHAVE}
       FROM documentos_antecedentes
      WHERE profissional_id = $1
      ORDER BY created_at DESC
      LIMIT 1`,
    [profissionalId],
  );
  return rows[0] ?? null;
}

/** Chave S3 do envio mais recente do PRÓPRIO profissional -- posse garantida no WHERE (mesmo espírito de `removerFotoPortfolio`), não só checada na rota. Usada por `GET /profissionais/me/documento-antecedentes/arquivo`. */
export async function buscarChaveParaDono(
  profissionalId: string,
): Promise<{ chaveS3: string; tipoMime: string } | null> {
  const { rows } = await pool.query<{ chave_s3: string; tipo_mime: string }>(
    `SELECT chave_s3, tipo_mime
       FROM documentos_antecedentes
      WHERE profissional_id = $1
      ORDER BY created_at DESC
      LIMIT 1`,
    [profissionalId],
  );
  if (!rows[0]) return null;
  return { chaveS3: rows[0].chave_s3, tipoMime: rows[0].tipo_mime };
}

/** Mesma ideia, para o ADMIN revisando um envio específico da fila (por isso recebe `id`, não `profissionalId` -- o admin pode olhar o documento de QUALQUER profissional). Autorização de papel já é responsabilidade da rota (`exigirPapel('admin')`), não deste repository. */
export async function buscarChaveParaAdmin(
  id: string,
): Promise<{ chaveS3: string; tipoMime: string } | null> {
  const { rows } = await pool.query<{ chave_s3: string; tipo_mime: string }>(
    `SELECT chave_s3, tipo_mime FROM documentos_antecedentes WHERE id = $1`,
    [id],
  );
  if (!rows[0]) return null;
  return { chaveS3: rows[0].chave_s3, tipoMime: rows[0].tipo_mime };
}

/** Item da fila de revisão do admin -- inclui o nome do profissional (join), pra não precisar de uma segunda chamada só pra identificar quem é. */
export interface ItemFilaAdmin extends DocumentoAntecedentes {
  nome_profissional: string;
  tipo_pessoa: 'PF' | 'PJ';
}

/** Fila de documentos PENDENTES, do mais ANTIGO pro mais novo (FIFO -- quem mandou primeiro é revisado primeiro). */
export async function listarPendentes(): Promise<ItemFilaAdmin[]> {
  const { rows } = await pool.query<ItemFilaAdmin>(
    `SELECT
       d.id, d.profissional_id, d.status, d.palavras_chave_encontradas,
       d.nome_encontrado, d.cpf_encontrado, d.motivo_rejeicao, d.revisado_em, d.created_at,
       COALESCE(p.nome, p.razao_social) AS nome_profissional,
       p.tipo_pessoa
     FROM documentos_antecedentes d
     JOIN profissionais p ON p.profissional_id = d.profissional_id
    WHERE d.status = 'PENDENTE'
    ORDER BY d.created_at ASC`,
  );
  return rows;
}

/**
 * Aprova o documento `id` -- SÓ SE ele ainda estiver PENDENTE (evita
 * aprovar duas vezes, ou aprovar algo já rejeitado). Numa operação lógica
 * só (CTE encadeada, mesmo padrão de `criarProfissionalPF`): marca o
 * documento como APROVADO E liga `profissionais.antecedentes_verificados`
 * -- ou as duas coisas acontecem, ou nenhuma.
 *
 * Devolve `null` se `id` não existir ou já tiver sido revisado antes (a
 * rota trata isso como 404/409, nunca deixa reaprovar silenciosamente).
 */
export async function aprovarDocumento(
  id: string,
  adminId: string,
): Promise<{ profissionalId: string } | null> {
  const { rows } = await pool.query<{ profissional_id: string }>(
    `WITH atualizado AS (
       UPDATE documentos_antecedentes
          SET status = 'APROVADO', revisado_por = $2, revisado_em = NOW()
        WHERE id = $1 AND status = 'PENDENTE'
       RETURNING profissional_id
     )
     UPDATE profissionais
        SET antecedentes_verificados = TRUE
       FROM atualizado
      WHERE profissionais.profissional_id = atualizado.profissional_id
     RETURNING profissionais.profissional_id`,
    [id, adminId],
  );
  if (!rows[0]) return null;
  return { profissionalId: rows[0].profissional_id };
}

/**
 * Rejeita o documento `id` -- só se ainda estiver PENDENTE. NÃO mexe em
 * `antecedentes_verificados` (rejeição não revoga uma aprovação anterior
 * de ENVIO diferente -- só existe algo pra revogar se o envio rejeitado
 * fosse o mais recente, e nesse caso ele já estava com `antecedentes_verificados
 * = FALSE` desde o próprio envio, ver `inserirDocumento`).
 */
export async function rejeitarDocumento(
  id: string,
  adminId: string,
  motivo: string,
): Promise<boolean> {
  const resultado = await pool.query(
    `UPDATE documentos_antecedentes
        SET status = 'REJEITADO', motivo_rejeicao = $3, revisado_por = $2, revisado_em = NOW()
      WHERE id = $1 AND status = 'PENDENTE'`,
    [id, adminId, motivo],
  );
  return (resultado.rowCount ?? 0) > 0;
}
