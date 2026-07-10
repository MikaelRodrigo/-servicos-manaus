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
  if (n < min || n > max) {
    throw new ErroDeValidacao(`"${campo}" deve estar entre ${min} e ${max}. Recebido: ${n}.`);
  }
  return n;
}

/** String opcional, aparada e limitada. Devolve undefined se ausente. */
export function textoOpcional(valor: unknown, campo: string, maxLen = 100): string | undefined {
  if (valor === undefined || valor === null) return undefined;

  if (typeof valor !== 'string') {
    throw new ErroDeValidacao(`O parâmetro "${campo}" deve ser texto.`);
  }

  const texto = valor.trim();
  if (texto === '') return undefined;

  if (texto.length > maxLen) {
    throw new ErroDeValidacao(`"${campo}" excede ${maxLen} caracteres.`);
  }

  return texto;
}
