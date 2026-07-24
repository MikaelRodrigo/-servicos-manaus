import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import multerS3 from 'multer-s3';
import path from 'node:path';
import crypto from 'node:crypto';
import { Readable } from 'node:stream';
import { StorageEngine, FileFilterCallback } from 'multer';
import { env } from '../env';
import { ErroDeValidacao } from '../utils/validacao';

/* ============================================================================
   STORAGE S3-COMPATIBLE (Cloudflare R2, AWS S3, MinIO...)

   Etapa 9 (Deploy e Empacotamento): a API precisa ser stateless para escalar
   e ser redeployada sem perder arquivo de usuário. Containers efêmeros
   (Render, Railway, Fly.io...) apagam o disco local a cada novo deploy -- por
   isso o upload vai direto para um bucket, o multer nunca mais escreve no
   disco do servidor. `req.file`/`req.files` chegam na rota já com `.location`
   preenchido (URL pública), prontos para gravar na coluna do banco.
   ========================================================================= */
export const s3Client = new S3Client({
  region: env.s3.region,
  endpoint: env.s3.endpoint,
  // A maioria dos provedores S3-compatible (R2, MinIO...) exige path-style
  // (`endpoint/bucket/chave`) em vez do virtual-hosted-style da AWS
  // (`bucket.endpoint/chave`). Ligado sempre -- inofensivo na AWS também.
  forcePathStyle: true,
  credentials: {
    accessKeyId: env.s3.accessKeyId,
    secretAccessKey: env.s3.secretAccessKey,
  },
});

const TIPOS_DE_IMAGEM_ACEITOS = new Set(['image/jpeg', 'image/png', 'image/webp']);

/**
 * Cria o storage engine do multer para uma "pasta" lógica dentro do bucket
 * (ex.: "avaliacoes", "perfis") -- não existe pasta de verdade num bucket S3,
 * é só um prefixo na chave do objeto, mas serve exatamente ao mesmo propósito
 * de separação que as pastas em disco tinham antes (ver `middlewares/upload.ts`).
 */
export function criarStorageS3(prefixo: string): StorageEngine {
  return multerS3({
    s3: s3Client,
    bucket: env.s3.bucketName,
    contentType: multerS3.AUTO_CONTENT_TYPE,
    key: (_req, file, callback) => {
      // Nome aleatório, nunca o original: evita colisão entre usuários,
      // path traversal, e não revela quem enviou o quê (mesma justificativa
      // de antes, quando os arquivos ainda iam para o disco).
      const extensao = path.extname(file.originalname).toLowerCase();
      callback(null, `${prefixo}/${crypto.randomUUID()}${extensao}`);
    },
  });
}

/** Filtro de tipo de arquivo compartilhado pelos dois uploads (avaliação e perfil). */
export function filtroDeImagem(
  _req: Express.Request,
  file: Express.Multer.File,
  callback: FileFilterCallback,
): void {
  if (!TIPOS_DE_IMAGEM_ACEITOS.has(file.mimetype)) {
    callback(new ErroDeValidacao('Envie uma imagem JPEG, PNG ou WEBP.'));
    return;
  }
  callback(null, true);
}

/**
 * Migração 18 -- certidão de antecedentes criminais. Aceita tudo que
 * `filtroDeImagem` aceita, MAIS `application/pdf` (a maioria das certidões
 * emitidas hoje em dia é baixada direto em PDF, com camada de texto de
 * verdade -- é o que permite a checagem automática por palavra-chave, ver
 * `services/checagem-documento.ts`).
 */
const TIPOS_DE_DOCUMENTO_ACEITOS = new Set([...TIPOS_DE_IMAGEM_ACEITOS, 'application/pdf']);

export function filtroDeDocumento(
  _req: Express.Request,
  file: Express.Multer.File,
  callback: FileFilterCallback,
): void {
  if (!TIPOS_DE_DOCUMENTO_ACEITOS.has(file.mimetype)) {
    callback(new ErroDeValidacao('Envie um PDF ou uma imagem (JPEG, PNG ou WEBP).'));
    return;
  }
  callback(null, true);
}

/* ============================================================================
   ARMAZENAMENTO PRIVADO (migração 18)

   Diferente de `criarStorageS3` acima (que o multer-s3 usa para subir o
   arquivo DIRETO pro bucket, sem passar pela memória do servidor): a
   certidão de antecedentes precisa passar pela memória da rota primeiro
   (para `pdf-parse` conseguir ler os bytes e rodar a checagem automática
   ANTES de decidir se grava), e o resultado é salvo com uma CHAVE, nunca
   uma URL pública -- ver comentário em `database/18_*.sql` sobre por que
   este é o único upload do app que não usa `urlPublicaDoArquivo`.

   O middleware correspondente (`uploadDocumentoAntecedentes` em
   middlewares/upload.ts) usa `multer.memoryStorage()` -- por isso `req.file`
   chega com `.buffer` preenchido, e é a ROTA quem chama
   `enviarDocumentoPrivado` explicitamente, depois de rodar a checagem.
   ========================================================================= */

/** Sobe um buffer já em memória pro bucket, sob o prefixo "antecedentes/". Devolve a CHAVE (não a URL). */
export async function enviarDocumentoPrivado(
  buffer: Buffer,
  mimetype: string,
  nomeOriginal: string,
): Promise<{ chave: string }> {
  const extensao = path.extname(nomeOriginal).toLowerCase();
  const chave = `antecedentes/${crypto.randomUUID()}${extensao}`;

  await s3Client.send(
    new PutObjectCommand({
      Bucket: env.s3.bucketName,
      Key: chave,
      Body: buffer,
      ContentType: mimetype,
    }),
  );

  return { chave };
}

/**
 * Busca de volta um documento privado, para transmitir pela rota
 * autenticada (nunca por URL pública -- ver comentário acima). Lança se a
 * chave não existir mais no bucket; quem chama decide como tratar (a rota
 * transforma em 404).
 */
export async function baixarDocumentoPrivado(
  chave: string,
): Promise<{ stream: Readable; contentType: string | undefined; tamanho: number | undefined }> {
  const resultado = await s3Client.send(
    new GetObjectCommand({ Bucket: env.s3.bucketName, Key: chave }),
  );
  return {
    stream: resultado.Body as Readable,
    contentType: resultado.ContentType,
    tamanho: resultado.ContentLength,
  };
}
