import multer from 'multer';
import { criarStorageS3, filtroDeImagem } from '../services/uploadService';
import { env } from '../env';

/** Teto de fotos por avaliação. Ajuste aqui se um dia precisar de mais. */
export const MAX_FOTOS_POR_AVALIACAO = 5;

/**
 * Middleware pronto para usar numa rota: `router.post('/x', uploadFotoServico, handler)`.
 *
 * Espera um campo de formulário chamado EXATAMENTE "fotos_servico"
 * (multipart/form-data), podendo repetir esse campo várias vezes (é assim
 * que multipart representa "vários arquivos no mesmo campo"). `.array(...)`
 * -- não `.single(...)` -- porque uma avaliação pode ter várias fotos (ver
 * migração 05: `avaliacoes_profissional_fotos`). Se nenhum arquivo vier,
 * `req.files` chega como array vazio -- a foto continua sendo OPCIONAL.
 *
 * O storage (`criarStorageS3`) sobe o arquivo direto para o bucket durante
 * o próprio middleware -- quando a rota roda, o arquivo já está no bucket
 * e `urlsPublicasDosArquivos`/`urlPublicaDoArquivoPerfil` (abaixo) devolvem
 * a URL pública pronta para gravar no banco.
 */
export const uploadFotoServico = multer({
  storage: criarStorageS3('avaliacoes'),
  limits: {
    fileSize: 5 * 1024 * 1024, // 5 MB por arquivo. Ajuste aqui se precisar de mais.
  },
  fileFilter: filtroDeImagem,
}).array('fotos_servico', MAX_FOTOS_POR_AVALIACAO);

/**
 * FOTO DE PERFIL do profissional/cliente (PATCH /profissionais/me, PATCH /clientes/me).
 *
 * Prefixo SEPARADO ("perfis") do de avaliação ("avaliacoes") de propósito:
 * são coleções diferentes de arquivo, com ciclo de vida diferente (uma foto
 * de perfil é substituída quando o dono troca; as fotos de avaliação são
 * histórico permanente). Separar os prefixos deixa o caminho aberto para
 * uma política de retenção diferente para cada um no futuro (ex.: ao trocar
 * de foto de perfil, apagar a antiga do bucket).
 *
 * Middleware pronto para usar numa rota: espera um campo de formulário
 * chamado EXATAMENTE "foto_perfil" (multipart/form-data). Opcional -- se o
 * campo não vier, `req.file` fica `undefined` e a rota entende que só o
 * texto está sendo atualizado.
 */
export const uploadFotoPerfil = multer({
  storage: criarStorageS3('perfis'),
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
  fileFilter: filtroDeImagem,
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
  LIMIT_FILE_COUNT: `Envie no máximo ${MAX_FOTOS_POR_AVALIACAO} fotos.`,
  LIMIT_FIELD_COUNT: `Envie no máximo ${MAX_FOTOS_POR_AVALIACAO} fotos.`,
};

export function mensagemDeErroUpload(erro: multer.MulterError): string {
  return MENSAGENS_DE_ERRO_MULTER[erro.code] ?? `Erro no upload do arquivo: ${erro.message}`;
}

/**
 * Monta a URL pública de um arquivo já enviado ao bucket.
 *
 * NÃO usa `arquivo.location` (o multer-s3 monta esse campo a partir do
 * `endpoint` da API S3, que exige assinatura AWS SigV4 até para GET -- o
 * app não conseguiria simplesmente abrir essa URL numa tag de imagem).
 * Em vez disso, usamos `arquivo.key` (o caminho que NÓS escolhemos em
 * `criarStorageS3`) + `S3_PUBLIC_URL_BASE` (o domínio público do bucket,
 * ex.: o R2.dev subdomain), que é servido sem autenticação.
 */
export function urlPublicaDoArquivo(arquivo: Express.MulterS3.File): string {
  return `${env.s3.publicUrlBase}/${arquivo.key}`;
}

/** Mesma ideia, para VÁRIOS arquivos de uma vez (`req.files`, vindo do `.array(...)` acima). */
export function urlsPublicasDosArquivos(arquivos: Express.MulterS3.File[]): string[] {
  return arquivos.map(urlPublicaDoArquivo);
}

/** Mesma ideia de `urlPublicaDoArquivo`, para a foto de perfil (`req.file`). */
export function urlPublicaDoArquivoPerfil(arquivo: Express.MulterS3.File): string {
  return urlPublicaDoArquivo(arquivo);
}
