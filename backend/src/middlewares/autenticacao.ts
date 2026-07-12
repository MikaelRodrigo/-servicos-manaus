import { Request, Response, NextFunction } from 'express';
import { verificarToken, Papel } from '../utils/jwt';

/**
 * Erro de autenticação/autorização. Vira 401 (não autenticado) ou 403 (sem
 * permissão) no middleware de erro do app.ts -- ver o ajuste feito lá.
 */
export class ErroDeAutenticacao extends Error {
  constructor(
    mensagem: string,
    public readonly status: 401 | 403 = 401,
  ) {
    super(mensagem);
    this.name = 'ErroDeAutenticacao';
  }
}

/* ============================================================================
   COMO O TOKEN CHEGA NA REQUEST

   O cliente (Flutter, ou o curl no seu teste) manda um cabeçalho HTTP:

       Authorization: Bearer eyJhbGciOiJIUzI1NiIs...

   "Bearer" é só uma palavra-convenção (RFC 6750) que diz "o que vem depois
   é um token". Por isso o split(' ') abaixo: pegamos a segunda metade.
   ========================================================================= */
function extrairTokenDoHeader(req: Request): string | null {
  const cabecalho = req.headers.authorization;
  if (!cabecalho) return null;

  const [esquema, token] = cabecalho.split(' ');
  if (esquema !== 'Bearer' || !token) return null;

  return token;
}

/**
 * Middleware que EXIGE um token válido. Se não houver, ou se ele for
 * inválido/expirado, a request nunca chega na rota -- cai direto no 401.
 *
 * Uso: router.get('/rota-protegida', exigirAutenticacao, (req, res) => {...})
 */
export function exigirAutenticacao(req: Request, _res: Response, next: NextFunction): void {
  try {
    const token = extrairTokenDoHeader(req);
    if (!token) {
      throw new ErroDeAutenticacao(
        'Token ausente. Envie "Authorization: Bearer <token>".',
        401,
      );
    }

    // Lança automaticamente se a assinatura não bater ou se tiver expirado.
    req.usuario = verificarToken(token);
    next();
  } catch (erro) {
    if (erro instanceof ErroDeAutenticacao) {
      return next(erro);
    }
    // jsonwebtoken lança TokenExpiredError / JsonWebTokenError, entre outros.
    // Todos viram a mesma mensagem genérica -- não vale a pena o cliente
    // saber SE foi expiração ou adulteração, o resultado prático é o mesmo.
    return next(new ErroDeAutenticacao('Token inválido ou expirado.', 401));
  }
}

/**
 * Versão "sem exigência" de `exigirAutenticacao`, para rotas PÚBLICAS que
 * ainda assim se comportam diferente para quem está logado.
 *
 * Caso de uso real: GET /profissionais/:id/portfolio é pública -- qualquer
 * visitante vê, mesmo sem conta (é o que convence alguém a se cadastrar).
 * Mas se a pessoa JÁ está logada, a rota quer saber quem ela é, pra marcar
 * quais avaliações ela já curtiu (`curtido_por_mim`). Este middleware tenta
 * ler o token; se vier um token válido, preenche `req.usuario` normalmente;
 * se não vier token NENHUM, ou vier um token quebrado/expirado, a request
 * segue em frente do mesmo jeito -- só que com `req.usuario` indefinido.
 *
 * A diferença para `exigirAutenticacao` é só essa: aqui, "sem token" ou
 * "token inválido" NUNCA vira erro. A rota que usar isto precisa tratar
 * `req.usuario` como opcional (`req.usuario?.sub`, não `req.usuario!.sub`).
 */
export function autenticacaoOpcional(req: Request, _res: Response, next: NextFunction): void {
  const token = extrairTokenDoHeader(req);
  if (!token) {
    return next();
  }

  try {
    req.usuario = verificarToken(token);
  } catch {
    // Token presente mas inválido/expirado -- ignora e segue como visitante
    // anônimo, em vez de derrubar a request. É a diferença central para
    // `exigirAutenticacao`, que lançaria 401 aqui.
  }
  next();
}

/**
 * Middleware de AUTORIZAÇÃO (diferente de autenticação!). Restringe uma rota
 * a um papel específico. Precisa rodar DEPOIS de `exigirAutenticacao`.
 *
 * Exemplo: só profissional pode responder a um serviço.
 *   router.post('/servicos/:id/aceitar', exigirAutenticacao, exigirPapel('profissional'), ...)
 */
export function exigirPapel(...papeisPermitidos: Papel[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.usuario) {
      // Só acontece se alguém esquecer de colocar exigirAutenticacao antes.
      return next(new ErroDeAutenticacao('Rota mal configurada: falta exigirAutenticacao.', 401));
    }

    if (!papeisPermitidos.includes(req.usuario.papel)) {
      return next(
        new ErroDeAutenticacao(
          `Acesso restrito a: ${papeisPermitidos.join(', ')}.`,
          403,
        ),
      );
    }

    next();
  };
}
