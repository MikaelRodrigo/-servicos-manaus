import { Router, Request, Response, NextFunction } from 'express';
import {
  uuidObrigatorio,
  textoOpcional,
  statusServicoOpcional,
  numeroOpcional,
  inteiroPositivoObrigatorio,
  entre,
  ErroDeConflito,
  ErroDeValidacao,
  ErroNaoEncontrado,
  StatusServico,
} from '../utils/validacao';
import { ehErroDePostgres, PG_FOREIGN_KEY_VIOLATION } from '../utils/erros-postgres';
import { exigirAutenticacao, exigirPapel, ErroDeAutenticacao } from '../middlewares/autenticacao';
import {
  Servico,
  buscarServicoPorId,
  listarServicosDoCliente,
  listarServicosDoProfissional,
  criarServico,
  aceitarServico,
  recusarServico,
  iniciarServico,
  concluirServico,
  cancelarServicoComoCliente,
  cancelarServicoComoProfissional,
} from '../repositories/servicos.repository';
import { profissionalPossuiTag } from '../repositories/profissionais.repository';
import { cancelarTransacoesAbertasDoServico } from '../repositories/transacoes.repository';
import { avaliacoesRouter } from './avaliacoes.routes';

export const servicosRouter = Router();

/* ============================================================================
   TODA ROTA AQUI EMBAIXO EXIGE LOGIN.

   Diferente de /profissionais/proximos (pública -- é a busca no mapa),
   /servicos é sempre "meu serviço", "meu histórico". Por isso
   `exigirAutenticacao` está no `router.use()`, uma vez só, em vez de
   repetido rota por rota.
   ========================================================================= */
servicosRouter.use(exigirAutenticacao);

/* ============================================================================
   Tudo em /servicos/:id/avaliacoes/* vive em avaliacoes.routes.ts. Montar
   como sub-router aqui (em vez de colar as rotas neste arquivo) mantém
   "servicos.routes.ts" falando só sobre a MÁQUINA DE ESTADOS do serviço, e
   "avaliacoes.routes.ts" falando só sobre AVALIAR. O `mergeParams: true`
   daquele router é o que permite ele enxergar o `:id` capturado aqui.
   ========================================================================= */
servicosRouter.use('/:id/avaliacoes', avaliacoesRouter);

/* ============================================================================
   POST /servicos -- o CLIENTE solicita um serviço a um profissional.

   Body: {
     profissional_id: string (uuid),
     categoria_id: number,
     subcategoria_id: number,
     descricao?: string,
   }

   `categoria_id`/`subcategoria_id` são OBRIGATÓRIOS (migração 12): o
   cliente escolhe, dentre as especialidades (tags) do profissional, qual
   delas está contratando. Essa categoria fica gravada no serviço -- não
   duplicada na avaliação depois, ela "flui" via `id_servico` (ver
   vw_historico_portifolio). Isso é o que permite segmentar o histórico de
   avaliações por especialidade: a nota de "Eletricista" não se mistura com
   a de "Pintor" do mesmo profissional.

   Além de existir no catálogo geral (checado pela FK composta em
   `servicos`), a subcategoria precisa ser uma das tags do PRÓPRIO
   profissional -- senão o cliente poderia "contratar" uma especialidade que
   ele nem oferece.

   Só cliente pode criar (exigirPapel('cliente')). Um profissional não
   "solicita serviço para si mesmo" neste fluxo -- se um dia vocês quiserem
   esse caso de uso, é uma rota nova, não uma exceção aqui.
   ========================================================================= */
servicosRouter.post(
  '/',
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Record<string, unknown>;
      const profissionalId = uuidObrigatorio(body.profissional_id, 'profissional_id');
      const categoriaId = inteiroPositivoObrigatorio(body.categoria_id, 'categoria_id');
      const subcategoriaId = inteiroPositivoObrigatorio(body.subcategoria_id, 'subcategoria_id');
      const descricao = textoOpcional(body.descricao, 'descricao', 1000);
      const clienteId = req.usuario!.sub;

      const possuiTag = await profissionalPossuiTag(profissionalId, subcategoriaId);
      if (!possuiTag) {
        throw new ErroDeValidacao(
          'Esta especialidade não está entre as oferecidas por este profissional.',
        );
      }

      let servico: Servico;
      try {
        servico = await criarServico({
          clienteId,
          profissionalId,
          descricao,
          categoriaId,
          subcategoriaId,
        });
      } catch (erro) {
        // profissional_id bem formado (passou no uuidObrigatorio) mas que
        // não existe na tabela `profissionais` -- o Postgres recusa a FK.
        // (O par categoria/subcategoria já foi validado acima via
        // profissionalPossuiTag, então uma FK violation aqui só pode ser o
        // profissional_id.)
        if (ehErroDePostgres(erro) && erro.code === PG_FOREIGN_KEY_VIOLATION) {
          throw new ErroNaoEncontrado('Profissional não encontrado.');
        }
        throw erro;
      }

      return res.status(201).json(servico);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /servicos/meus -- lista os serviços da pessoa logada.

   Query params:
     status  (opcional) filtra por um status: ?status=ACEITO
     pagina  (opcional) padrão 1
     limite  (opcional) padrão 20, máximo 100

   O que a rota devolve depende do PAPEL de quem está logado: um cliente vê
   os serviços em que ele é cliente_id; um profissional vê os em que ele é
   profissional_id. Ninguém vê os dois lados -- não existe "admin" ainda.
   ========================================================================= */
servicosRouter.get('/meus', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { sub: usuarioId, papel } = req.usuario!;

    const status = statusServicoOpcional(req.query.status);
    const pagina = entre(numeroOpcional(req.query.pagina, 'pagina', 1), 1, 1000, 'pagina');
    const limite = entre(numeroOpcional(req.query.limite, 'limite', 20), 1, 100, 'limite');
    const offset = (pagina - 1) * limite;

    const servicos =
      papel === 'cliente'
        ? await listarServicosDoCliente(usuarioId, { status, limite, offset })
        : await listarServicosDoProfissional(usuarioId, { status, limite, offset });

    return res.json({ pagina, limite, total_retornado: servicos.length, dados: servicos });
  } catch (erro) {
    return next(erro);
  }
});

/* ============================================================================
   GET /servicos/:id -- detalhe de UM serviço.

   Protegido por OWNERSHIP, não só por login: você só pode ver um serviço se
   for o cliente OU o profissional daquele serviço específico. Sem essa
   checagem, qualquer usuário autenticado poderia ler o histórico de
   qualquer outra pessoa só adivinhando UUIDs -- e UUID não é secreto.
   ========================================================================= */
servicosRouter.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = uuidObrigatorio(req.params.id, 'id');
    const servico = await buscarServicoPorId(id);
    if (!servico) {
      throw new ErroNaoEncontrado('Serviço não encontrado.');
    }

    verificarPertencimento(servico, req);

    return res.json(servico);
  } catch (erro) {
    return next(erro);
  }
});

/** Lança 403 se a pessoa logada não for nem o cliente nem o profissional deste serviço. */
function verificarPertencimento(servico: Servico, req: Request): void {
  const { sub, papel } = req.usuario!;
  const ehODono =
    (papel === 'cliente' && servico.cliente_id === sub) ||
    (papel === 'profissional' && servico.profissional_id === sub);

  if (!ehODono) {
    throw new ErroDeAutenticacao('Você não tem acesso a este serviço.', 403);
  }
}

/**
 * Fábrica de handler para as transições que só o PROFISSIONAL pode fazer
 * (aceitar, recusar, iniciar, concluir). As quatro rotas fazem exatamente a
 * mesma coisa em três passos -- só muda QUAL transição e a mensagem de erro:
 *
 *   1) busca o serviço e confere que ele é o dono (403 se não for)
 *   2) confere se o status atual permite essa transição (409 se não permitir)
 *   3) executa o UPDATE condicional (409 se, por uma corrida rara, alguém
 *      mudou o status entre o passo 1 e o passo 3)
 */
function criarRotaDeTransicaoDoProfissional(opcoes: {
  statusEsperado: StatusServico;
  nomeAcao: string;
  executar: (idServico: string, profissionalId: string) => Promise<boolean>;
}) {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id = uuidObrigatorio(req.params.id, 'id');
      const profissionalId = req.usuario!.sub;

      const servico = await buscarServicoPorId(id);
      if (!servico) {
        throw new ErroNaoEncontrado('Serviço não encontrado.');
      }
      if (servico.profissional_id !== profissionalId) {
        throw new ErroDeAutenticacao('Este serviço não pertence a você.', 403);
      }
      if (servico.status !== opcoes.statusEsperado) {
        throw new ErroDeConflito(
          `Só é possível ${opcoes.nomeAcao} um serviço com status "${opcoes.statusEsperado}". ` +
            `Status atual: "${servico.status}".`,
        );
      }

      const conseguiu = await opcoes.executar(id, profissionalId);
      if (!conseguiu) {
        // Passou nas checagens acima, mas o UPDATE não achou a linha no
        // estado esperado -- alguém alterou o serviço entre o SELECT e o
        // UPDATE. Raro, mas o código tem que admitir que existe.
        throw new ErroDeConflito('O status do serviço mudou. Recarregue e tente novamente.');
      }

      return res.json(await buscarServicoPorId(id));
    } catch (erro) {
      return next(erro);
    }
  };
}

servicosRouter.patch(
  '/:id/aceitar',
  exigirPapel('profissional'),
  criarRotaDeTransicaoDoProfissional({
    statusEsperado: 'SOLICITADO',
    nomeAcao: 'aceitar',
    executar: aceitarServico,
  }),
);

servicosRouter.patch(
  '/:id/recusar',
  exigirPapel('profissional'),
  criarRotaDeTransicaoDoProfissional({
    statusEsperado: 'SOLICITADO',
    nomeAcao: 'recusar',
    executar: recusarServico,
  }),
);

servicosRouter.patch(
  '/:id/iniciar',
  exigirPapel('profissional'),
  criarRotaDeTransicaoDoProfissional({
    statusEsperado: 'ACEITO',
    nomeAcao: 'iniciar',
    executar: iniciarServico,
  }),
);

servicosRouter.patch(
  '/:id/concluir',
  exigirPapel('profissional'),
  criarRotaDeTransicaoDoProfissional({
    statusEsperado: 'EM_ANDAMENTO',
    nomeAcao: 'concluir',
    executar: concluirServico,
  }),
);

/* ============================================================================
   PATCH /servicos/:id/cancelar -- o ÚNICO estado que os DOIS lados podem
   mudar. Um cliente desiste, ou um profissional desiste -- ambos cancelam.

   Por isso não usa `criarRotaDeTransicaoDoProfissional`: a coluna de
   "dono" (cliente_id vs profissional_id) muda dependendo de quem chamou.
   ========================================================================= */
servicosRouter.patch('/:id/cancelar', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = uuidObrigatorio(req.params.id, 'id');
    const { sub: usuarioId, papel } = req.usuario!;

    const servico = await buscarServicoPorId(id);
    if (!servico) {
      throw new ErroNaoEncontrado('Serviço não encontrado.');
    }
    verificarPertencimento(servico, req);

    const STATUS_CANCELAVEIS: StatusServico[] = ['SOLICITADO', 'ACEITO', 'EM_ANDAMENTO'];
    if (!STATUS_CANCELAVEIS.includes(servico.status)) {
      throw new ErroDeConflito(
        `Não é possível cancelar um serviço com status "${servico.status}".`,
      );
    }

    const conseguiu =
      papel === 'cliente'
        ? await cancelarServicoComoCliente(id, usuarioId)
        : await cancelarServicoComoProfissional(id, usuarioId);

    if (!conseguiu) {
      throw new ErroDeConflito('O status do serviço mudou. Recarregue e tente novamente.');
    }

    // Cancela junto qualquer proposta/cobrança ainda EM ABERTO (migração
    // 15) -- limitado, de propósito, a transações que ainda não chegaram a
    // "RETIDA" (dinheiro já na conta do profissional exige estorno manual,
    // não é uma operação de banco de dados). Ver o comentário completo em
    // `cancelarTransacoesAbertasDoServico`.
    await cancelarTransacoesAbertasDoServico(id);

    return res.json(await buscarServicoPorId(id));
  } catch (erro) {
    return next(erro);
  }
});
