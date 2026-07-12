import bcrypt from 'bcryptjs';
import { env } from '../env';

/* ============================================================================
   POR QUE BCRYPT E NÃO SHA-256 / MD5?

   SHA-256 e MD5 são RÁPIDOS de propósito -- foram feitos para checar
   integridade de arquivo, não para proteger senha. Rápido é exatamente o
   que você NÃO quer aqui: um atacante com a tabela de hashes em mãos
   consegue testar bilhões de senhas por segundo contra um hash SHA-256.

   BCRYPT é deliberadamente LENTO (o "custo"/"rounds" controla o quanto), e
   já embute um SALT aleatório diferente em cada hash -- por isso dois
   usuários com a mesma senha "123456" geram hashes completamente diferentes
   no banco. Isso também impede um ataque de "rainbow table" (tabela
   pré-calculada de hash -> senha).

   NUNCA guarde a senha em texto puro. NUNCA devolva senha_hash em um JSON
   de resposta, nem por engano.
   ========================================================================= */

/** Gera o hash que vai para a coluna senha_hash. Usado no cadastro. */
export async function gerarHashSenha(senhaEmTextoPuro: string): Promise<string> {
  return bcrypt.hash(senhaEmTextoPuro, env.bcryptSaltRounds);
}

/**
 * Compara a senha digitada no login com o hash salvo no banco.
 * Retorna true/false -- nunca lança erro, nunca revela "qual dos dois
 * estava errado" (isso é feito pela rota, com uma mensagem genérica).
 */
export async function conferirSenha(
  senhaEmTextoPuro: string,
  hashSalvo: string,
): Promise<boolean> {
  return bcrypt.compare(senhaEmTextoPuro, hashSalvo);
}

/* ============================================================================
   REGRA MÍNIMA DE SENHA FORTE

   Validação de "força" de senha é debate infinito. Aqui vai o mínimo que
   qualquer banca de TCC aceita sem discussão: 8+ caracteres, pelo menos uma
   letra e um número. Isso barra "123456" e "senha" sem exigir símbolo
   especial (que só faz usuário anotar a senha num post-it).
   ========================================================================= */
const REGEX_SENHA_FORTE = /^(?=.*[A-Za-z])(?=.*\d).{8,}$/;

export function senhaAtendeRequisitosMinimos(senha: string): boolean {
  return REGEX_SENHA_FORTE.test(senha);
}
