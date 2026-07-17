/* ============================================================================
   POR QUE ESTE ARQUIVO EXISTE

   `database.ts` tem um aviso explícito sobre a coluna NUMERIC do Postgres:

     "Se um dia entrar valor monetário aqui, REMOVA esta linha [o parser
     global `types.setTypeParser(1700, parseFloat)`] e trate como
     string/decimal."

   Esse dia chegou com a migração 14 (`transacoes.valor_servico`,
   `valor_total_cobrado`, `taxa_plataforma`, `valor_repasse_profissional`
   etc, todos NUMERIC(10,2)). NÃO removemos o parser global -- ele continua
   sendo usado por várias queries antigas que dependem de NUMERIC virar
   `number` automaticamente (distâncias, médias de avaliação) e reescrever
   tudo isso está fora do escopo desta etapa. Em vez disso, o repository de
   pagamentos (`transacoes.repository.ts`) evita o parser global nos
   pontos que importam:

     1. Toda coluna monetária é lida com `::text` explícito no SELECT --
        chega em JS como STRING exata ("49.90"), nunca como float.
     2. Todo valor monetário é ESCRITO como string (`"49.90"`), nunca como
        `number` calculado em JS -- o Postgres é quem faz a aritmética
        exata (`NUMERIC - NUMERIC` é exato; `float - float` não é).
     3. A ÚNICA vez que um valor monetário vira `number` em JS é na
        fronteira com o gateway (Pagar.me cobra em CENTAVOS, um inteiro) --
        é isso que as funções abaixo fazem, de forma isolada e testável.

   Nunca faça `valorA + valorB` com dois valores desta tabela lidos como
   `number` esperando um resultado financeiro exato -- se precisar somar/
   subtrair dinheiro, faça isso numa query SQL (`NUMERIC` é exato lá) ou
   usando as funções de centavos abaixo (inteiros somam/subtraem sem erro
   de ponto flutuante).
   ========================================================================= */

/**
 * "49.90" -> 4990. Usada só na fronteira com o gateway (Pagar.me espera
 * `amount` em centavos, inteiro). Faz a conversão via STRING (não
 * `Math.round(Number(texto) * 100)`) para nunca passar por uma
 * multiplicação em float64 -- ex.: `0.1 * 100` já não é exatamente `10` em
 * float64 puro; para valores de 2 casas fixas isso quase nunca aparece na
 * prática, mas "quase nunca" não é um padrão aceitável para dinheiro.
 */
export function valorParaCentavos(valorDecimal: string): number {
  const texto = valorDecimal.trim();
  if (!/^\d+(\.\d{1,2})?$/.test(texto)) {
    throw new Error(`[dinheiro] Valor monetário mal formado: "${valorDecimal}".`);
  }

  const [inteiro, decimalBruto = ''] = texto.split('.');
  // Sempre duas casas -- "49.9" e "49" viram "90" e "00".
  const decimal = decimalBruto.padEnd(2, '0');

  return Number(inteiro) * 100 + Number(decimal);
}

/** 4990 -> "49.90". Inverso de `valorParaCentavos`, para exibir/gravar de volta um valor que veio do gateway em centavos. */
export function centavosParaValor(centavos: number): string {
  if (!Number.isInteger(centavos)) {
    throw new Error(`[dinheiro] Centavos precisa ser um inteiro. Recebido: ${centavos}.`);
  }
  const negativo = centavos < 0;
  const absoluto = Math.abs(centavos);
  const inteiro = Math.floor(absoluto / 100);
  const decimal = String(absoluto % 100).padStart(2, '0');
  return `${negativo ? '-' : ''}${inteiro}.${decimal}`;
}
