import jwt, { SignOptions } from 'jsonwebtoken';
import { env } from '../env';

/**
 * "Papel" do usuário dentro do app. Note que, diferente de muitos tutoriais,
 * aqui isso NÃO é uma coluna "role" numa tabela única de usuários -- é o
 * reflexo direto de qual tabela a pessoa está cadastrada (profissionais,
 * clientes, ou -- desde a migração 15 -- admins, para gerenciar a
 * conciliação de comissão). `admin` nunca se autocadastra (sem rota POST
 * /auth/cadastro/admin) -- ver comentário em `database/15_*.sql`.
 */
export type Papel = 'cliente' | 'profissional' | 'admin';

/** O que vai DENTRO do token. Nunca, jamais, inclua senha_hash aqui. */
export interface PayloadToken {
  /** "sub" (subject) é convenção do padrão JWT para "de quem é este token". */
  sub: string;
  papel: Papel;
  email: string;
}

/* ============================================================================
   O QUE UM JWT REALMENTE É

   Três pedaços separados por ponto, cada um em Base64:

     HEADER.PAYLOAD.ASSINATURA

   O HEADER e o PAYLOAD são só Base64 -- QUALQUER UM consegue decodificar e
   ler (dá pra colar em jwt.io agora e ver). NÃO é criptografia, é só
   codificação. Por isso o payload acima só tem id/papel/email -- nada
   sensível.

   A ASSINATURA é a parte que importa: o servidor gera ela a partir do
   HEADER + PAYLOAD + JWT_SECRET usando HMAC-SHA256. Quando o token volta
   numa request futura, o servidor recalcula a assinatura com o MESMO
   segredo e compara. Se uma vírgula do payload for alterada por fora
   (ex.: tentar trocar "papel":"cliente" por "papel":"profissional"),
   a assinatura recalculada não bate mais, e o token é rejeitado.

   Conclusão prática: JWT prova "isto não foi alterado desde que o servidor
   assinou", não "isto está em segredo". Nunca coloque senha, CPF completo
   ou qualquer dado sensível dentro do payload.
   ========================================================================= */

export function gerarToken(payload: PayloadToken): string {
  // O cast duplo (`as unknown as`) evita depender do formato exato que a
  // lib espera para `expiresIn` (ela aceita "1h", "15m", 3600, etc. -- um
  // tipo bem específico que muda entre versões). Nosso valor vem do .env
  // como string simples; sabemos que está no formato certo.
  const opcoes = { expiresIn: env.jwt.expiresIn } as unknown as SignOptions;
  return jwt.sign(payload, env.jwt.secret, opcoes);
}

/**
 * Verifica assinatura + validade (expiração) do token.
 * Lança erro se o token for inválido, expirado ou adulterado -- é
 * responsabilidade de quem chama (o middleware) tratar isso como 401.
 *
 * O `as unknown as` (em vez de um `as` direto) é proposital: o tipo de
 * retorno de `jwt.verify` é `string | JwtPayload`, que não tem overlap
 * suficiente com o nosso `PayloadToken` para o TypeScript aceitar um cast
 * direto. Nós SABEMOS que o payload tem esse formato porque fomos nós que
 * assinamos com `gerarToken` -- então o cast é seguro aqui.
 */
export function verificarToken(token: string): PayloadToken {
  return jwt.verify(token, env.jwt.secret) as unknown as PayloadToken;
}
