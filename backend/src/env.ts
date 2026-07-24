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

  // API Pix própria (migração 15 -- substituiu o Pagar.me). DIFERENTE de
  // todo o resto deste arquivo: nenhuma chave aqui é `obrigatoria(...)`.
  // O usuário ainda vai CONSTRUIR essa API ("Eu criarei uma api, integrada
  // a minha conta pix jurídica") -- hoje ela não existe. Enquanto
  // `baseUrl` não estiver definida, `services/pix-proprio.ts` roda em MODO
  // SIMULADO (gera uma cobrança fake na hora, sem chamar nada de verdade)
  // -- é o que permite o resto do fluxo (proposta -> confirmação ->
  // retenção -> liberação) ser testado ponta a ponta já, sem esperar essa
  // API ficar pronta. Configure as três variáveis quando ela existir.
  pixProprio: {
    baseUrl: process.env.PIX_PROPRIO_BASE_URL,
    apiKey: process.env.PIX_PROPRIO_API_KEY,
    // Segredo compartilhado para validar quem chama POST /pagamentos/webhook
    // (a futura API própria avisando "este Pix caiu"). Comparação simples
    // (não HMAC) de propósito -- o formato de assinatura da API própria
    // ainda não existe para ser implementado direito; troque por HMAC (ver
    // o padrão já usado antes para o Pagar.me, git-log deste arquivo) assim
    // que o formato real dela for definido.
    webhookSecret: process.env.PIX_PROPRIO_WEBHOOK_SECRET,
  },

  // Provedor de SMS (migração 17 -- verificação de telefone no cadastro).
  // MESMO ESPÍRITO de `pixProprio` acima: nenhuma chave aqui é
  // `obrigatoria(...)`. Enquanto `baseUrl` não estiver definida,
  // `services/sms.ts` roda em MODO SIMULADO (gera o código de 6 dígitos
  // normalmente, mas em vez de mandar pra operadora de verdade, só loga no
  // console do servidor e devolve o código na própria resposta da API --
  // ver `verificacao: { simulado: true, codigo: "..." }` em
  // `POST /auth/cadastro/*` e `POST /auth/verificar-telefone/*`) -- é o
  // que permite testar o fluxo inteiro (cadastro -> código -> confirmação
  // -> login) sem nenhuma conta de SMS de verdade. Configure as três
  // variáveis quando escolher um provedor (Twilio, Zenvia, AWS SNS...).
  sms: {
    baseUrl: process.env.SMS_PROVIDER_BASE_URL,
    apiKey: process.env.SMS_PROVIDER_API_KEY,
    // Remetente exibido no SMS (nome curto ou número, depende do provedor)
    // -- opcional mesmo em modo real: alguns provedores definem isso na
    // própria conta, não por requisição.
    remetente: process.env.SMS_PROVIDER_REMETENTE,
  },

  // Percentual retido pela plataforma sobre cada serviço (pedido do
  // usuário: "8,9%", o número mais recente e específico -- a mensagem
  // inicial dizia "8%"; ver o comentário em `database/15_*.sql`, Seção 4).
  // Configurável aqui, NUNCA hardcoded no código de rota -- trocar a taxa é
  // mudar uma variável de ambiente, não editar SQL nem TypeScript. Cada
  // transação grava o percentual VIGENTE no momento (não uma referência
  // viva a esta constante), então mudar isto não altera o histórico já
  // gravado -- só as próximas propostas.
  comissaoPlataformaPercentual: numero('COMISSAO_PLATAFORMA_PERCENTUAL', 8.9),
} as const;
