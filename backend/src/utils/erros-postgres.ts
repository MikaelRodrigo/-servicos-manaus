/* ============================================================================
   Códigos de erro do Postgres (SQLSTATE) que o backend precisa reconhecer.

   Referência oficial: https://www.postgresql.org/docs/current/errcodes-appendix.html

   Por que isolar isto num arquivo só? Porque na Etapa 4 (auth.repository.ts)
   e agora na Etapa "Serviços" (servicos.repository.ts) a mesma pergunta se
   repete: "essa violação foi de UNIQUE, ou de FOREIGN KEY?". Cada resposta
   vira um HTTP status diferente (409 vs 404). Um único lugar evita que os
   dois arquivos definam o código errado por descuido de copiar-e-colar.
   ========================================================================= */

/** UNIQUE_VIOLATION -- ex.: e-mail/CPF/CNPJ que já existe. Vira 409. */
export const PG_UNIQUE_VIOLATION = '23505';

/** FOREIGN_KEY_VIOLATION -- ex.: profissional_id que não existe. Vira 404. */
export const PG_FOREIGN_KEY_VIOLATION = '23503';

/** CHECK_VIOLATION -- ex.: um CHECK do schema barrou o INSERT/UPDATE. Vira 400. */
export const PG_CHECK_VIOLATION = '23514';

/**
 * O driver `pg` lança um erro cujo `.code` é o SQLSTATE, mas o `catch (erro)`
 * do TypeScript tipa `erro` como `unknown` -- por segurança, já que QUALQUER
 * coisa pode ser lançada em JavaScript, não só instâncias de `Error`. Este
 * type guard "prova" para o compilador que, se a condição for verdadeira,
 * é seguro acessar `erro.code`.
 */
export function ehErroDePostgres(
  erro: unknown,
): erro is { code: string; constraint?: string; detail?: string } {
  return typeof erro === 'object' && erro !== null && 'code' in erro;
}
