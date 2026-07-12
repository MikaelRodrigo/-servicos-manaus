import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import path from 'node:path';
import { env } from './env';
import { profissionaisRouter } from './routes/profissionais.routes';
import { authRouter } from './routes/auth.routes';
import { servicosRouter } from './routes/servicos.routes';
import { ErroDeValidacao, ErroDeConflito, ErroNaoEncontrado } from './utils/validacao';
import { ErroDeAutenticacao } from './middlewares/autenticacao';
import { ehErroDeUpload, mensagemDeErroUpload } from './middlewares/upload';

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

// Serve os arquivos de uploads/avaliacoes/ como arquivo estático, na URL
// /uploads/avaliacoes/<nome>. É essa URL que vai parar em `url_foto_servico`.
// Lembrete da Etapa "Avaliações": isto é armazenamento em DISCO LOCAL,
// bom para aprender, mas não sobrevive a um deploy num container efêmero.
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

app.use('/profissionais', profissionaisRouter);
app.use('/auth', authRouter);
app.use('/servicos', servicosRouter);

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

  // E-mail/CPF/CNPJ já cadastrado -> 409 (conflito), não 400: o dado está
  // bem formado, só que já existe outro registro igual.
  if (erro instanceof ErroDeConflito) {
    return res.status(409).json({ erro: erro.message });
  }

  // Token ausente/inválido/expirado (401) ou papel sem permissão (403).
  if (erro instanceof ErroDeAutenticacao) {
    return res.status(erro.status).json({ erro: erro.message });
  }

  // Recurso que não existe -> 404 (ex.: GET /servicos/:id com UUID inexistente).
  if (erro instanceof ErroNaoEncontrado) {
    return res.status(404).json({ erro: erro.message });
  }

  // Erro do multer (arquivo grande demais, campo errado etc.) -> 400.
  if (ehErroDeUpload(erro)) {
    return res.status(400).json({ erro: mensagemDeErroUpload(erro) });
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
