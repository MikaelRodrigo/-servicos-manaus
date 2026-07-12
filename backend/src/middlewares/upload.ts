import multer from 'multer';
import path from 'node:path';
import fs from 'node:fs';
import crypto from 'node:crypto';
import { ErroDeValidacao } from '../utils/validacao';

/* ============================================================================
   ONDE AS FOTOS FICAM GUARDADAS (E POR QUE ISSO É PROVISÓRIO)

   Para esta etapa, salvamos o arquivo no DISCO do próprio servidor, numa
   pasta `uploads/avaliacoes/` na raiz do backend. É a opção mais simples
   para aprender e testar local -- não exige conta em nenhum serviço externo.

   O PROBLEMA: isso NÃO sobrevive a um deploy na nuvem de verdade (Render,
   Railway, Fly.io...). A maioria roda em containers "efêmeros" -- toda vez
   que o serviço reinicia ou você faz um novo deploy, o disco volta ao
   estado da imagem, e as fotos enviadas por usuários SOMEM. Quando chegar
   a hora de colocar o app no ar de verdade, essa função troca de lugar por
   upload para um bucket (S3, Cloudflare R2, Supabase Storage...) -- mas
   TODO o resto do sistema (rotas, banco) continua igual, porque só
   guardamos uma URL na coluna `url_foto_servico`, nunca o arquivo em si.
   ========================================================================= */
const PASTA_UPLOADS = path.join(__dirname, '..', '..', 'uploads', 'avaliacoes');

// multer NÃO cria a pasta sozinho -- se ela não existir, o primeiro upload falha.
fs.mkdirSync(PASTA_UPLOADS, { recursive: true });

const armazenamento = multer.diskStorage({
  destination: (_req, _file, callback) => {
    callback(null, PASTA_UPLOADS);
  },
  filename: (_req, file, callback) => {
    // NUNCA reaproveite o nome original do arquivo. Três motivos:
    // 1) Dois usuários podem mandar "foto.jpg" ao mesmo tempo -- colisão.
    // 2) O nome original pode ter caracteres que quebram o sistema de
    //    arquivos ou, pior, tentar "path traversal" (ex.: "../../etc/passwd").
    // 3) Um nome aleatório não revela nada sobre quem enviou o quê.
    const extensao = path.extname(file.originalname).toLowerCase();
    const nomeAleatorio = crypto.randomUUID();
    callback(null, `${nomeAleatorio}${extensao}`);
  },
});

const TIPOS_DE_IMAGEM_ACEITOS = new Set(['image/jpeg', 'image/png', 'image/webp']);

/**
 * Middleware pronto para usar numa rota: `router.post('/x', uploadFotoServico, handler)`.
 *
 * Espera um campo de formulário chamado EXATAMENTE "foto_servico"
 * (multipart/form-data). Se o campo não vier, `req.file` fica `undefined`
 * -- a foto é OPCIONAL, a rota decide o que fazer com isso.
 */
export const uploadFotoServico = multer({
  storage: armazenamento,
  limits: {
    fileSize: 5 * 1024 * 1024, // 5 MB. Ajuste aqui se precisar de mais.
  },
  fileFilter: (_req, file, callback) => {
    if (!TIPOS_DE_IMAGEM_ACEITOS.has(file.mimetype)) {
      // Isto vira um ErroDeValidacao normal, tratado pelo middleware de
      // erro do app.ts como qualquer outro 400.
      return callback(new ErroDeValidacao('Envie uma imagem JPEG, PNG ou WEBP.'));
    }
    callback(null, true);
  },
}).single('foto_servico');

/* ============================================================================
   FOTO DE PERFIL do profissional (PATCH /profissionais/me)

   Pasta SEPARADA de `uploads/avaliacoes/` de propósito: são coleções
   diferentes de arquivo, com ciclo de vida diferente (uma foto de perfil é
   substituída quando o profissional troca; as fotos de avaliação são
   histórico permanente, uma por serviço). Misturar as duas pastas tornaria
   impossível, no futuro, aplicar uma política de retenção diferente para
   cada uma (ex.: ao trocar de foto de perfil, apagar a antiga do bucket).
   ========================================================================= */
const PASTA_UPLOADS_PERFIS = path.join(__dirname, '..', '..', 'uploads', 'perfis');
fs.mkdirSync(PASTA_UPLOADS_PERFIS, { recursive: true });

const armazenamentoPerfil = multer.diskStorage({
  destination: (_req, _file, callback) => {
    callback(null, PASTA_UPLOADS_PERFIS);
  },
  filename: (_req, file, callback) => {
    const extensao = path.extname(file.originalname).toLowerCase();
    callback(null, `${crypto.randomUUID()}${extensao}`);
  },
});

/**
 * Middleware pronto para usar numa rota: espera um campo de formulário
 * chamado EXATAMENTE "foto_perfil" (multipart/form-data). Opcional -- se o
 * campo não vier, `req.file` fica `undefined` e a rota entende que só o
 * texto (`descricao`) está sendo atualizado.
 */
export const uploadFotoPerfil = multer({
  storage: armazenamentoPerfil,
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
  fileFilter: (_req, file, callback) => {
    if (!TIPOS_DE_IMAGEM_ACEITOS.has(file.mimetype)) {
      return callback(new ErroDeValidacao('Envie uma imagem JPEG, PNG ou WEBP.'));
    }
    callback(null, true);
  },
}).single('foto_perfil');

/**
 * multer lança sua PRÓPRIA classe de erro (`MulterError`) para problemas
 * como "arquivo grande demais" -- ela não é `ErroDeValidacao`. Este type
 * guard, no mesmo espírito de `ehErroDePostgres`, permite ao app.ts
 * reconhecer esses erros e devolver 400 em vez de 500.
 */
export function ehErroDeUpload(erro: unknown): erro is multer.MulterError {
  return erro instanceof multer.MulterError;
}

const MENSAGENS_DE_ERRO_MULTER: Partial<Record<string, string>> = {
  LIMIT_FILE_SIZE: 'A imagem excede o tamanho máximo permitido (5 MB).',
  LIMIT_UNEXPECTED_FILE: 'Campo de arquivo inesperado.',
};

export function mensagemDeErroUpload(erro: multer.MulterError): string {
  return MENSAGENS_DE_ERRO_MULTER[erro.code] ?? `Erro no upload do arquivo: ${erro.message}`;
}

/** Converte o arquivo salvo por multer numa URL relativa, pronta para gravar no banco. */
export function urlPublicaDoArquivo(arquivo: Express.Multer.File): string {
  return `/uploads/avaliacoes/${arquivo.filename}`;
}

/** Mesma ideia de `urlPublicaDoArquivo`, mas para a pasta `uploads/perfis/`. */
export function urlPublicaDoArquivoPerfil(arquivo: Express.Multer.File): string {
  return `/uploads/perfis/${arquivo.filename}`;
}
