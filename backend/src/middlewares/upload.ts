import multer from 'multer';
import { criarStorageS3, filtroDeImagem, filtroDeDocumento } from '../services/uploadService';
import { env } from '../env';

/** Teto de fotos por avaliação. Ajuste aqui se um dia precisar de mais. */
export const MAX_FOTOS_POR_AVALIACAO = 5;

/** Teto de fotos por LOTE enviado de uma vez ao portfólio (migração 16) -- não é o teto TOTAL da galeria, só quantas cabem numa única chamada de upload. */
export const MAX_FOTOS_POR_LOTE_PORTFOLIO = 6;

/** Teto TOTAL de fotos no portfólio de um profissional -- checado no repository (`contarFotosPortfolio`) antes de aceitar um novo lote, não aqui (o multer só sabe quantas vieram NESTA requisição, não quantas já existem no banco). */
export const MAX_FOTOS_TOTAL_PORTFOLIO = 24;

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
 * FOTOS DO PORTFÓLIO (migração 16) -- galeria curada pelo próprio
 * profissional (`POST /profissionais/me/portfolio-fotos`), diferente de
 * `uploadFotoServico` (fotos que o CLIENTE anexa numa avaliação). Prefixo
 * próprio ("portfolio") para não misturar ciclo de vida com os outros dois.
 *
 * Espera um campo de formulário chamado EXATAMENTE "fotos_portfolio",
 * podendo repetir várias vezes -- mesma convenção de `uploadFotoServico`.
 * O teto TOTAL da galeria (`MAX_FOTOS_TOTAL_PORTFOLIO`) é responsabilidade
 * da ROTA/repository (`contarFotosPortfolio`), não deste middleware -- o
 * multer só enxerga os arquivos DESTA requisição, nunca quantos já
 * existem no banco.
 */
export const uploadFotosPortfolio = multer({
  storage: criarStorageS3('portfolio'),
  limits: {
    fileSize: 5 * 1024 * 1024,
  },
  fileFilter: filtroDeImagem,
}).array('fotos_portfolio', MAX_FOTOS_POR_LOTE_PORTFOLIO);

export const MAX_TAMANHO_DOCUMENTO_ANTECEDENTES_MB = 8;

/**
 * CERTIDÃO DE ANTECEDENTES CRIMINAIS (migração 18) -- ÚNICO upload do app
 * que usa `multer.memoryStorage()` em vez de `criarStorageS3(...)`.
 *
 * Motivo: a rota (`POST /profissionais/me/documento-antecedentes`) precisa
 * dos BYTES do arquivo em memória (`req.file.buffer`) para rodar a
 * extração de texto (`pdf-parse`) e a checagem automática ANTES de decidir
 * gravar -- diferente de `uploadFotoServico`/`uploadFotoPerfil`/
 * `uploadFotosPortfolio`, que sobem direto pro bucket sem a rota precisar
 * olhar o conteúdo. É a própria rota quem chama
 * `enviarDocumentoPrivado` (uploadService.ts) depois da checagem -- ver
 * comentário lá sobre por que o resultado é uma CHAVE, nunca uma URL
 * pública.
 *
 * Limite de tamanho maior que os uploads de imagem (8 MB, não 5 MB):
 * certidões em PDF costumam ser pequenas, mas uma foto/scan do documento
 * pode passar de 5 MB facilmente.
 *
 * Espera um campo de formulário chamado EXATAMENTE "documento_antecedentes".
 */
export const uploadDocumentoAntecedentes = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: MAX_TAMANHO_DOCUMENTO_ANTECEDENTES_MB * 1024 * 1024,
  },
  fileFilter: filtroDeDocumento,
}).single('documento_antecedentes');

/**
 * multer lança sua PRÓPRIA classe de erro (`MulterError`) para problemas
 * como "arquivo grande demais" -- ela não é `ErroDeValidacao`. Este type
 * guard, no mesmo espírito de `ehErroDePostgres`, permite ao app.ts
 * reconhecer esses erros e devolver 400 em vez de 500.
 */
export function ehErroDeUpload(erro: unknown): erro is multer.MulterError {
  return erro instanceof multer.MulterError;
}

// Mensagem genérica de propósito -- este mapa é COMPARTILHADO por todo
// middleware de upload do arquivo (avaliação, perfil, portfólio,
// documento de antecedentes), cada um com seu próprio teto de tamanho/
// quantidade (MAX_FOTOS_POR_AVALIACAO, MAX_TAMANHO_DOCUMENTO_ANTECEDENTES_MB...).
// Citar um número fixo aqui seria impreciso para os outros -- cada
// middleware já barra no teto certo (`limits.fileSize`/`.array(...)`);
// esta mensagem só precisa dizer QUE existe um limite.
const MENSAGENS_DE_ERRO_MULTER: Partial<Record<string, string>> = {
  LIMIT_FILE_SIZE: 'O arquivo excede o tamanho máximo permitido.',
  LIMIT_UNEXPECTED_FILE: 'Campo de arquivo inesperado.',
  LIMIT_FILE_COUNT: 'Você enviou arquivos demais de uma vez.',
  LIMIT_FIELD_COUNT: 'Você enviou arquivos demais de uma vez.',
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
