import { pool } from '../database';

/* ============================================================================
   Camada de acesso à lista de categorias/subcategorias (migração 09).

   É a única fonte da verdade para o seletor em cascata do app: o Flutter
   NUNCA guarda essa lista fixa embutida no código, sempre busca daqui --
   assim, adicionar/renomear uma categoria é só um INSERT/UPDATE no banco,
   sem precisar publicar uma nova versão do app.
   ========================================================================= */

export interface Subcategoria {
  id: number;
  nome: string;
}

export interface CategoriaComSubcategorias {
  id: number;
  nome: string;
  subcategorias: Subcategoria[];
}

/** Formato cru de uma linha do JOIN, antes de agrupar em árvore. */
interface LinhaCategoriaSubcategoria {
  categoria_id: number;
  categoria_nome: string;
  subcategoria_id: number | null;
  subcategoria_nome: string | null;
}

/**
 * Lista todas as categorias com suas subcategorias aninhadas, ordenadas
 * alfabeticamente nos dois níveis -- é exatamente a árvore que o seletor em
 * cascata do Flutter precisa para desenhar a Etapa 1 (categorias) e, depois
 * de escolhida uma, a Etapa 2 (subcategorias filtradas por ela).
 *
 * `LEFT JOIN` (não `JOIN`) de propósito: se um dia existir uma categoria
 * ainda sem nenhuma subcategoria cadastrada, ela continua aparecendo na
 * lista (só que com `subcategorias: []`), em vez de sumir silenciosamente.
 */
export async function listarCategoriasComSubcategorias(): Promise<CategoriaComSubcategorias[]> {
  const { rows } = await pool.query<LinhaCategoriaSubcategoria>(
    `SELECT
       c.categoria_id,
       c.nome                AS categoria_nome,
       s.subcategoria_id,
       s.nome                AS subcategoria_nome
     FROM categorias c
     LEFT JOIN subcategorias s ON s.categoria_id = c.categoria_id
     ORDER BY c.nome, s.nome`,
  );

  // Agrupa as linhas planas do SQL na árvore pai -> filhos que o Flutter
  // espera. Um Map preserva a ordem de inserção (= ordem do ORDER BY acima),
  // então não precisa de nenhum sort extra em JavaScript.
  const categoriasPorId = new Map<number, CategoriaComSubcategorias>();

  for (const linha of rows) {
    let categoria = categoriasPorId.get(linha.categoria_id);
    if (!categoria) {
      categoria = { id: linha.categoria_id, nome: linha.categoria_nome, subcategorias: [] };
      categoriasPorId.set(linha.categoria_id, categoria);
    }

    if (linha.subcategoria_id !== null && linha.subcategoria_nome !== null) {
      categoria.subcategorias.push({ id: linha.subcategoria_id, nome: linha.subcategoria_nome });
    }
  }

  return Array.from(categoriasPorId.values());
}
