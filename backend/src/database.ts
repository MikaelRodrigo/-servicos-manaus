import { Pool, types } from 'pg';
import { env } from './env';

/* ============================================================================
   PEGADINHA DO DRIVER 'pg' -- leia antes de sair debugando

   O tipo NUMERIC do Postgres tem precisão arbitrária. Um `number` do
   JavaScript é um float64 e NÃO consegue representar todo NUMERIC sem perder
   precisão. Para não mentir para você, o driver 'pg' devolve NUMERIC como
   STRING.

   Consequência: ROUND(ST_Distance(...)::numeric, 2) chega no JSON como
   "1234.56" (com aspas). O cast ::float8 no repository resolve na query; o
   parser abaixo resolve globalmente. Se um dia entrar valor monetário aqui,
   REMOVA esta linha e trate como string/decimal.
   ========================================================================= */
const OID_NUMERIC = 1700;
types.setTypeParser(OID_NUMERIC, (valor: string) => parseFloat(valor));

/* ============================================================================
   POOL vs CLIENT

   Client = uma conexão TCP. Abrir/fechar por request custa caro e o Postgres
   tem limite de conexões. Pool = conexões reaproveitadas. É sempre isto que
   se usa em servidor web.

   ATENCAO NEON: o plano free do Neon tem um limite BAIXO de conexoes diretas.
   Como somos 3 devs, mantemos `max` conservador (5). Se der erro
   "too many connections", este e o numero a baixar -- ou use a connection
   string com "-pooler" no host, que o Neon oferece no painel.
   ========================================================================= */
export const pool = new Pool({
  host: env.db.host,
  port: env.db.port,
  database: env.db.database,
  user: env.db.user,
  password: env.db.password,

  /* ==========================================================================
     SSL -- ESTA E A DIFERENCA DO BANCO LOCAL

     O Neon SO aceita conexoes criptografadas (a connection string termina em
     ?sslmode=require). Sem este bloco, a conexao falha com um erro tipo
     "The server does not support SSL connections" ou "self-signed certificate".

     rejectUnauthorized: false -> aceita o certificado do Neon sem exigir uma
     cadeia de CA local. Para o Neon (provedor confiavel) e o padrao usado na
     pratica.

     Se um dia voltar para um Postgres LOCAL, troque por `ssl: false` ou
     remova o campo. Local nao usa SSL.
     ======================================================================= */
  ssl: {
    rejectUnauthorized: false,
  },

  max: 5,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000, // Neon "acorda" o compute; damos mais folga
  statement_timeout: 10_000,
});

/**
 * O pool emite 'error' quando uma conexao OCIOSA morre. No Neon isso acontece
 * com frequencia: no plano free o compute "dorme" apos inatividade (scale to
 * zero) e derruba conexoes ociosas. Sem escutar este evento, o Node cai com
 * uncaughtException. Aqui a gente so loga -- a proxima query reabre a conexao.
 */
pool.on('error', (erro) => {
  console.error('[db] Erro em conexao ociosa do pool:', erro.message);
});

/**
 * Ping no banco, na subida do servidor. Confirma conexao + PostGIS.
 * No Neon, a PRIMEIRA conexao pode demorar alguns segundos porque o compute
 * estava dormindo. E normal.
 */
export async function testarConexao(): Promise<void> {
  const client = await pool.connect();
  try {
    const { rows } = await client.query<{ postgis: string }>(
      'SELECT postgis_version() AS postgis',
    );
    console.log(`[db] Conectado em ${env.db.database}@${env.db.host}`);
    console.log(`[db] PostGIS: ${rows[0]?.postgis}`);
  } finally {
    client.release();
  }
}

/** Fecha o pool ordenadamente no shutdown. */
export async function fecharConexao(): Promise<void> {
  await pool.end();
  console.log('[db] Pool encerrado.');
}
