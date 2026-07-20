import { Router, Request, Response, NextFunction } from 'express';
import { env } from '../env';
import {
  buscarProximos,
  buscarMeuPerfil,
  buscarPerfilPublico,
  atualizarPerfilProfissional,
  listarTagsDoProfissional,
  adicionarTagAoProfissional,
  removerTagDoProfissional,
  listarPortfolioFotos,
  contarFotosPortfolio,
  adicionarFotosPortfolio,
  removerFotoPortfolio,
} from '../repositories/profissionais.repository';
import {
  numeroObrigatorio,
  numeroOpcional,
  textoOpcional,
  inteiroPositivoOpcional,
  inteiroPositivoObrigatorio,
  apenasDigitos,
  entre,
  uuidObrigatorio,
  ErroNaoEncontrado,
  ErroDeValidacao,
} from '../utils/validacao';
import { buscarPortifolio, buscarResumoDeAvaliacoes } from '../repositories/avaliacoes.repository';
import { exigirAutenticacao, exigirPapel, autenticacaoOpcional } from '../middlewares/autenticacao';
import {
  uploadFotoPerfil,
  urlPublicaDoArquivoPerfil,
  uploadFotosPortfolio,
  urlsPublicasDosArquivos,
  MAX_FOTOS_TOTAL_PORTFOLIO,
} from '../middlewares/upload';
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

      // Teto bem mais alto que o normal (outras rotas paginadas ficam em
      // 100) porque este é o único caso onde "página cortada" pode passar
      // a impressão de bug de filtro: o mapa quer mostrar TODO MUNDO
      // dentro do raio escolhido (é um "cerco" geográfico, não uma lista
      // navegável) -- se alguém aumenta o raio de 2km pra 15km e o número
      // de profissionais na área passa de 100, o antigo teto cortaria os
      // mais distantes silenciosamente, e pareceria que a busca "esqueceu"
      // gente que devia continuar aparecendo. Ainda ASSIM tem teto (500,
      // não ilimitado) -- e continua barato, porque `ST_DWithin` já reduz
      // o universo de linhas ANTES do LIMIT entrar em jogo.
      const limite = entre(numeroOpcional(req.query.limite, 'limite', 20), 1, 500, 'limite');

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
   GET /profissionais/me -- PRIVADA (exige login, só "profissional").

   Devolve os dados do PRÓPRIO profissional logado: nome, e-mail, contato,
   endereço, descrição, CEP, foto de perfil, especialidades. Diferente de
   `GET /profissionais/:id` (pública): esta inclui `email`/`contato`, porque
   só o dono do token consegue chamá-la. É o que alimenta a tela de editar
   perfil -- antes dela, a tela usava a rota pública (com o próprio ID), que
   nunca devolvia `contato`, então não existia como editar esse campo (ver
   comentário em `buscarMeuPerfil`, profissionais.repository.ts).

   Precisa ficar registrada ANTES de `/:id` abaixo, mesma pegadinha de
   sempre: se viesse depois, "/me" seria capturado pelo `:id`.
   ========================================================================= */
profissionaisRouter.get(
  '/me',
  exigirAutenticacao,
  exigirPapel('profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const perfil = await buscarMeuPerfil(req.usuario!.sub);
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
   PATCH /profissionais/me -- PRIVADA (exige login, só "profissional").

   Edita o PRÓPRIO perfil: descrição ("sobre mim"), CEP (que define onde o
   profissional aparece no mapa), contato, endereço (texto livre) e/ou foto
   de perfil. Repare que não existe `:id` na URL -- de propósito. O
   profissional editado é sempre `req.usuario.sub` (quem está logado), nunca
   um ID escolhido no corpo da request. Isso elimina de saída qualquer risco
   de um profissional editar o perfil de outro só trocando um ID no JSON.

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
     contato        (texto, 11 dígitos -- telefone/WhatsApp; migração 16)
     endereco       (texto, até 500 caracteres -- número/complemento/
                    referência, livre; migração 16, NÃO confundir com
                    "cep"/endereco_atuacao acima)
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
      const urlFotoPerfil = req.file
        ? urlPublicaDoArquivoPerfil(req.file as Express.MulterS3.File)
        : undefined;

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

      // `contato`/`endereco` -- migração 16. Mesma convenção de `cep` acima:
      // "não veio" (undefined) é diferente de "veio vazio" -- só o segundo
      // caso dispara a validação de formato.
      const contato =
        req.body.contato !== undefined && req.body.contato !== null && req.body.contato !== ''
          ? apenasDigitos(req.body.contato, 'contato', 11)
          : undefined;
      const endereco = textoOpcional(req.body.endereco, 'endereco', 500);

      if (
        descricao === undefined &&
        cepBruto === undefined &&
        urlFotoPerfil === undefined &&
        categoriaId === undefined &&
        contato === undefined &&
        endereco === undefined
      ) {
        throw new ErroDeValidacao(
          'Envie ao menos "descricao", "cep", "categoria_id"/"subcategoria_id", "contato", "endereco" ou uma foto ("foto_perfil") para atualizar.',
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
        contato,
        endereco,
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
   GET /profissionais/me/subcategorias -- PRIVADA (exige login, só "profissional").

   Lista TODAS as tags de especialidade do profissional logado -- migração
   11. É o que a tela de editar perfil usa para desenhar os "boxes"
   removíveis antes mesmo de qualquer alteração.
   ========================================================================= */
profissionaisRouter.get(
  '/me/subcategorias',
  exigirAutenticacao,
  exigirPapel('profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const tags = await listarTagsDoProfissional(req.usuario!.sub);
      return res.json({ dados: tags });
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /profissionais/me/subcategorias -- PRIVADA (exige login, só "profissional").

   Body: { subcategoria_id: number }

   Adiciona UMA tag de especialidade nova -- idempotente (adicionar de novo
   uma que já existe não dá erro, só devolve a lista sem mudança). É o que
   roda a cada "Enter"/confirmação no fluxo de 'Adicionar Categoria' da tela
   de editar perfil: o profissional digita, confirma, o box aparece -- e o
   campo continua ali, pronto pra próxima.
   ========================================================================= */
profissionaisRouter.post(
  '/me/subcategorias',
  exigirAutenticacao,
  exigirPapel('profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const subcategoriaId = inteiroPositivoObrigatorio(req.body.subcategoria_id, 'subcategoria_id');
      const tags = await adicionarTagAoProfissional(req.usuario!.sub, subcategoriaId);
      return res.status(201).json({ dados: tags });
    } catch (erro) {
      // `subcategoria_id` não existe -- a FK de `profissional_subcategorias`
      // recusa o INSERT. Mesma tradução já usada em PATCH /profissionais/me.
      if (ehErroDePostgres(erro) && erro.code === PG_FOREIGN_KEY_VIOLATION) {
        return next(new ErroDeValidacao('Especialidade inválida. Selecione novamente na lista.'));
      }
      return next(erro);
    }
  },
);

/* ============================================================================
   DELETE /profissionais/me/subcategorias/:subcategoriaId -- PRIVADA (exige
   login, só "profissional").

   Remove UMA tag de especialidade -- recusa (400) se for a última que
   sobrou (ver `removerTagDoProfissional`): um profissional precisa manter
   ao menos uma, senão desapareceria de toda busca por subcategoria exata.
   ========================================================================= */
profissionaisRouter.delete(
  '/me/subcategorias/:subcategoriaId',
  exigirAutenticacao,
  exigirPapel('profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const subcategoriaId = numeroObrigatorio(req.params.subcategoriaId, 'subcategoria_id');
      if (!Number.isInteger(subcategoriaId) || subcategoriaId <= 0) {
        throw new ErroDeValidacao('"subcategoria_id" deve ser um número inteiro positivo.');
      }
      const tags = await removerTagDoProfissional(req.usuario!.sub, subcategoriaId);
      return res.json({ dados: tags });
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /profissionais/me/avaliacoes/resumo -- PRIVADA (exige login, só "profissional").

   Painel de desempenho ("dashboard") da tela de editar perfil: a MESMA
   agregação de `GET /profissionais/:id/avaliacoes/resumo` (pública), só que
   o `:id` nunca vem da URL nem do corpo da requisição -- é sempre
   `req.usuario.sub`, o dono do token. Rota separada, e não
   "reaproveitar a pública passando o próprio id", por dois motivos: (1) o
   profissional não precisa saber o próprio UUID para ver o painel dele, e
   (2) fica registrado no código, de forma explícita, que "minhas métricas"
   é sempre sobre QUEM ESTÁ LOGADO -- nunca um id manipulável.

   Precisa ficar registrada ANTES de `/:id/avaliacoes/resumo` abaixo --
   mesma pegadinha de ordem de rotas do Express já documentada em
   `/me/subcategorias`: se viesse depois, "/me" seria capturado pelo `:id`.

   `buscarResumoDeAvaliacoes` já devolve tudo `null` (nunca lança erro)
   quando o profissional ainda não tem avaliação nenhuma -- COUNT(*) sempre
   devolve uma linha, com os AVG em branco. O app mostra isso como "ainda
   sem avaliações", não como falha.
   ========================================================================= */
profissionaisRouter.get(
  '/me/avaliacoes/resumo',
  exigirAutenticacao,
  exigirPapel('profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const resumo = await buscarResumoDeAvaliacoes(req.usuario!.sub);
      return res.json(resumo);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   PORTFÓLIO VISUAL (migração 16) -- galeria de fotos que o PRÓPRIO
   profissional escolhe subir para mostrar seu trabalho. Diferente de
   `GET /:id/portfolio` (mais abaixo), que é o histórico de AVALIAÇÕES com
   foto anexada pelo CLIENTE -- este aqui é curado pelo profissional, sem
   vínculo com nenhum serviço específico.

   POST/DELETE precisam ficar registradas ANTES de `/:id` abaixo, mesma
   pegadinha de sempre com rotas "/me/*".
   ========================================================================= */

/**
 * POST /profissionais/me/portfolio-fotos -- PRIVADA (exige login, só "profissional").
 *
 * Content-Type: multipart/form-data
 * Campo: fotos_portfolio (1 a 6 arquivos por chamada -- JPEG/PNG/WEBP, até 5MB cada)
 *
 * Recusa (400) se o LOTE mais o que já existe passar de
 * `MAX_FOTOS_TOTAL_PORTFOLIO` -- checado ANTES de subir qualquer arquivo
 * pro bucket (`contarFotosPortfolio` primeiro, upload depois), pra não
 * gastar armazenamento com um lote que vai ser recusado de qualquer jeito.
 *
 * Devolve a galeria COMPLETA atualizada (mesmo padrão de
 * `adicionarTagAoProfissional`).
 */
profissionaisRouter.post(
  '/me/portfolio-fotos',
  exigirAutenticacao,
  exigirPapel('profissional'),
  // Pré-checagem RÁPIDA (antes do multer subir qualquer coisa pro bucket):
  // se o profissional já está NO teto, recusa de cara -- evita gastar
  // armazenamento com um lote que vai ser recusado de qualquer jeito. Não é
  // a checagem FINAL (essa vem depois do upload, porque só ali sabemos
  // quantos arquivos de fato vieram nesta chamada -- ver o handler abaixo).
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const totalAtual = await contarFotosPortfolio(req.usuario!.sub);
      if (totalAtual >= MAX_FOTOS_TOTAL_PORTFOLIO) {
        throw new ErroDeValidacao(
          `Seu portfólio já tem o máximo de ${MAX_FOTOS_TOTAL_PORTFOLIO} fotos. Remova alguma antes de adicionar novas.`,
        );
      }
      return next();
    } catch (erro) {
      return next(erro);
    }
  },
  uploadFotosPortfolio,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const arquivos = (req.files as Express.MulterS3.File[] | undefined) ?? [];
      if (arquivos.length === 0) {
        throw new ErroDeValidacao('Envie ao menos uma foto no campo "fotos_portfolio".');
      }

      // Checagem FINAL, exata: a pré-checagem acima só barrou quem já
      // estava NO teto; esta cobre quem tinha espaço para MENOS fotos do
      // que enviou (ex.: 2 vagas livres, mandou 4 no lote).
      const totalAtual = await contarFotosPortfolio(req.usuario!.sub);
      if (totalAtual + arquivos.length > MAX_FOTOS_TOTAL_PORTFOLIO) {
        throw new ErroDeValidacao(
          `Seu portfólio ficaria com ${totalAtual + arquivos.length} fotos -- o máximo é ${MAX_FOTOS_TOTAL_PORTFOLIO}. Envie menos fotos de uma vez ou remova alguma antes.`,
        );
      }

      const urls = urlsPublicasDosArquivos(arquivos);
      const galeria = await adicionarFotosPortfolio(
        req.usuario!.sub,
        urls.map((url) => ({ urlFoto: url })),
      );

      return res.status(201).json({ dados: galeria });
    } catch (erro) {
      return next(erro);
    }
  },
);

/**
 * DELETE /profissionais/me/portfolio-fotos/:idFoto -- PRIVADA (exige login, só "profissional").
 *
 * A checagem de ownership acontece DENTRO do SQL de `removerFotoPortfolio`
 * (WHERE profissional_id = dono) -- devolve 404 tanto para uma foto que não
 * existe quanto para uma que existe mas é de OUTRO profissional (a mesma
 * resposta nos dois casos evita confirmar pra quem tentou que aquele UUID
 * pertence a alguém).
 */
profissionaisRouter.delete(
  '/me/portfolio-fotos/:idFoto',
  exigirAutenticacao,
  exigirPapel('profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const idFoto = uuidObrigatorio(req.params.idFoto, 'idFoto');
      const removeu = await removerFotoPortfolio(req.usuario!.sub, idFoto);
      if (!removeu) {
        throw new ErroNaoEncontrado('Foto não encontrada.');
      }
      const galeria = await listarPortfolioFotos(req.usuario!.sub);
      return res.json({ dados: galeria });
    } catch (erro) {
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

   Query params:
     pagina          (opcional) padrão 1
     limite          (opcional) padrão 20, máximo 100
     subcategoria_id (opcional) filtra o histórico para só uma especialidade
                                 (migração 12) -- é o toggle "por categoria"
                                 do perfil público. Ausente = portfólio
                                 inteiro, todas as especialidades juntas.
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
      const subcategoriaId = inteiroPositivoOpcional(req.query.subcategoria_id, 'subcategoria_id');

      const portfolio = await buscarPortifolio(
        profissionalId,
        { limite, offset },
        req.usuario?.sub,
        subcategoriaId,
      );

      return res.json({ pagina, limite, total_retornado: portfolio.length, dados: portfolio });
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /profissionais/:id/portfolio-fotos -- PÚBLICA (sem login).

   A galeria de fotos CURADA PELO PRÓPRIO PROFISSIONAL (migração 16) --
   diferente de `GET /:id/portfolio` acima (histórico de avaliações com
   foto anexada pelo cliente). Pública pelo mesmo motivo: é vitrine, precisa
   convencer um cliente novo ANTES dele criar conta. Mesma função de
   repository usada pela tela de edição do dono (`GET /profissionais/me`
   não tem endpoint próprio de portfólio -- o dono chama esta MESMA rota
   pública com o próprio ID, já que os dados não são sensíveis).
   ========================================================================= */
profissionaisRouter.get(
  '/:id/portfolio-fotos',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const profissionalId = uuidObrigatorio(req.params.id, 'id');
      const fotos = await listarPortfolioFotos(profissionalId);
      return res.json({ dados: fotos });
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
