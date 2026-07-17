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
    // Sem valor obrigatório aqui seria fácil esquecer de definir em produção
    // e o app "funcionar" assinando tokens com um segredo previsível.
    secret: obrigatoria('JWT_SECRET'),
    expiresIn: process.env.JWT_EXPIRES_IN ?? '1h',
  },

  bcryptSaltRounds: numero('BCRYPT_SALT_ROUNDS', 10),

  // Storage S3-compatible (Cloudflare R2, AWS S3, MinIO...) para as fotos de
  // avaliação e de perfil. Obrigatório sempre (dev incluso) -- Etapa 9 tornou
  // a API stateless de propósito: nenhum arquivo de usuário pode depender do
  // disco local do servidor, nem em desenvolvimento, para que o comportamento
  // seja o mesmo em qualquer ambiente. Use um bucket gratuito (ex.: Cloudflare
  // R2, tier free) também para rodar localmente.
  s3: {
    endpoint: obrigatoria('S3_ENDPOINT'),
    region: process.env.S3_REGION ?? 'auto',
    bucketName: obrigatoria('S3_BUCKET_NAME'),
    accessKeyId: obrigatoria('S3_ACCESS_KEY_ID'),
    secretAccessKey: obrigatoria('S3_SECRET_ACCESS_KEY'),
    // URL PÚBLICA do bucket (R2.dev subdomain ou domínio customizado) --
    // DIFERENTE do `endpoint` acima. O `endpoint` é a API S3 (exige
    // assinatura AWS SigV4 até para GET, o app não consegue simplesmente
    // carregar uma imagem dali). Sem essa variável, a URL salva no banco
    // aponta para um recurso que `Image.network` no Flutter não consegue
    // abrir -- ver `middlewares/upload.ts`, que monta a URL final com isto.
    publicUrlBase: obrigatoria('S3_PUBLIC_URL_BASE'),
  },

  // Gateway de pagamento (migração 14 -- Escrow + Split). DIFERENTE de todo
  // o resto deste arquivo: as duas chaves aqui NÃO são `obrigatoria(...)`.
  // Se fossem, o servidor inteiro recusaria subir para qualquer dev/
  // ambiente que ainda não tenha uma conta Pagar.me configurada -- e hoje
  // isso é a maioria (o módulo de pagamentos é aditivo, o resto do app
  // funciona sem ele). Em vez disso, a ausência só vira erro NA HORA de
  // efetivamente chamar o gateway (ver `services/gateway-pagamento.ts`,
  // `exigirCredenciais()`) -- um servidor sem Pagar.me configurado sobe
  // normalmente; só as rotas de /pagamentos que dependem do gateway falham,
  // com uma mensagem clara.
  pagarme: {
    // Chave secreta da API (formato "sk_..." em produção, "sk_test_..." em
    // sandbox) -- ver https://docs.pagar.me/docs/chaves-de-acesso. Usada
    // como usuário em HTTP Basic Auth (senha vazia), conforme a API v5.
    apiKey: process.env.PAGARME_API_KEY,
    // Segredo usado para validar a assinatura HMAC de cada webhook
    // recebido (cabeçalho `X-Hub-Signature-256`) -- sem isso, QUALQUER UM
    // que descubra a URL do webhook conseguiria forjar um "pagamento
    // autorizado" falso. Configurado no painel do Pagar.me, na tela do
    // próprio webhook.
    webhookSecret: process.env.PAGARME_WEBHOOK_SECRET,
  },
} as const;
