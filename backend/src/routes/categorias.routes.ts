import { Router, Request, Response, NextFunction } from 'express';
import { listarCategoriasComSubcategorias } from '../repositories/categorias.repository';

export const categoriasRouter = Router();

/* ============================================================================
   GET /categorias -- PÚBLICA (sem login).

   Devolve a árvore completa categoria -> subcategorias, usada em DOIS
   lugares do app:
     1. O seletor em cascata na tela de cadastro do profissional (obrigatório
        escolher categoria + subcategoria, texto livre não é mais aceito).
     2. Qualquer filtro futuro por categoria (ex.: no mapa).

   Sem paginação de propósito: são ~7 categorias e ~60 subcategorias no
   total (ver seed da migração 09) -- populações desse tamanho, o app
   carrega tudo de uma vez e filtra localmente, é mais rápido que ficar
   paginando uma lista que cabe inteira na tela.
   ========================================================================= */
categoriasRouter.get('/', async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const categorias = await listarCategoriasComSubcategorias();
    return res.json({ dados: categorias });
  } catch (erro) {
    return next(erro);
  }
});
