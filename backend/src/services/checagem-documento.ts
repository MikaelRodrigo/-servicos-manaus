import pdfParse from 'pdf-parse';

/* ============================================================================
   O QUE ESTE ARQUIVO FAZ (e o que ele NÃO faz)

   Roda uma checagem AUTOMÁTICA BÁSICA sobre a certidão de antecedentes
   criminais enviada pelo profissional (migração 18): o arquivo tem texto
   legível, esse texto tem cara de certidão (palavras-chave esperadas), e o
   nome/CPF do profissional aparecem nele.

   O QUE ISTO NÃO FAZ -- e não existe jeito de fazer sem integrar com o
   órgão emissor: confirmar que o documento é AUTÊNTICO de verdade. Uma
   certidão de antecedentes tem um código de verificação que só o site
   oficial do emissor (Polícia Federal, TJ de cada estado...) confere --
   isso está fora do alcance de qualquer checagem de texto. Por isso a
   aprovação final é SEMPRE de um admin humano (ver
   `repositories/documentos-antecedentes.repository.ts`) -- esta checagem
   só ajuda ele a decidir mais rápido (e rejeita sozinha os casos óbvios:
   arquivo que claramente não é uma certidão nenhuma).
   ========================================================================= */

/** Só extraímos texto de PDF -- imagem (JPEG/PNG/WEBP) fica sem OCR nesta etapa (ver comentário abaixo). Devolve `null` se não for PDF, ou se o PDF estiver corrompido/protegido por senha (nesse caso a checagem cai toda pra "não aplicável", e o documento vai pra revisão manual mesmo). */
export async function extrairTextoDoDocumento(
  buffer: Buffer,
  mimetype: string,
): Promise<string | null> {
  if (mimetype !== 'application/pdf') {
    // OCR de imagem (Tesseract ou similar) ficou de fora desta etapa de
    // propósito -- adiciona uma dependência pesada (motor de OCR + dados de
    // idioma) e alguns segundos de latência por upload, para um caso que a
    // maioria das certidões emitidas hoje (PDF gerado digitalmente, com
    // camada de texto) já não precisa. Se o profissional enviar uma FOTO do
    // documento em vez do PDF original, ele simplesmente cai direto na fila
    // de revisão manual, sem checagem de palavra-chave -- ainda funciona,
    // só sem o atalho automático.
    return null;
  }

  try {
    const resultado = await pdfParse(buffer);
    return resultado.text;
  } catch {
    return null;
  }
}

/** Remove acentos e uniformiza maiúsculas -- extração de PDF costuma variar espaçamento/acentuação conforme a fonte usada no documento original. */
function normalizar(texto: string): string {
  const MARCAS_DIACRITICAS_COMBINANTES = /[̀-ͯ]/g;
  return texto.normalize('NFD').replace(MARCAS_DIACRITICAS_COMBINANTES, '').toUpperCase();
}

/** Qualquer uma destas frases aparecendo já é sinal forte de que o arquivo É uma certidão de antecedentes (ou documento correlato emitido por órgão de segurança/justiça) -- não precisa achar todas, uma só já basta pra não rejeitar automaticamente. */
const PALAVRAS_CHAVE_ESPERADAS = [
  'CERTIDAO',
  'ANTECEDENTES CRIMINAIS',
  'ANTECEDENTE CRIMINAL',
  'NADA CONSTA',
  'POLICIA FEDERAL',
  'TRIBUNAL DE JUSTICA',
  'SECRETARIA DE SEGURANCA',
];

export interface ResultadoChecagem {
  /** Quais das `PALAVRAS_CHAVE_ESPERADAS` apareceram no texto extraído. */
  palavrasChaveEncontradas: string[];
  /** `null` = não aplicável (sem texto extraído -- documento é imagem, ou PDF ilegível). */
  nomeEncontrado: boolean | null;
  /** `null` = não aplicável (sem texto extraído, OU profissional é PJ, sem CPF individual cadastrado -- ver comentário em documentos-antecedentes.repository.ts). */
  cpfEncontrado: boolean | null;
  /** `true` só quando o texto foi extraído com sucesso e NENHUMA palavra-chave apareceu -- sinal forte de que o arquivo enviado não é uma certidão (ex.: a pessoa anexou outro documento por engano). Rejeição automática (ver rota). */
  pareceDocumentoErrado: boolean;
}

/**
 * `texto` já vem de `extrairTextoDoDocumento` (pode ser `null`). `nome` e
 * `cpf` são os dados JÁ CADASTRADOS do profissional (nunca digitados de
 * novo aqui) -- `cpf` é `null` para profissional PJ.
 */
export function checarDocumento(params: {
  texto: string | null;
  nome: string;
  cpf: string | null;
}): ResultadoChecagem {
  if (params.texto === null) {
    return {
      palavrasChaveEncontradas: [],
      nomeEncontrado: null,
      cpfEncontrado: null,
      pareceDocumentoErrado: false,
    };
  }

  const textoNormalizado = normalizar(params.texto);

  const palavrasChaveEncontradas = PALAVRAS_CHAVE_ESPERADAS.filter((chave) =>
    textoNormalizado.includes(chave),
  );

  // Todas as "palavras" do nome (>2 letras, pra ignorar preposições como
  // "DE"/"DA"/"DOS") precisam aparecer no texto -- não em sequência exata
  // (a extração de PDF às vezes quebra linha no meio do nome), só
  // presentes em algum lugar.
  const palavrasDoNome = normalizar(params.nome)
    .split(/\s+/)
    .filter((palavra) => palavra.length > 2);
  const nomeEncontrado =
    palavrasDoNome.length > 0 && palavrasDoNome.every((palavra) => textoNormalizado.includes(palavra));

  // Procura sequências de dígitos (com ou sem pontuação de CPF -- "123.456.789-00"
  // ou "12345678900") no texto ORIGINAL (não no normalizado, que já perdeu
  // a pontuação) e compara o que sobra depois de tirar a pontuação contra
  // o CPF cadastrado. Evitar concatenar TODOS os dígitos do documento antes
  // de comparar -- isso coincidiria por acaso com trechos de outros números
  // (RG, protocolo, data) que nada tem a ver com o CPF de verdade.
  const cpfEncontrado =
    params.cpf === null
      ? null
      : (params.texto.match(/[\d.\-/]{11,14}/g) ?? []).some(
          (trecho) => trecho.replace(/\D/g, '') === params.cpf,
        );

  return {
    palavrasChaveEncontradas,
    nomeEncontrado,
    cpfEncontrado,
    pareceDocumentoErrado: palavrasChaveEncontradas.length === 0,
  };
}
