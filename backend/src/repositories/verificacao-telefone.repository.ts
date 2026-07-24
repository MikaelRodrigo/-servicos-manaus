import crypto from 'crypto';
import { pool } from '../database';
import { ErroDeValidacao, ErroNaoEncontrado } from '../utils/validacao';
import { gerarCodigoDeVerificacao, enviarCodigoPorSms, ResultadoEnvioSms } from '../services/sms';

/* ============================================================================
   Verificação de telefone por SMS (migração 17 --
   17_verificacao_telefone.sql).

   Este repository é o único lugar que sabe o formato da tabela
   `codigos_verificacao_telefone` e como ela se relaciona com `clientes`/
   `profissionais` -- a rota (`routes/auth.routes.ts`) só chama as três
   funções exportadas abaixo, nunca monta SQL diretamente.
   ========================================================================= */

export type PapelVerificavel = 'cliente' | 'profissional';

/** Quanto tempo um código vale, a partir do envio. */
const MINUTOS_VALIDADE_CODIGO = 10;

/** Tentativas de confirmação ERRADAS permitidas para um mesmo código, antes dele virar inválido. */
const MAX_TENTATIVAS_CODIGO = 5;

/**
 * Intervalo mínimo entre dois envios para a MESMA pessoa -- evita que um
 * toque duplo em "reenviar" (ou um script malicioso) esgote a cota do
 * provedor de SMS gerando dezenas de códigos por segundo.
 */
const SEGUNDOS_ENTRE_ENVIOS = 20;

/** SHA-256 do código -- nunca gravamos o código em texto puro (mesmo espírito de nunca guardar senha em texto puro). Não é bcrypt de propósito: o código já expira sozinho em minutos, não precisa do custo computacional de um hash de senha. */
function hashCodigo(codigo: string): string {
  return crypto.createHash('sha256').update(codigo).digest('hex');
}

/**
 * Busca o `contato` (telefone) de quem vai receber o SMS -- direto na
 * tabela certa, conforme `papel`. Devolve `null` se o `usuarioId` não
 * existir naquela tabela (a rota decide o que fazer -- normalmente vira
 * `ErroNaoEncontrado`).
 */
async function buscarContato(papel: PapelVerificavel, usuarioId: string): Promise<string | null> {
  const tabela = papel === 'cliente' ? 'clientes' : 'profissionais';
  const coluna = papel === 'cliente' ? 'cliente_id' : 'profissional_id';

  const { rows } = await pool.query<{ contato: string }>(
    `SELECT contato FROM ${tabela} WHERE ${coluna} = $1`,
    [usuarioId],
  );
  return rows[0]?.contato ?? null;
}

/**
 * Marca `telefone_verificado = TRUE` na tabela certa. Chamada só depois de
 * `confirmarCodigo` aceitar o código.
 */
async function marcarTelefoneVerificado(papel: PapelVerificavel, usuarioId: string): Promise<void> {
  const tabela = papel === 'cliente' ? 'clientes' : 'profissionais';
  const coluna = papel === 'cliente' ? 'cliente_id' : 'profissional_id';

  await pool.query(`UPDATE ${tabela} SET telefone_verificado = TRUE WHERE ${coluna} = $1`, [
    usuarioId,
  ]);
}

/**
 * Gera um código novo, grava o HASH dele no banco e manda por SMS (real ou
 * simulado, ver services/sms.ts). Chamada em TRÊS lugares:
 *   1. logo depois de um cadastro bem-sucedido (POST /auth/cadastro/*);
 *   2. quando um login é bloqueado por telefone não verificado (garante um
 *      código fresco mesmo que o da hora do cadastro já tenha expirado);
 *   3. na rota explícita de reenvio (POST /auth/verificar-telefone/reenviar).
 *
 * Lança `ErroDeValidacao` se a pessoa pediu um código há menos de
 * `SEGUNDOS_ENTRE_ENVIOS` -- proteção contra spam de reenvio.
 */
export async function gerarEEnviarCodigo(
  papel: PapelVerificavel,
  usuarioId: string,
): Promise<ResultadoEnvioSms> {
  const contato = await buscarContato(papel, usuarioId);
  if (!contato) {
    throw new ErroNaoEncontrado('Usuário não encontrado para envio do código de verificação.');
  }

  const { rows: ultimoEnvio } = await pool.query<{ created_at: Date }>(
    `SELECT created_at FROM codigos_verificacao_telefone
      WHERE papel = $1 AND usuario_id = $2
      ORDER BY created_at DESC
      LIMIT 1`,
    [papel, usuarioId],
  );
  if (ultimoEnvio[0]) {
    const segundosDesdeUltimoEnvio = (Date.now() - new Date(ultimoEnvio[0].created_at).getTime()) / 1000;
    if (segundosDesdeUltimoEnvio < SEGUNDOS_ENTRE_ENVIOS) {
      const faltam = Math.ceil(SEGUNDOS_ENTRE_ENVIOS - segundosDesdeUltimoEnvio);
      throw new ErroDeValidacao(`Aguarde ${faltam} segundo(s) antes de pedir um novo código.`);
    }
  }

  const codigo = gerarCodigoDeVerificacao();
  const expiraEm = new Date(Date.now() + MINUTOS_VALIDADE_CODIGO * 60 * 1000);

  await pool.query(
    `INSERT INTO codigos_verificacao_telefone (papel, usuario_id, codigo_hash, expira_em)
     VALUES ($1, $2, $3, $4)`,
    [papel, usuarioId, hashCodigo(codigo), expiraEm],
  );

  return enviarCodigoPorSms(contato, codigo);
}

/**
 * Confirma um código digitado pela pessoa. Regras, na ordem:
 *   1. precisa existir um código NÃO USADO e DENTRO DA VALIDADE para este
 *      usuário (o mais recente, se houver mais de um pedido de reenvio);
 *   2. esse código não pode ter estourado `MAX_TENTATIVAS_CODIGO` erros;
 *   3. o hash do código digitado precisa bater com o gravado.
 *
 * Em caso de erro (2) ou (3), incrementa `tentativas` antes de lançar --
 * é o que faz o contador de fato proteger contra força bruta. Em caso de
 * sucesso, marca `usado_em` (o código não pode ser reaproveitado) E marca
 * `telefone_verificado = TRUE` na mesma operação lógica.
 */
export async function confirmarCodigo(
  papel: PapelVerificavel,
  usuarioId: string,
  codigo: string,
): Promise<void> {
  const { rows } = await pool.query<{
    id: string;
    codigo_hash: string;
    tentativas: number;
  }>(
    `SELECT id, codigo_hash, tentativas
       FROM codigos_verificacao_telefone
      WHERE papel = $1 AND usuario_id = $2
        AND usado_em IS NULL
        AND expira_em > NOW()
      ORDER BY created_at DESC
      LIMIT 1`,
    [papel, usuarioId],
  );
  const pendente = rows[0];

  if (!pendente) {
    throw new ErroDeValidacao('Código expirado ou inexistente. Solicite um novo código.');
  }

  if (pendente.tentativas >= MAX_TENTATIVAS_CODIGO) {
    throw new ErroDeValidacao('Muitas tentativas erradas. Solicite um novo código.');
  }

  if (pendente.codigo_hash !== hashCodigo(codigo)) {
    await pool.query(
      `UPDATE codigos_verificacao_telefone SET tentativas = tentativas + 1 WHERE id = $1`,
      [pendente.id],
    );
    throw new ErroDeValidacao('Código incorreto.');
  }

  await pool.query(`UPDATE codigos_verificacao_telefone SET usado_em = NOW() WHERE id = $1`, [
    pendente.id,
  ]);
  await marcarTelefoneVerificado(papel, usuarioId);
}
