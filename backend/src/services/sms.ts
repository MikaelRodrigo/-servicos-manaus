import crypto from 'crypto';
import { env } from '../env';

/* ============================================================================
   O QUE ESTE ARQUIVO FAZ

   Isola TODA a conversa com o futuro provedor de SMS (Twilio, Zenvia, AWS
   SNS...) atrás de um punhado de funções -- mesmo espírito de
   `services/pix-proprio.ts` e `services/cep.ts`: a ROTA
   (`routes/auth.routes.ts`) e o REPOSITORY
   (`repositories/verificacao-telefone.repository.ts`) nunca montam um
   payload nem leem uma resposta externa diretamente, só chamam estas
   funções.

   NENHUM PROVEDOR ESTÁ CONFIGURADO HOJE (o usuário ainda vai escolher um).
   Por isso este arquivo tem DOIS modos, no MESMO padrão de `pix-proprio.ts`:

     MODO SIMULADO (`env.sms.baseUrl` ausente -- o padrão em qualquer
     ambiente até um provedor real ser configurado): `enviarCodigoPorSms`
     GERA o código de 6 dígitos normalmente (é um código de verdade, dá pra
     usar pra confirmar), mas em vez de mandar pra operadora, só loga no
     console do servidor e devolve o código na própria resposta da API
     (`{ simulado: true, codigo: "123456" }`) -- é o que permite testar o
     fluxo inteiro (cadastro -> código -> confirmação -> login) sem
     nenhuma conta de SMS de verdade.

     MODO REAL (`env.sms.baseUrl` definida): tenta chamar a API de verdade.
     NÃO IMPLEMENTADO ainda -- lança `ErroDeSms` explicando que falta
     implementar contra o formato do provedor escolhido. Quando o provedor
     estiver definido, implemente `chamarApiSmsReal` abaixo seguindo a
     documentação dele.
   ========================================================================= */

/**
 * Erro de comunicação com o provedor de SMS -- mesmo papel que
 * `ErroDePixProprio` tem para a API Pix própria: HTTP 502 (nosso servidor
 * tentou falar com algo externo e deu errado), nunca 400 nem 500.
 */
export class ErroDeSms extends Error {
  public readonly status = 502;

  constructor(mensagem: string) {
    super(mensagem);
    this.name = 'ErroDeSms';
  }
}

function modoSimuladoAtivo(): boolean {
  return !env.sms.baseUrl;
}

/** Código numérico de 6 dígitos, com zeros à esquerda quando necessário (ex.: "004821"). */
export function gerarCodigoDeVerificacao(): string {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, '0');
}

export interface ResultadoEnvioSms {
  simulado: boolean;
  /** Só preenchido em MODO SIMULADO -- nunca devolva o código de verdade fora dele. */
  codigo?: string;
}

/**
 * Envia `codigo` por SMS para `numeroContato` (11 dígitos, DDD+número --
 * mesmo formato de `clientes.contato`/`profissionais.contato`). Quem chama
 * (`verificacao-telefone.repository.ts`) já gravou o HASH do código no
 * banco antes de chamar isto -- esta função só cuida do envio em si.
 */
export async function enviarCodigoPorSms(
  numeroContato: string,
  codigo: string,
): Promise<ResultadoEnvioSms> {
  if (modoSimuladoAtivo()) {
    // SEM chamada de rede nenhuma -- ver "MODO SIMULADO" no comentário do
    // topo. Loga no console do servidor (útil pra quem estiver olhando o
    // terminal do backend durante o teste) E devolve o código na resposta
    // da API, para quem estiver testando só pelo app/Postman também
    // conseguir confirmar sem precisar de acesso ao servidor.
    console.log(`[sms simulado] Código ${codigo} "enviado" para +55${numeroContato}`);
    return { simulado: true, codigo };
  }

  await chamarApiSmsReal(numeroContato, codigo);
  return { simulado: false };
}

/**
 * Chamada de verdade contra o provedor -- SEM IMPLEMENTAÇÃO ainda, porque
 * nenhum provedor foi escolhido. Quando escolher um (Twilio, Zenvia, AWS
 * SNS...), troque este corpo pela chamada HTTP real (autenticação via
 * `env.sms.apiKey`, endpoint documentado pelo provedor), seguindo o mesmo
 * padrão de `chamarComTimeout`/`AbortController` que `gateway-pagamento.ts`
 * (removido, ver histórico do Git) usava para o Pagar.me.
 */
async function chamarApiSmsReal(_numeroContato: string, _codigo: string): Promise<void> {
  throw new ErroDeSms(
    'SMS_PROVIDER_BASE_URL está configurada, mas a integração real ainda não foi implementada em services/sms.ts (função chamarApiSmsReal). Implemente contra o formato do provedor escolhido antes de usar em produção.',
  );
}
