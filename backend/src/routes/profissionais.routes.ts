import { Router, Request, Response, NextFunction } from 'express';
import { env } from '../env';
import { buscarProximos, buscarPerfilPublico, atualizarPerfilProfissional } from '../repositories/profissionais.repository';
import {
  numeroObrigatorio,
  numeroOpcional,
  textoOpcional,
  inteiroPositivoOpcional,
  apenasDigitos,
  entre,
  uuidObrigatorio,
  ErroNaoEncontrado,
  ErroDeValidacao,
} from '../utils/validacao';
import { buscarPortifolio, buscarResumoDeAvaliacoes } from '../repositories/avaliacoes.repository';
import { exigirAutenticacao, exigirPapel, autenticacaoOpcional } from '../middlewares/autenticacao';
import { uploadFotoPerfil, urlPublicaDoArquivoPerfil } from '../middlewares/upload';
import { buscarLocalizacaoPorCep } from '../services/cep';
import { ehErroDePostgres, PG_FOREIGN_KEY_VIOLATION } from '../utils/erros-postgres';

export const profissionaisRouter = Router();

/**
 * GET /profissionais/proximos
 *
 * Query params:
 *   latitude   (obrigatório)  -3.13013
 *   longitude  (obrigatório)  -60.02340
 *   raio_km         (opcional)  padrão 5, máximo RAIO_MAXIMO_KM
 *   profissao       (opcional)  "eletricista" -- busca livre (legado)
 *   subcategoria_id (opcional)  17 -- filtro EXATO, o que o app usa hoje
 *                               (ver BuscaSubcategoriaAutocomplete no Flutter)
 *   ordenar_por     (opcional)  padrão "distancia" -- uma das três opções
 *                               abaixo, ver ORDENACOES_VALIDAS:
 *                                 distancia               (padrão, mais perto primeiro)
 *                                 melhor_custo_beneficio   (média do critério "econômico" das avaliações)
 *                                 melhores_avaliados       (média geral das avaliações)
 *   pagina          (opcional)  padrão 1
 *   limite          (opcional)  padrão 20, máximo 100
 *
 * Exemplo:
 *   /profissionais/proximos?latitude=-3.13013&longitude=-60.02340&raio_km=5&ordenar_por=melhores_avaliados
 */
const ORDENACOES_VALIDAS = ['distancia', 'melhor_custo_beneficio', 'melhores_avaliados'] as const;
type Ordenacao = (typeof ORDENACOES_VALIDAS)[number];
profissionaisRouter.get(
  '/proximos',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      /* ---------------------------------------------------------------
         PASSO 1 - VALIDAR. Sempre antes de tocar no banco.

         Nada abaixo desta seção pode assumir que a entrada é confiável,
         porque a partir daqui ela é.
         --------------------------------------------------------------- */
      const latitude = entre(
        numeroObrigatorio(req.query.latitude, 'latitude'),
        -90,
        90,
        'latitude',
      );

      const longitude = entre(
        numeroObrigatorio(req.query.longitude, 'longitude'),
        -180,
        180,
        'longitude',
      );

      // O teto do raio vem do .env. Sem teto, `?raio_km=999999` faz o
      // Postgres varrer a tabela inteira a cada request.
      const raioKm = entre(
        numeroOpcional(req.query.raio_km, 'raio_km', 5),
        0.1,
        env.raioMaximoKm,
        'raio_km',
      );

      const profissao = textoOpcional(req.query.profissao, 'profissao', 100);
      const subcategoriaId = inteiroPositivoOpcional(req.query.subcategoria_id, 'subcategoria_id');

      // Sem validador genérico de "enum" em validacao.ts hoje -- uma lista
      // fechada + `includes` já resolve, sem precisar criar um validador
      // novo só para este caso único.
      const ordenarPorBruto = req.query.ordenar_por;
      let ordenarPor: Ordenacao = 'distancia';
      if (ordenarPorBruto !== undefined) {
        if (
          typeof ordenarPorBruto !== 'string' ||
          !ORDENACOES_VALIDAS.includes(ordenarPorBruto as Ordenacao)
        ) {
          throw new ErroDeValidacao(
            `"ordenar_por" precisa ser um de: ${ORDENACOES_VALIDAS.join(', ')}.`,
          );
        }
        ordenarPor = ordenarPorBruto as Ordenacao;
      }

      const pagina = entre(numeroOpcional(req.query.pagina, 'pagina', 1), 1, 1000, 'pagina');
      const limite = entre(numeroOpcional(req.query.limite, 'limite', 20), 1, 100, 'limite');

      /* ---------------------------------------------------------------
         PASSO 2 - CONVERTER para o que o domínio entende.

         A API fala em quilômetros porque é o que faz sentido para quem
         usa o app. O PostGIS, com geography, fala em metros. A conversão
         acontece aqui, numa linha, e nunca mais se pensa nela.
         --------------------------------------------------------------- */
      const raioMetros = Math.round(raioKm * 1000);
      const offset = (pagina - 1) * limite;

      /* ---------------------------------------------------------------
         PASSO 3 - CONSULTAR.
         --------------------------------------------------------------- */
      const profissionais = await buscarProximos({
        latitude,
        longitude,
        raioMetros,
        profissao,
        subcategoriaId,
        limite,
        offset,
        ordenarPor,
      });

      /* ---------------------------------------------------------------
         PASSO 4 - RESPONDER.

         Devolvo um objeto com metadados, não um array cru. Quando o
         Flutter precisar de paginação (Etapa 7), o contrato já existe e
         você não quebra o app dos usuários.
         --------------------------------------------------------------- */
      return res.json({
        parametros: {
          latitude,
          longitude,
          raio_km: raioKm,
          profissao: profissao ?? null,
          subcategoria_id: subcategoriaId ?? null,
          ordenar_por: ordenarPor,
        },
        pagina,
        limite,
        total_retornado: profissionais.length,
        dados: profissionais,
      });
    } catch (erro) {
      // Não trate o erro aqui. Empurre para o middleware central
      // (veja app.ts). Um lugar só para formatar erro = respostas
      // consistentes e nenhum stack trace vazando pro cliente.
      return next(erro);
    }
  },
);

/* ============================================================================
   PATCH /profissionais/me -- PRIVADA (exige login, só "profissional").

   Edita o PRÓPRIO perfil público: descrição ("sobre mim"), CEP (que define
   onde o profissional aparece no mapa) e/ou foto de perfil. Repare que não
   existe `:id` na URL -- de propósito. O profissional editado é sempre
   `req.usuario.sub` (quem está logado), nunca um ID escolhido no corpo da
   request. Isso elimina de saída qualquer risco de um profissional editar
   o perfil de outro só trocando um ID no JSON.

   Content-Type: multipart/form-data
   Campos (todos opcionais, mas ao menos um precisa vir):
     descricao      (texto, até 2000 caracteres)
     cep            (texto, 8 dígitos) -- geocodificado nesta rota: define
                    latitude/longitude (o que alimenta a busca por
                    proximidade do mapa) e substitui endereco_atuacao pelo
                    endereço formatado que a geocodificação devolveu.
     categoria_id    (inteiro) -- só junto com subcategoria_id, os dois ou
     subcategoria_id (inteiro)    nenhum. A FK composta da migração 09
                    (fk_profissionais_subcategoria_categoria) recusa um par
                    incoerente -- ver SeletorCategoriaCascata no app.
     foto_perfil    (arquivo -- JPEG, PNG ou WEBP, até 5 MB)

   É rota PATCH, não POST: estamos atualizando um recurso que já existe (o
   cadastro do profissional), não criando um novo.
   ========================================================================= */
profissionaisRouter.patch(
  '/me',
  exigirAutenticacao,
  exigirPapel('profissional'),
  uploadFotoPerfil,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const descricao = textoOpcional(req.body.descricao, 'descricao', 2000);
      const urlFotoPerfil = req.file ? urlPublicaDoArquivoPerfil(req.file) : undefined;

      // CEP é opcional (o campo pode não vir no request), mas QUANDO vem,
      // precisa ter exatamente 8 dígitos -- mesma convenção de `contato`
      // no cadastro (ver auth.routes.ts).
      const cepBruto =
        req.body.cep !== undefined && req.body.cep !== null && req.body.cep !== ''
          ? apenasDigitos(req.body.cep, 'cep', 8)
          : undefined;

      // `categoria_id`/`subcategoria_id` só existem JUNTOS -- mesmo espírito
      // do trio cep/latitude/longitude abaixo. A coerência do PAR (a
      // subcategoria de fato pertencer à categoria) fica por conta da FK
      // composta do banco; aqui só garantimos que os dois vieram ou nenhum
      // veio, antes de chamar o repository.
      const categoriaId = inteiroPositivoOpcional(req.body.categoria_id, 'categoria_id');
      const subcategoriaId = inteiroPositivoOpcional(req.body.subcategoria_id, 'subcategoria_id');
      if ((categoriaId === undefined) !== (subcategoriaId === undefined)) {
        throw new ErroDeValidacao(
          'Envie "categoria_id" e "subcategoria_id" juntos, para trocar a categoria.',
        );
      }

      if (
        descricao === undefined &&
        cepBruto === undefined &&
        urlFotoPerfil === undefined &&
        categoriaId === undefined
      ) {
        throw new ErroDeValidacao(
          'Envie ao menos "descricao", "cep", "categoria_id"/"subcategoria_id" ou uma foto ("foto_perfil") para atualizar.',
        );
      }

      // `cep`, `latitude`, `longitude` e `enderecoAtuacao` só existem
      // JUNTOS: um único CEP gera as quatro informações de uma vez, via
      // geocodificação (ver services/cep.ts). Se `cepBruto` não veio,
      // nenhum dos quatro é passado adiante -- o COALESCE no repository
      // mantém tudo como já estava.
      let localizacao: { latitude: number; longitude: number; enderecoFormatado: string } | undefined;
      if (cepBruto !== undefined) {
        localizacao = await buscarLocalizacaoPorCep(cepBruto);
      }

      const perfilAtualizado = await atualizarPerfilProfissional(req.usuario!.sub, {
        descricao,
        urlFotoPerfil,
        cep: cepBruto,
        latitude: localizacao?.latitude,
        longitude: localizacao?.longitude,
        enderecoAtuacao: localizacao?.enderecoFormatado,
        categoriaId,
        subcategoriaId,
      });

      return res.json(perfilAtualizado);
    } catch (erro) {
      // `subcategoria_id` não existe, ou existe mas não pertence à
      // `categoria_id` informada -- a FK composta (migração 09) recusa o
      // UPDATE nos dois casos. Mesma tradução usada no cadastro
      // (auth.routes.ts).
      if (ehErroDePostgres(erro) && erro.code === PG_FOREIGN_KEY_VIOLATION) {
        return next(
          new ErroDeValidacao('Categoria/subcategoria inválida. Selecione novamente na lista.'),
        );
      }
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /profissionais/:id -- PÚBLICA (sem login).

   Perfil público completo: foto, descrição, atuação, endereço de atuação.
   NÃO inclui contato (telefone/WhatsApp) -- ver comentário em
   `PerfilPublicoProfissional` no repository. É a tela que abre quando o
   cliente toca no pino do profissional no mapa.

   IMPORTANTE sobre ordem de rotas no Express: esta rota usa `:id`, que
   casa com QUALQUER segmento único de URL. Ela só pode ficar registrada
   DEPOIS de `/proximos` (linha ~31) -- senão `/proximos` seria interpretado
   como se ":id" fosse o texto "proximos", e a rota de busca nunca seria
   alcançada. Como `/proximos` já vem antes no arquivo, estamos seguros.
   ========================================================================= */
profissionaisRouter.get(
  '/:id',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const profissionalId = uuidObrigatorio(req.params.id, 'id');
      const perfil = await buscarPerfilPublico(profissionalId);

      if (!perfil) {
        throw new ErroNaoEncontrado('Profissional não encontrado.');
      }

      return res.json(perfil);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /profissionais/:id/portfolio -- PÚBLICA (sem login).

   É a "vitrine" do profissional: fotos + comentários dos serviços que ele
   já concluiu, vindos direto da view `vw_historico_portifolio`. Pública de
   propósito -- é o que convence um cliente novo a contratar, ele precisa
   ver isso ANTES de criar conta.

   `autenticacaoOpcional` (não `exigirAutenticacao`): a rota continua
   funcionando sem login, mas quando a pessoa ESTÁ logada, `req.usuario`
   fica preenchido e usamos o ID dela para marcar quais avaliações ela já
   curtiu (`curtido_por_mim` -- ver botão "Útil" em curtidas.routes.ts).

   Query params: pagina (padrão 1), limite (padrão 20, máximo 100)
   ========================================================================= */
profissionaisRouter.get(
  '/:id/portfolio',
  autenticacaoOpcional,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const profissionalId = uuidObrigatorio(req.params.id, 'id');
      const pagina = entre(numeroOpcional(req.query.pagina, 'pagina', 1), 1, 1000, 'pagina');
      const limite = entre(numeroOpcional(req.query.limite, 'limite', 20), 1, 100, 'limite');
      const offset = (pagina - 1) * limite;

      const portfolio = await buscarPortifolio(
        profissionalId,
        { limite, offset },
        req.usuario?.sub,
      );

      return res.json({ pagina, limite, total_retornado: portfolio.length, dados: portfolio });
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /profissionais/:id/avaliacoes/resumo -- PÚBLICA (sem login).

   As médias por critério + total de avaliações. É o número que vira
   estrelinha ao lado do nome do profissional na busca do mapa.
   Sem avaliação nenhuma ainda, as médias voltam `null` (não `0` -- 0
   estrelas pareceria "profissional ruim"; `null` é "ainda sem avaliação").
   ========================================================================= */
profissionaisRouter.get(
  '/:id/avaliacoes/resumo',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const profissionalId = uuidObrigatorio(req.params.id, 'id');
      const resumo = await buscarResumoDeAvaliacoes(profissionalId);
      return res.json(resumo);
    } catch (erro) {
      return next(erro);
    }
  },
);
