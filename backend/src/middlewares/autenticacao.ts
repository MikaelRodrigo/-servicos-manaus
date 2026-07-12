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
