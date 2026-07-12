import 'dotenv/config';

function obrigatoria(chave: string): string {
  const valor = process.env[chave];
  if (!valor || valor.trim() === '') {
    throw new Error(
      `[env] Variavel de ambiente obrigatoria ausente: ${chave}. ` +
        `Voce copiou o .env.example para .env?`,
    );
  }
  return valor;
}

function numero(chave: string, padrao: number): number {
  const bruto = process.env[chave];
  if (!bruto) return padrao;

  const n = Number(bruto);
  if (!Number.isFinite(n)) {
    throw new Error(`[env] ${chave} precisa ser um numero. Recebido: "${bruto}"`);
  }
  return n;
}

export const env = {
  port: numero('PORT', 3333),
  nodeEnv: process.env.NODE_ENV ?? 'development',

  db: {
    host: obrigatoria('DB_HOST'),
    port: numero('DB_PORT', 5432),
    database: obrigatoria('DB_NAME'),
    user: obrigatoria('DB_USER'),
    password: obrigatoria('DB_PASSWORD'),
  },

  raioMaximoKm: numero('RAIO_MAXIMO_KM', 50),

  jwt: {
 