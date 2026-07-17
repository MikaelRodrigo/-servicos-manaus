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

/**
 * Inteiro positivo OPCIONAL vindo de QUERY STRING -- ex.: `?subcategoria_id=17`.
 * Devolve `undefined` quando ausente, em vez de lançar (diferente de
 * `inteiroPositivoObrigatorio`, que é para BODY de POST e não aceita ausência).
 */
export function inteiroPositivoOpcional(valor: unknown, campo: string): number | undefined {
  if (valor === undefined || valor === null || valor === '') return undefined;
  const n = numeroObrigatorio(valor, campo);
  if (!Number.isInteger(n) || n <= 0) {
    throw new ErroDeValidacao(`O parâmetro "${campo}" deve ser um número inteiro positivo.`);
  }
  return n;
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

/* ============================================================================
   VALIDADORES DE BODY (Etapa 4 - cadastro/login)

   Os validadores acima nasceram para query string (sempre string | undefined).
   Body de POST chega como JSON já desserializado -- um número pode chegar
   como number de verdade, uma data como string "1990-05-10", etc. Os
   validadores abaixo são para ESSE formato.
   ========================================================================= */

/** String obrigatória, aparada, com tamanho mínimo/máximo. */
export function textoObrigatorio(
  valor: unknown,
  campo: string,
  opcoes: { min?: number; max?: number } = {},
): string {
  const { min = 1, max = 255 } = opcoes;

  if (valor === undefined || valor === null || typeof valor !== 'string') {
    throw new ErroDeValidacao(`O campo "${campo}" é obrigatório e deve ser texto.`);
  }

  const texto = valor.trim();
  if (texto.length < min) {
    throw new ErroDeValidacao(`O campo "${campo}" precisa ter ao menos ${min} caractere(s).`);
  }
  if (texto.length > max) {
    throw new ErroDeValidacao(`O campo "${campo}" excede ${max} caracteres.`);
  }

  return texto;
}

/** Mesma regra do CHECK do banco (chk_*_email_formato) -- falhar aqui é mais barato que no Postgres. */
export function emailValido(valor: unknown, campo = 'email'): string {
  const texto = textoObrigatorio(valor, campo, { max: 255 }).toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(texto)) {
    throw new ErroDeValidacao(`O campo "${campo}" não parece um e-mail válido.`);
  }
  return texto;
}

/** Remove tudo que não é dígito e confere o tamanho. NÃO valida dígito verificador. */
export function apenasDigitos(valor: unknown, campo: string, tamanhoExato: number): string {
  const texto = textoObrigatorio(valor, campo, { max: 30 });
  const digitos = texto.replace(/\D/g, '');

  if (digitos.length !== tamanhoExato) {
    throw new ErroDeValidacao(
      `O campo "${campo}" deve ter ${tamanhoExato} dígitos. Recebido: "${valor}".`,
    );
  }

  return digitos;
}

/**
 * Senha em texto puro, ainda ANTES do hash. Espelha a regex de
 * `senhaAtendeRequisitosMinimos` em senha.ts -- mantidas em arquivos
 * diferentes porque uma é regra de ENTRADA (aqui) e a outra é regra de
 * DOMÍNIO (lá), mas o motivo de existirem é o mesmo.
 */
export function senhaObrigatoria(valor: unknown, campo = 'senha'): string {
  if (valor === undefined || valor === null || typeof valor !== 'string') {
    throw new ErroDeValidacao(`O campo "${campo}" é obrigatório.`);
  }
  if (valor.length < 8) {
    throw new ErroDeValidacao(`O campo "${campo}" precisa ter ao menos 8 caracteres.`);
  }
  if (!/[A-Za-z]/.test(valor) || !/\d/.test(valor)) {
    throw new ErroDeValidacao(`O campo "${campo}" precisa ter letras e números.`);
  }
  return valor;
}

/** Data no formato "AAAA-MM-DD", convertida e validada. */
export function dataObrigatoria(valor: unknown, campo: string): string {
  const texto = textoObrigatorio(valor, campo, { max: 10 });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(texto) || Number.isNaN(Date.parse(texto))) {
    throw new ErroDeValidacao(`O campo "${campo}" deve estar no formato AAAA-MM-DD.`);
  }
  return texto;
}

/**
 * Número vindo de BODY JSON (não de query string). Diferença importante:
 * `numeroObrigatorio` (lá em cima) exige `typeof valor === 'string'` porque
 * query params SEMPRE chegam como string. Body de POST com Content-Type
 * application/json chega DESSERIALIZADO -- `{"latitude": -3.13}` vira um
 * `number` de verdade no `req.body.latitude`. Se você chamar o validador de
 * query aqui, ele rejeita todo número válido com "deve ser informado uma
 * única vez". Por isso este validador aceita `number` OU `string`.
 */
export function numeroDoBody(valor: unknown, campo: string): number {
  if (valor === undefined || valor === null) {
    throw new ErroDeValidacao(`O campo "${campo}" é obrigatório.`);
  }

  if (typeof valor === 'number') {
    if (!Number.isFinite(valor)) {
      throw new ErroDeValidacao(`O campo "${campo}" deve ser um número finito.`);
    }
    return valor;
  }

  if (typeof valor === 'string') {
    const texto = valor.trim();
    const n = Number(texto);
    if (texto === '' || !Number.isFinite(n)) {
      throw new ErroDeValidacao(`O campo "${campo}" deve ser um número. Recebido: "${valor}".`);
    }
    return n;
  }

  throw new ErroDeValidacao(`O campo "${campo}" deve ser um número.`);
}

/**
 * Inteiro positivo vindo de BODY JSON -- ex.: `categoria_id`, `subcategoria_id`.
 * Mesma ideia de `notaObrigatoria` (número inteiro + faixa), mas sem teto
 * fixo: quem chama decide se o valor existe de verdade consultando o banco
 * (a FK cuida disso -- ver `PG_FOREIGN_KEY_VIOLATION` em erros-postgres.ts).
 */
export function inteiroPositivoObrigatorio(valor: unknown, campo: string): number {
  const n = numeroDoBody(valor, campo);
  if (!Number.isInteger(n) || n <= 0) {
    throw new ErroDeValidacao(`O campo "${campo}" deve ser um número inteiro positivo.`);
  }
  return n;
}

/** enum literal 'PF' | 'PJ' -- qualquer outra coisa é 400. */
export function tipoPessoaObrigatorio(valor: unknown, campo = 'tipo_pessoa'): 'PF' | 'PJ' {
  if (valor !== 'PF' && valor !== 'PJ') {
    throw new ErroDeValidacao(`O campo "${campo}" deve ser "PF" ou "PJ". Recebido: ${valor}.`);
  }
  return valor;
}

/* ============================================================================
   VALIDADORES DO MÓDULO DE SERVIÇOS

   id_servico, cliente_id e profissional_id são todos UUID (é o tipo da
   PRIMARY KEY no schema, gerado por gen_random_uuid()). Um UUID mal formado
   NUNCA vai casar com nenhuma linha -- mas é melhor barrar isso aqui, com
   uma mensagem clara, do que deixar o Postgres devolver um erro de sintaxe
   feio ("invalid input syntax for type uuid").
   ========================================================================= */
const REGEX_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function uuidObrigatorio(valor: unknown, campo: string): string {
  if (typeof valor !== 'string' || !REGEX_UUID.test(valor)) {
    throw new ErroDeValidacao(`O campo "${campo}" deve ser um UUID válido.`);
  }
  return valor;
}

/**
 * Espelha o ENUM `status_servico_enum` do banco (Seção 1 do 01_schema.sql).
 * Se um dia você adicionar um status novo no banco, adicione aqui também --
 * TypeScript não lê o schema do Postgres sozinho.
 */
export const STATUS_SERVICO_VALIDOS = [
  'SOLICITADO',
  'ACEITO',
  'EM_ANDAMENTO',
  'CONCLUIDO',
  'CANCELADO',
  'RECUSADO',
] as const;

export type StatusServico = (typeof STATUS_SERVICO_VALIDOS)[number];

/** Filtro OPCIONAL de status na query string (?status=ACEITO). */
export function statusServicoOpcional(valor: unknown, campo = 'status'): StatusServico | undefined {
  const texto = textoOpcional(valor, campo, 20);
  if (texto === undefined) return undefined;

  const maiuscula = texto.toUpperCase();
  if (!(STATUS_SERVICO_VALIDOS as readonly string[]).includes(maiuscula)) {
    throw new ErroDeValidacao(
      `"${campo}" deve ser um de: ${STATUS_SERVICO_VALIDOS.join(', ')}. Recebido: "${texto}".`,
    );
  }
  return maiuscula as StatusServico;
}

/* ============================================================================
   VALIDADORES DO MÓDULO DE AVALIAÇÕES

   Todas as colunas de nota são SMALLINT com CHECK (... BETWEEN 1 AND 5) no
   banco (Seções 6 e 7 do 01_schema.sql). Validar aqui também não é
   redundância inútil -- é a diferença entre o usuário receber "estrelas_
   tecnico deve ser de 1 a 5" (400, claro) e receber um erro cru de
   constraint do Postgres (feio, e vaza nome de coluna interna).
   ========================================================================= */
export function notaObrigatoria(valor: unknown, campo: string): number {
  const n = numeroDoBody(valor, campo);
  if (!Number.isInteger(n) || n < 1 || n > 5) {
    throw new ErroDeValidacao(`O campo "${campo}" deve ser um número inteiro de 1 a 5.`);
  }
  return n;
}

/* ============================================================================
   VALIDADORES DO MÓDULO DE PAGAMENTOS (migração 14 --
   14_pagamentos_escrow_split.sql)

   Cada `*_VALIDOS`/`type Status*` abaixo espelha, 1:1, um ENUM do banco.
   Mesma regra de sempre: o Postgres não expõe o próprio schema para o
   TypeScript, então um enum novo no SQL PRECISA ser copiado aqui também --
   nada aqui é derivado automaticamente.
   ========================================================================= */

export const STATUS_TRANSACAO_VALIDOS = [
  'PENDENTE',
  'AUTORIZADA',
  'FALHOU',
  'EM_DISPUTA',
  'LIBERADA',
  'REEMBOLSADA',
] as const;
export type StatusTransacao = (typeof STATUS_TRANSACAO_VALIDOS)[number];

export const METODO_PAGAMENTO_VALIDOS = ['PIX', 'CARTAO'] as const;
export type MetodoPagamento = (typeof METODO_PAGAMENTO_VALIDOS)[number];

export const STATUS_ESCROW_VALIDOS = ['RETIDO', 'LIBERADO', 'REEMBOLSADO'] as const;
export type StatusEscrow = (typeof STATUS_ESCROW_VALIDOS)[number];

export const STATUS_DISPUTA_VALIDOS = [
  'ABERTA',
  'EM_MEDIACAO',
  'RESOLVIDA_CLIENTE',
  'RESOLVIDA_PROFISSIONAL',
] as const;
export type StatusDisputa = (typeof STATUS_DISPUTA_VALIDOS)[number];

export const STATUS_NOTA_FISCAL_VALIDOS = ['PENDENTE', 'EMITIDA', 'ERRO'] as const;
export type StatusNotaFiscal = (typeof STATUS_NOTA_FISCAL_VALIDOS)[number];

/** enum literal 'PIX' | 'CARTAO' vindo de BODY -- qualquer outra coisa é 400. */
export function metodoPagamentoObrigatorio(valor: unknown, campo = 'metodo_pagamento'): MetodoPagamento {
  if (valor !== 'PIX' && valor !== 'CARTAO') {
    throw new ErroDeValidacao(`O campo "${campo}" deve ser "PIX" ou "CARTAO". Recebido: ${valor}.`);
  }
  return valor;
}

/**
 * Parcelas -- só faz sentido para CARTAO (ver `chk_transacao_parcelas_coerentes`
 * na migração 14: PIX é sempre 1x). Aceita ausência (padrão 1), mas nunca
 * aceita um valor fora de 1-12 -- 12x é o teto comum de qualquer adquirente
 * brasileira; um valor maior quase certo é erro de input, não uma parcela
 * real que o gateway aceitaria.
 */
export function parcelasOpcional(valor: unknown, campo = 'parcelas'): number {
  if (valor === undefined || valor === null) return 1;
  const n = numeroDoBody(valor, campo);
  if (!Number.isInteger(n) || n < 1 || n > 12) {
    throw new ErroDeValidacao(`O campo "${campo}" deve ser um número inteiro de 1 a 12.`);
  }
  return n;
}

/**
 * Valor monetário em BODY JSON, como STRING decimal ("49.90") -- de
 * propósito NÃO aceita `number` aqui (diferente de `numeroDoBody`): um
 * valor monetário que chega como `number` já passou por uma
 * (des)serialização em float64 do lado do cliente, o que é exatamente o
 * problema que `utils/dinheiro.ts` documenta. Exigir string obriga quem
 * chama esta API a mandar o valor formatado por extenso ("49.90", não
 * `49.9` nem `49.900000000000006`), que é o único formato que
 * `valorParaCentavos` consegue converter sem ambiguidade.
 */
export function valorMonetarioObrigatorio(valor: unknown, campo: string): string {
  if (typeof valor !== 'string' || !/^\d+(\.\d{1,2})?$/.test(valor.trim())) {
    throw new ErroDeValidacao(
      `O campo "${campo}" deve ser um valor monetário em texto, com até 2 casas decimais (ex.: "49.90"). Recebido: ${JSON.stringify(valor)}.`,
    );
  }
  const texto = valor.trim();
  if (Number(texto) <= 0) {
    throw new ErroDeValidacao(`O campo "${campo}" deve ser maior que zero.`);
  }
  return texto;
}
