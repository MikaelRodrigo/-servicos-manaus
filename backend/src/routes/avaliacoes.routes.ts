import { Router, Request, Response, NextFunction } from 'express';
import {
  uuidObrigatorio,
  notaObrigatoria,
  textoOpcional,
  ErroDeConflito,
  ErroNaoEncontrado,
} from '../utils/validacao';
import { ehErroDePostgres, PG_UNIQUE_VIOLATION, PG_CHECK_VIOLATION } from '../utils/erros-postgres';
import { ErroDeAutenticacao } from '../middlewares/autenticacao';
import { uploadFotoServico, urlsPublicasDosArquivos } from '../middlewares/upload';
import { buscarServicoPorId } from '../repositories/servicos.repository';
import {
  criarAvaliacaoProfissional,
  criarAvaliacaoCliente,
  buscarAvaliacaoProfissionalPorServico,
  buscarAvaliacaoClientePorServico,
} from '../repositories/avaliacoes.repository';

/* ============================================================================
   `mergeParams: true` é o que permite este router LER `req.params.id`
   mesmo ele tendo sido capturado pelo router PAI (servicos.routes.ts, que
   monta este arquivo em `servicosRouter.use('/:id/avaliacoes', avaliacoesRouter)`).
   Sem essa opção, `req.params` chegaria aqui vazio -- é um erro clássico de
   quem começa a usar sub-routers no Express.

   `exigirAutenticacao` já rodou no router pai (servicosRouter.use(...) no
   topo de servicos.routes.ts) antes de chegar aqui -- não precisa repetir.
   ========================================================================= */
export const avaliacoesRouter = Router({ mergeParams: true });

/** Busca o serviço do :id da URL e garante que ele existe. Repetido nas 3 rotas abaixo. */
async function buscarServicoOuFalhar(req: Request) {
  const idServico = uuidObrigatorio(req.params.id, 'id');
  const servico = await buscarServicoPorId(idServico);
  if (!servico) {
    throw new ErroNaoEncontrado('Serviço não encontrado.');
  }
  return { idServico, servico };
}

/* ============================================================================
   POST /servicos/:id/avaliacoes/profissional
   (o CLIENTE avalia o PROFISSIONAL -- com fotos opcionais, até 5)

   Content-Type: multipart/form-data
   Campos: estrelas_tecnico, estrelas_comportamental, estrelas_economico,
           comentario (opcional), fotos_servico (0 a 5 arquivos, campo
           repetido -- ver MAX_FOTOS_POR_AVALIACAO em upload.ts)

   `exigirPapel('cliente')` não foi colocado aqui de propósito -- ele
   sozinho não bastaria (um cliente qualquer, não o DESTE serviço, também
   passaria). A checagem real é "você é o cliente_id deste serviço
   específico", feita abaixo manualmente.
   ========================================================================= */
avaliacoesRouter.post(
  '/profissional',
  uploadFotoServico,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { idServico, servico } = await buscarServicoOuFalhar(req);

      if (req.usuario!.papel !== 'cliente' || servico.cliente_id !== req.usuario!.sub) {
        throw new ErroDeAutenticacao('Só o cliente que solicitou este serviço pode avaliá-lo.', 403);
      }
      if (servico.status !== 'CONCLUIDO') {
        throw new ErroDeConflito(
          `Só é possível avaliar um serviço "CONCLUIDO". Status atual: "${servico.status}".`,
        );
      }

      // multipart/form-data manda TUDO como string -- inclusive números.
      // `notaObrigatoria` (via `numeroDoBody`) já sabe converter string OU
      // number, então funciona igual nas duas situações.
      const estrelasTecnico = notaObrigatoria(req.body.estrelas_tecnico, 'estrelas_tecnico');
      const estrelasComportamental = notaObrigatoria(
        req.body.estrelas_comportamental,
        'estrelas_comportamental',
      );
      const estrelasEconomico = notaObrigatoria(req.body.estrelas_economico, 'estrelas_economico');
      const comentario = textoOpcional(req.body.comentario, 'comentario', 2000);

      // `.array(...)` (ver upload.ts) preenche `req.files` como ARRAY, não
      // `req.file` como o antigo `.single(...)`. Sem nenhuma foto enviada,
      // `req.files` chega como array vazio -- por isso o `?? []` não é nem
      // necessário aqui, mas o cast garante o tipo certo pro TypeScript.
      const arquivos = (req.files as Express.MulterS3.File[] | undefined) ?? [];
      const urlsFotos = urlsPublicasDosArquivos(arquivos);

      let avaliacao;
      try {
        avaliacao = await criarAvaliacaoProfissional({
          idServico,
          clienteId: servico.cliente_id,
          profissionalId: servico.profissional_id,
          estrelasTecnico,
          estrelasComportamental,
          estrelasEconomico,
          comentario,
          urlsFotos,
        });
      } catch (erro) {
        if (ehErroDePostgres(erro) && erro.code === PG_UNIQUE_VIOLATION) {
          throw new ErroDeConflito('Este serviço já foi avaliado.');
        }
        // Rede de segurança: o trigger `fn_valida_servico_concluido` recusaria
        // de qualquer forma, mas já barramos isso acima com uma mensagem melhor.
        if (ehErroDePostgres(erro) && erro.code === PG_CHECK_VIOLATION) {
          throw new ErroDeConflito('O serviço precisa estar concluído para ser avaliado.');
        }
        throw erro;
      }

      return res.status(201).json(avaliacao);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /servicos/:id/avaliacoes/cliente
   (o PROFISSIONAL avalia o CLIENTE -- sem foto, essa tabela não tem essa coluna)

   Content-Type: application/json
   Campos: estrelas_clareza, estrelas_comportamental, estrelas_pagamento,
           comentario (opcional)
   ========================================================================= */
avaliacoesRouter.post('/cliente', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { idServico, servico } = await buscarServicoOuFalhar(req);

    if (req.usuario!.papel !== 'profissional' || servico.profissional_id !== req.usuario!.sub) {
      throw new ErroDeAutenticacao('Só o profissional deste serviço pode avaliar o cliente.', 403);
    }
    if (servico.status !== 'CONCLUIDO') {
      throw new ErroDeConflito(
        `Só é possível avaliar um serviço "CONCLUIDO". Status atual: "${servico.status}".`,
      );
    }

    const body = req.body as Record<string, unknown>;
    const estrelasClareza = notaObrigatoria(body.estrelas_clareza, 'estrelas_clareza');
    const estrelasComportamental = notaObrigatoria(
      body.estrelas_comportamental,
      'estrelas_comportamental',
    );
    const estrelasPagamento = notaObrigatoria(body.estrelas_pagamento, 'estrelas_pagamento');
    const comentario = textoOpcional(body.comentario, 'comentario', 2000);

    let avaliacao;
    try {
      avaliacao = await criarAvaliacaoCliente({
        idServico,
        clienteId: servico.cliente_id,
        profissionalId: servico.profissional_id,
        estrelasClareza,
        estrelasComportamental,
        estrelasPagamento,
        comentario,
      });
    } catch (erro) {
      if (ehErroDePostgres(erro) && erro.code === PG_UNIQUE_VIOLATION) {
        throw new ErroDeConflito('Você já avaliou o cliente deste serviço.');
      }
      if (ehErroDePostgres(erro) && erro.code === PG_CHECK_VIOLATION) {
        throw new ErroDeConflito('O serviço precisa estar concluído para ser avaliado.');
      }
      throw erro;
    }

    return res.status(201).json(avaliacao);
  } catch (erro) {
    return next(erro);
  }
});

/* ============================================================================
   GET /servicos/:id/avaliacoes -- mostra as duas avaliações deste serviço
   (a que o cliente fez do profissional, e a que o profissional fez do
   cliente), quando existirem. Só quem participou do serviço pode ver.
   ========================================================================= */
avaliacoesRouter.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { idServico, servico } = await buscarServicoOuFalhar(req);

    const { sub, papel } = req.usuario!;
    const ehParticipante =
      (papel === 'cliente' && servico.cliente_id === sub) ||
      (papel === 'profissional' && servico.profissional_id === sub);
    if (!ehParticipante) {
      throw new ErroDeAutenticacao('Você não tem acesso às avaliações deste serviço.', 403);
    }

    const [avaliacaoProfissional, avaliacaoCliente] = await Promise.all([
      buscarAvaliacaoProfissionalPorServico(idServico),
      buscarAvaliacaoClientePorServico(idServico),
    ]);

    return res.json({
      avaliacao_do_profissional: avaliacaoProfissional, // feita pelo cliente
      avaliacao_do_cliente: avaliacaoCliente, // feita pelo profissional
    });
  } catch (erro) {
    return next(erro);
  }
});
