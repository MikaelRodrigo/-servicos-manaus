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
  /**
   * Quantos profissionais têm essa subcategoria hoje -- alimenta o "(9)" ao
   * lado do nome no autocomplete de busca do mapa. Vem pronto de dentro da
   * MESMA query que já busca a árvore de categorias (um `COUNT` agregado com
   * `GROUP BY`, apoiado no índice `idx_profissionais_subcategoria_id` que já
   * existe desde a migração 09) -- não é uma contagem separada por
   * subcategoria a cada tecla digitada no app; o Flutter busca essa árvore
   * (com as contagens já embutidas) UMA vez por tela e filtra em memória
   * depois (ver `busca_subcategoria_autocomplete.dart`), então o "N+1" que
   * uma contagem por tecla causaria nunca chega a existir.
   */
  totalProfissionais: number;
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
  // `COUNT(...)` do Postgres sempre volta como string via node-postgres (é
  // um `bigint` debaixo do capô, que o driver não converte sozinho para
  // não perder precisão em números muito grandes) -- convertido pra
  // `number` na hora de montar `Subcategoria` abaixo.
  total_profissionais: string;
}

/**
 * Lista todas as categorias com suas subcategorias aninhadas, ordenadas
 * alfabeticamente nos dois níveis -- é exatamente a árvore que o seletor em
 * cascata do Flutter precisa para desenhar a Etapa 1 (categorias) e, depois
 * de escolhida uma, a Etapa 2 (subcategorias filtradas por ela). Também
 * inclui, para cada subcategoria, quantos profissionais estão cadastrados
 * nela agora (ver comentário em `Subcategoria.totalProfissionais`).
 *
 * `LEFT JOIN` (não `JOIN`) de propósito: se um dia existir uma categoria
 * ainda sem nenhuma subcategoria cadastrada, ela continua aparecendo na
 * lista (só que com `subcategorias: []`), em vez de sumir silenciosamente.
 * Mesma lógica no segundo `LEFT JOIN` (contra `profissionais`): uma
 * subcategoria sem nenhum profissional ainda aparece, só que com `(0)`.
 */
export async function listarCategoriasComSubcategorias(): Promise<CategoriaComSubcategorias[]> {
  const { rows } = await pool.query<LinhaCategoriaSubcategoria>(
    `SELECT
       c.categoria_id,
       c.nome                    AS categoria_nome,
       s.subcategoria_id,
       s.nome                    AS subcategoria_nome,
       COUNT(p.subcategoria_id)  AS total_profissionais
     FROM categorias c
     LEFT JOIN subcategorias s ON s.categoria_id = c.categoria_id
     LEFT JOIN profissionais p ON p.subcategoria_id = s.subcategoria_id
     GROUP BY c.categoria_id, c.nome, s.subcategoria_id, s.nome
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
      categoria.subcategorias.push({
        id: linha.subcategoria_id,
        nome: linha.subcategoria_nome,
        totalProfissionais: Number(linha.total_profissionais),
      });
    }
  }

  return Array.from(categoriasPorId.values());
}
