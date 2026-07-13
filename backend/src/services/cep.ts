import { ErroDeValidacao } from '../utils/validacao';

/* ============================================================================
   GEOCODIFICAÇÃO POR CEP

   Este é o primeiro lugar do backend que fala com um serviço EXTERNO (fora
   do nosso próprio banco). Por isso mora numa pasta nova, `services/` --
   diferente de `repositories/` (só sabe falar com o NOSSO Postgres) e de
   `utils/` (funções puras, sem I/O nenhum).

   Usamos a BrasilAPI (https://brasilapi.com.br/api/cep/v2/{cep}), gratuita e
   sem necessidade de chave/cadastro. Ela devolve o endereço (rua, bairro,
   cidade, UF) E, quando consegue geocodificar via OpenStreetMap/Nominatim,
   a coordenada (`location.coordinates`). Preferimos a v2 (não a v1)
   exatamente por causa dessa coordenada -- é o que permite ao profissional
   aparecer na busca por proximidade do mapa (ST_DWithin, ver
   profissionais.repository.ts) só digitando um CEP, sem precisar de GPS.

   `fetch` é GLOBAL a partir do Node 18 (não precisa instalar node-fetch/axios
   -- ver "dependencies" em package.json, que de propósito não tem nenhum
   cliente HTTP: não faz falta).
   ========================================================================= */

export interface LocalizacaoPorCep {
  latitude: number;
  longitude: number;
  /** Ex.: "Rua Doutor Luiz de Freitas Melro, Centro, Blumenau - SC". */
  enderecoFormatado: string;
}

/** Só o que a gente lê da resposta da BrasilAPI -- ela devolve mais campos, ignoramos o resto. */
interface RespostaBrasilApiCepV2 {
  street?: string;
  neighborhood?: string;
  city?: string;
  state?: string;
  location?: {
    coordinates?: {
      // A BrasilAPI devolve como STRING, não number -- por isso convertemos
      // com Number(...) abaixo, nunca assumindo que já vem numérico.
      latitude?: string;
      longitude?: string;
    };
  };
}

/**
 * Consulta um CEP e devolve coordenadas + endereço formatado, prontos para
 * gravar em `profissionais.latitude`/`longitude`/`endereco_atuacao`.
 *
 * `cep` já deve chegar VALIDADO (8 dígitos, só números -- ver
 * `apenasDigitos` em utils/validacao.ts, chamado pela rota antes desta
 * função). Esta função só cuida da parte externa: consultar e interpretar
 * a resposta.
 *
 * Lança `ErroDeValidacao` (400) para QUALQUER falha -- CEP inexistente,
 * serviço fora do ar, ou CEP que existe mas o provedor de geocodificação não
 * conseguiu resolver coordenada (acontece com CEPs muito novos ou rurais).
 * Do ponto de vista de quem chamou a rota, o efeito é o mesmo nos três
 * casos: "não deu pra definir sua localização com esse CEP agora" -- por
 * isso um único tipo de erro, com mensagens diferentes por causa.
 */
export async function buscarLocalizacaoPorCep(cep: string): Promise<LocalizacaoPorCep> {
  let resposta: Response;
  try {
    resposta = await fetch(`https://brasilapi.com.br/api/cep/v2/${cep}`);
  } catch {
    // Falha de rede (DNS, timeout, serviço fora do ar) -- não é culpa do
    // usuário, mas também não temos como resolver aqui. Mensagem pede para
    // tentar de novo mais tarde, sem vazar detalhe técnico.
    throw new ErroDeValidacao(
      'Não foi possível consultar o CEP agora. Tente novamente em instantes.',
    );
  }

  if (!resposta.ok) {
    // A BrasilAPI devolve 404 quando nenhum provedor conhece o CEP.
    // Qualquer outro status (5xx, etc.) também vira "CEP não encontrado"
    // do ponto de vista do usuário -- não faz sentido diferenciar aqui.
    throw new ErroDeValidacao('CEP não encontrado. Confira os 8 dígitos e tente novamente.');
  }

  const dados = (await resposta.json()) as RespostaBrasilApiCepV2;

  const latitudeTexto = dados.location?.coordinates?.latitude;
  const longitudeTexto = dados.location?.coordinates?.longitude;

  // A BrasilAPI às vezes acha o ENDEREÇO mas não consegue geocodificar
  // (coordinates vem como objeto vazio `{}`) -- CEP existe, mas sem
  // coordenada não tem como definir a localização no mapa.
  if (!latitudeTexto || !longitudeTexto) {
    throw new ErroDeValidacao(
      'Não foi possível encontrar a localização exata desse CEP. Tente o CEP de uma rua ou avenida próxima.',
    );
  }

  const latitude = Number(latitudeTexto);
  const longitude = Number(longitudeTexto);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new ErroDeValidacao('Não foi possível encontrar a localização exata desse CEP.');
  }

  // Monta "Rua X, Bairro Y, Cidade - UF" pulando qualquer parte que não veio
  // (nem toda resposta tem `street`, por exemplo).
  const cidadeEstado = dados.city && dados.state ? `${dados.city} - ${dados.state}` : dados.city;
  const partes = [dados.street, dados.neighborhood, cidadeEstado].filter(
    (parte) => !!parte && parte.trim() !== '',
  );

  return {
    latitude,
    longitude,
    enderecoFormatado: partes.length > 0 ? partes.join(', ') : `CEP ${cep}`,
  };
}
