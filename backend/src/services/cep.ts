import { ErroDeValidacao } from '../utils/validacao';

/* ============================================================================
   GEOCODIFICAÇÃO POR CEP

   Este é o primeiro lugar do backend que fala com serviços EXTERNOS (fora
   do nosso próprio banco). Por isso mora numa pasta nova, `services/` --
   diferente de `repositories/` (só sabe falar com o NOSSO Postgres) e de
   `utils/` (funções puras, sem I/O nenhum).

   POR QUE DOIS SERVIÇOS (ViaCEP + Nominatim) EM VEZ DE UM SÓ?

   A primeira versão usava a BrasilAPI v2 (que devolve endereço E coordenada
   numa chamada só). Na prática, para CEPs de Manaus/Norte a coordenada veio
   vazia com frequência -- a geocodificação embutida da BrasilAPI usa
   OpenStreetMap/Nominatim, e a cobertura de endereço-a-ponto do OSM no
   Norte do Brasil é bem mais fraca que no Sul/Sudeste. CEP existe, endereço
   é encontrado, mas "onde fica no mapa" não tem resposta -- e a rota
   simplesmente falhava.

   A solução: separar as duas responsabilidades.
     1) ViaCEP (https://viacep.com.br) -- SÓ acha o endereço a partir do CEP.
        Não tenta geocodificar, então não tem esse jeito de falhar; para
        qualquer CEP válido, o endereço vem quase sempre.
     2) Nominatim (https://nominatim.openstreetmap.org) -- geocodificamos
        NÓS MESMOS, com uma ESCADA de tentativas cada vez mais genéricas:
        rua+bairro+cidade -> bairro+cidade -> só cidade. Se o endereço exato
        não geocodificar, caímos para o bairro; se nem o bairro, caímos para
        o centro da cidade. Uma cidade inteira SEMPRE existe no OSM -- então
        no pior caso o profissional aparece no centro da cidade dele (ainda
        útil: aparece na busca por proximidade) em vez de a atualização de
        perfil simplesmente falhar.
   ========================================================================= */

export interface LocalizacaoPorCep {
  latitude: number;
  longitude: number;
  /** Ex.: "Rua Doutor Luiz de Freitas Melro, Centro, Manaus - AM". */
  enderecoFormatado: string;
}

export interface RespostaViaCep {
  erro?: boolean;
  logradouro?: string;
  bairro?: string;
  localidade?: string; // cidade
  uf?: string;
}

interface ResultadoNominatim {
  lat: string;
  lon: string;
}

/** Nominatim exige um User-Agent identificando a aplicação -- é a política deles, não uma chave de API. */
const USER_AGENT_NOMINATIM = 'servicos-manaus-app/1.0 (uso interno, geocodificacao de CEP)';

/** Timeout curto em cada chamada externa -- não faz sentido a atualização de perfil travar minutos esperando um serviço fora do ar. */
async function buscarComTimeout(url: string, cabecalhos: Record<string, string> = {}, timeoutMs = 8000): Promise<Response> {
  const controlador = new AbortController();
  const temporizador = setTimeout(() => controlador.abort(), timeoutMs);
  try {
    return await fetch(url, { headers: cabecalhos, signal: controlador.signal });
  } finally {
    clearTimeout(temporizador);
  }
}

/**
 * Busca o endereço (rua/bairro/cidade/UF) de um CEP via ViaCEP.
 *
 * `cep` já deve chegar VALIDADO (8 dígitos -- ver `apenasDigitos` em
 * utils/validacao.ts, chamado pela rota antes desta função).
 *
 * EXPORTADA (antes era só uso interno) porque `GET /cep/:cep` (ver
 * routes/cep.routes.ts) reaproveita ela sozinha, SEM a etapa de
 * geocodificação abaixo -- é o autofill em tempo real do formulário
 * (rua/bairro/cidade enquanto o profissional digita o CEP), que não
 * precisa de coordenada nenhuma ainda. A geocodificação de verdade só
 * acontece quando o perfil é salvo (`buscarLocalizacaoPorCep`, chamada por
 * `PATCH /profissionais/me`).
 */
export async function buscarEnderecoPorCep(cep: string): Promise<RespostaViaCep> {
  let resposta: Response;
  try {
    resposta = await buscarComTimeout(`https://viacep.com.br/ws/${cep}/json/`);
  } catch {
    throw new ErroDeValidacao(
      'Não foi possível consultar o CEP agora. Tente novamente em instantes.',
    );
  }

  if (!resposta.ok) {
    throw new ErroDeValidacao('Não foi possível consultar o CEP agora. Tente novamente em instantes.');
  }

  const dados = (await resposta.json()) as RespostaViaCep;

  // ViaCEP devolve HTTP 200 mesmo para CEP inexistente -- o jeito de saber
  // é o campo `erro: true` no corpo da resposta.
  if (dados.erro) {
    throw new ErroDeValidacao('CEP não encontrado. Confira os 8 dígitos e tente novamente.');
  }

  return dados;
}

/**
 * Geocodifica UM texto de busca via Nominatim. Devolve `null` (não lança
 * erro) quando não encontra nada -- é o sinal para `buscarLocalizacaoPorCep`
 * tentar a próxima tentativa da escada, mais genérica.
 */
async function geocodificar(query: string): Promise<{ latitude: number; longitude: number } | null> {
  const url = `https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=br&q=${encodeURIComponent(query)}`;

  let resposta: Response;
  try {
    resposta = await buscarComTimeout(url, { 'User-Agent': USER_AGENT_NOMINATIM });
  } catch {
    return null;
  }

  if (!resposta.ok) return null;

  const resultados = (await resposta.json()) as ResultadoNominatim[];
  if (resultados.length === 0) return null;

  const latitude = Number(resultados[0].lat);
  const longitude = Number(resultados[0].lon);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

  return { latitude, longitude };
}

/**
 * Consulta um CEP e devolve coordenadas + endereço formatado, prontos para
 * gravar em `profissionais.latitude`/`longitude`/`endereco_atuacao`.
 *
 * Tenta geocodificar do mais PRECISO para o mais GENÉRICO, parando na
 * primeira tentativa que funcionar:
 *   1. rua + bairro + cidade - UF
 *   2. bairro + cidade - UF
 *   3. cidade - UF   (quase sempre funciona -- é o "pior caso aceitável")
 *
 * Só lança `ErroDeValidacao` se o CEP nem existir (ViaCEP) ou se ATÉ o
 * nível de cidade falhar geocodificar (raríssimo -- praticamente só
 * aconteceria com Nominatim fora do ar).
 */
export async function buscarLocalizacaoPorCep(cep: string): Promise<LocalizacaoPorCep> {
  const endereco = await buscarEnderecoPorCep(cep);

  const cidadeEstado =
    endereco.localidade && endereco.uf ? `${endereco.localidade} - ${endereco.uf}` : endereco.localidade;

  // Cada item é uma tentativa de geocodificação, da mais específica pra
  // mais genérica. `null` é filtrado -- não faz sentido tentar geocodificar
  // uma query vazia porque o ViaCEP não devolveu aquele campo.
  const tentativas = [
    endereco.logradouro && endereco.bairro && cidadeEstado
      ? `${endereco.logradouro}, ${endereco.bairro}, ${cidadeEstado}, Brasil`
      : null,
    endereco.bairro && cidadeEstado ? `${endereco.bairro}, ${cidadeEstado}, Brasil` : null,
    cidadeEstado ? `${cidadeEstado}, Brasil` : null,
  ].filter((query): query is string => query !== null);

  let coordenada: { latitude: number; longitude: number } | null = null;
  for (const tentativa of tentativas) {
    coordenada = await geocodificar(tentativa);
    if (coordenada) break;
  }

  if (!coordenada) {
    throw new ErroDeValidacao(
      'Não foi possível encontrar a localização desse CEP agora. Tente novamente em instantes.',
    );
  }

  const partes = [endereco.logradouro, endereco.bairro, cidadeEstado].filter(
    (parte): parte is string => !!parte && parte.trim() !== '',
  );

  return {
    latitude: coordenada.latitude,
    longitude: coordenada.longitude,
    enderecoFormatado: partes.length > 0 ? partes.join(', ') : `CEP ${cep}`,
  };
}
