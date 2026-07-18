import { Router, Request, Response, NextFunction } from 'express';
import { uuidObrigatorio, ErroNaoEncontrado } from '../utils/validacao';
import { exigirAutenticacao, exigirPapel } from '../middlewares/autenticacao';
import {
  avaliacaoProfissionalExiste,
  alternarCurtidaAvaliacao,
} from '../repositories/avaliacoes.repository';

/* ============================================================================
   Router dedicado ao botão "Útil" do portfólio (curtir avaliação).

   Por que um router NOVO, separado de avaliacoesRouter (que já existe em
   avaliacoes.routes.ts)? Porque `avaliacoesRouter` é montado em
   `/servicos/:id/avaliacoes` -- ele só faz sentido no contexto de UM
   serviço específico (criar/ver a avaliação daquele serviço). Curtir, por
   outro lado, opera direto pelo ID da AVALIAÇÃO, e pode ser disparado por
   QUALQUER usuário logado navegando no portfólio de um profissional --
   nada a ver com "o serviço X". Por isso mora na sua própria rota,
   montada em `/avaliacoes` (ver app.ts).
   ========================================================================= */
export const curtidasRouter = Router();

/* ============================================================================
   POST /avaliacoes/:avaliacaoId/curtir -- PRIVADA (exige login).

   Alterna a curtida (like/unlike) de UMA avaliação do portfólio. Qualquer
   usuário autenticado pode curtir -- cliente OU profissional, e não
   precisa ter participado daquele serviço (é o mesmo espírito de "achei
   útil" numa loja online: qualquer visitante logado pode votar).

   Devolve o novo estado, pronto para a tela atualizar sem precisar
   recarregar o portfólio inteiro:
     { curtido: boolean, total_curtidas: number }
   ========================================================================= */
curtidasRouter.post(
  '/:avaliacaoId/curtir',
  exigirAutenticacao,
  // "Curtir" só faz sentido para cliente/profissional (é quem navega o
  // portfólio) -- admin (migração 15) nunca deveria chamar esta rota; esta
  // checagem também é o que restringe o tipo de `papel` abaixo para
  // `alternarCurtidaAvaliacao`, que nunca soube (nem precisa saber) de "admin".
  exigirPapel('cliente', 'profissional'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const avaliacaoId = uuidObrigatorio(req.params.avaliacaoId, 'avaliacaoId');

      const existe = await avaliacaoProfissionalExiste(avaliacaoId);
      if (!existe) {
        throw new ErroNaoEncontrado('Avaliação não encontrada.');
      }

      const { sub, papel } = req.usuario!;
      if (papel !== 'cliente' && papel !== 'profissional') {
        throw new ErroNaoEncontrado('Avaliação não encontrada.'); // inalcançável -- exigirPapel já bloqueou acima
      }
      const resultado = await alternarCurtidaAvaliacao(avaliacaoId, sub, papel);

      return res.json({ curtido: resultado.curtido, total_curtidas: resultado.totalCurtidas });
    } catch (erro) {
      return next(erro);
    }
  },
);
