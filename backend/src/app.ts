import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import { env } from './env';
import { profissionaisRouter } from './routes/profissionais.routes';
import { ErroDeValidacao } from './utils/validacao';

export const app = express();

/* ---------------------------------------------------------------------------
   MIDDLEWARES GLOBAIS
   A ordem importa: eles rodam de cima para baixo, em cada request.
   --------------------------------------------------------------------------- */

// CORS liberado geral. Isto serve para DESENVOLVIMENTO.
// Em produção, restrinja: cors({ origin: ['https://seuapp.com.br'] })
// O app Flutter nativo não é afetado por CORS (só navegadores são),
// mas o Flutter Web é.
app.use(cors());

// Faz o parse de body JSON. Limite baixo: nenhuma rota nossa recebe
// payload grande, e sem limite alguém te manda 500MB num POST.
app.use(express.json({ limit: '100kb' }));

// Log simples de request. Na Etapa 5 trocamos por pino/morgan.
app.use((req, _res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`);
  next();
});

/* ---------------------------------------------------------------------------
   ROTAS
   --------------------------------------------------------------------------- */

// Healthcheck. O Docker/Render/Railway usa isto pra saber se o app subiu.
app.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', ambiente: env.nodeEnv, timestamp: new Date().toISOString() });
});

app.use('/profissionais', profissionaisRouter);

/* ---------------------------------------------------------------------------
   404 - qualquer rota não registrada acima cai aqui.
   --------------------------------------------------------------------------- */
app.use((req: Request, res: Response) => {
  res.status(404).json({ erro: `Rota não encontrada: ${req.method} ${req.originalUrl}` });
});

/* ---------------------------------------------------------------------------
   MIDDLEWARE DE ERRO -- precisa vir POR ÚLTIMO, e precisa ter os QUATRO
   parâmetros (erro, req, res, next). O Express identifica um error handler
   pela ARIDADE da função. Se você remover o `_next`, ele deixa de funcionar
   e você não recebe nenhum aviso.
   --------------------------------------------------------------------------- */
app.use((erro: unknown, _req: Request, res: Response, _next: NextFunction) => {
  // Erro de entrada do usuário -> 400, com a mensagem.
  if (erro instanceof ErroDeValidacao) {
    return res.status(400).json({ erro: erro.message });
  }

  // Qualquer outra coisa é bug NOSSO. Loga completo no servidor...
  console.error('[erro] Não tratado:', erro);

  // ...e devolve uma mensagem genérica para o cliente.
  // Stack trace na resposta HTTP entrega a estrutura interna do seu sistema
  // (nomes de tabela, caminhos de arquivo) para quem estiver sondando.
  return res.status(500).json({
    erro: 'Erro interno do servidor.',
    ...(env.nodeEnv === 'development' && {
      detalhe: erro instanceof Error ? erro.message : String(erro),
    }),
  });
});
