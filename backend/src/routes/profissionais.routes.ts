import { Router, Request, Response, NextFunction } from 'express';
import { env } from '../env';
import { buscarProximos, buscarPerfilPublico, atualizarPerfilProfissional } from '../repositories/profissionais.repository';
import {
  numeroObrigatorio,
  numeroOpcional,
  textoOpcional,
  entre,
  uuidObrigatorio,
  ErroNaoEncontrado,
  ErroDeValidacao,
} from '../utils/validacao';
import { buscarPortifolio, buscarResumoDeAvaliacoes } from '../repositories/avaliacoes.repository';
import { exigirAutenticacao, exigirPapel, autenticacaoOpcional } from '../middlewares/autenticacao';
import { uploadFotoPerfil, urlPublicaDoArquivoPerfil } from '../middlewares/upload';

export const profissionaisRouter = Router();

/**
 * GET /profissionais/proximos
 *
 * Query params:
 *   latitude   (obrigatório)  -3.13013
 *   longitude  (obrigatório)  -60.02340
 *   raio_km    (opcional)     padrão 5, máximo RAIO_MAXIMO_KM
 *   profissao  (opcional)     "eletricista"
 *   pagina     (opcional)     padrão 1
 *   limite     (opcional)     padrão 20, máximo 100
 *
 * Exemplo:
 *   /profissionais/proximos?latitude=-3.13013&longitude=-60.02340&raio_km=5
 */
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
        limite,
        offset,
      });

      /* ---------------------------------------------------------------
         PASSO 4 - RESPONDER.

         Devolvo um objeto com metadados, não um array cru. Quando o
         Flutter precisar de paginação (Etapa 7), o contrato já existe e
         você não quebra o app dos usuários.
         --------------------------------------------------------------- */
      return res.json({
        parametros: { latitude, longitude, raio_km: raioKm, profissao: profissao ?? null },
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

   Edita o PRÓPRIO perfil público: descrição ("sobre mim") e/ou foto de
   perfil. Repare que não existe `:id` na URL -- de propósito. O profissional
   editado é sempre `req.usuario.sub` (quem está logado), nunca um ID
   escolhido no corpo da request. Isso elimina de saída qualquer risco de um
   profissional editar o perfil de outro só trocando um ID no JSON.

   Content-Type: multipart/form-data
   Campos (ambos opcionais, mas ao menos um precisa vir):
     descricao   (texto, até 2000 caracteres)
     foto_perfil (arquivo -- JPEG, PNG ou WEBP, até 5 MB)

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

      if (descricao === undefined && urlFotoPerfil === undefined) {
        throw new ErroDeValidacao(
          'Envie ao menos "descricao" ou uma foto ("foto_perfil") para atualizar.',
        );
      }

      const perfilAtualizado = await atualizarPerfilProfissional(req.usuario!.sub, {
        descricao,
        urlFotoPerfil,
      });

      return res.json(perfilAtualizado);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /profissionais/:id -- PÚBLICA (sem login).

   Perfil público completo: foto, descrição, atuação, contato. É a tela que
   abre quando o cliente toca no pino do profissional no mapa.

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
