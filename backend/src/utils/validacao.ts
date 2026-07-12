/**
 * Erro de entrada do usuário. O middleware de erro transforma isso em 400.
 * Qualquer outro erro vira 500.
 */
export class ErroDeValidacao extends Error {
  public readonly status = 400;

  constructor(mensagem: string) {
    super(mensagem);
    this.name = 'ErroDeValidacao';
  }
}

/**
 * Erro de CONFLITO -- ex.: e-mail/CPF/CNPJ que já existe. HTTP 409.
 * Diferente de ErroDeValidacao (400): o dado está bem formado, só que já
 * existe outro registro igual no banco.
 */
export class ErroDeConflito extends Error {
  public readonly status = 409;

  constructor(mensagem: string) {
    super(mensagem);
    this.name = 'ErroDeConflito';
  }
}

/**
 * Recurso não encontrado -- ex.: GET /servicos/:id com um UUID que não
 * existe na tabela. HTTP 404.
 */
export class ErroNaoEncontrado extends Error {
  public readonly status = 404;

  constructor(mensagem: string) {
    super(mensagem);
    this.name = 'ErroNaoEncontrado';
  }
}

/* ============================================================================
   Por que não `Number(req.query.latitude)` direto?

   Porque JavaScript:
     Number('')      === 0        <- string vazia vira zero!
     Number('  ')    === 0
     Number(null)    === 0
     Number('12abc') === NaN
     Number('1e999') === Infinity

   `?latitude=` (vazio) viraria latitude 0 -- que é uma coordenada VÁLIDA,
   no Golfo da Guiné. Sua busca retornaria zero resultados e você passaria a
   tarde procurando bug no SQL. Valide na porta de entrada.
   ========================================================================= */

/**
 * Converte um query param em número finito, ou lança 400.
 * Query params sempre chegam como string | string[] | undefined.
 */
export function numeroObrigatorio(valor: unknown, campo: string): number {
  if (valor === undefined || valor === null) {
    throw new ErroDeValidacao(`O parâmetro "${campo}" é obrigatório.`);
  }

  // ?latitude=1&latitude=2 chega como array. Recusamos.
  if (typeof valor !== 'string') {
    throw new ErroDeValidacao(`O parâmetro "${campo}" deve ser informado uma única vez.`);
  }

  const texto = valor.trim();
  if (texto === '') {
    throw new ErroDeValidacao(`O parâmetro "${campo}" não pode ser vazio.`);
  }

  const n = Number(texto);
  if (!Number.isFinite(n)) {
    throw new ErroDeValidacao(`O parâmetro "${campo}" deve ser um número. Recebido: "${texto}".`);
  }

  return n;
}

/** Converte, mas aceita ausência devolvendo o padrão. */
export function numeroOpcional(valor: unknown, campo: string, padrao: number): number {
  if (valor === undefined || valor === null || valor === '') return padrao;
  return numeroObrigatorio(valor, campo);
}

export function entre(n: number, min: number, max: number, campo: string): number {
  if (n < min || n > ma