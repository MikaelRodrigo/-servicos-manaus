import { pool } from '../database';
import { StatusNotaFiscal } from '../utils/validacao';

/* ============================================================================
   `notas_fiscais` (migração 14) -- checklist item 4 ("Integrar API de
   emissão de nota fiscal via webhook na finalização do serviço").

   ESTE ARQUIVO SÓ CRIA O REGISTRO PENDENTE. A chamada de verdade à API de
   um provedor (eNotas, ou a prefeitura de Manaus diretamente) NÃO está
   implementada -- é uma integração externa nova, com as mesmas perguntas
   em aberto de credenciais/sandbox que o Pagar.me tinha (ver o aviso no
   topo de `services/gateway-pagamento.ts`), e sem um provedor escolhido
   ainda (o checklist cita eNotas só como exemplo, "ex: eNotas ou
   prefeitura local"). `criarNotaFiscalPendente` é chamada pela rota de
   confirmação (Etapa D) só para deixar o REGISTRO existindo -- um worker/
   job futuro (fora do escopo desta entrega) seria quem consome as linhas
   PENDENTE e efetivamente chama o provedor.
   ========================================================================= */

export interface NotaFiscal {
  id_nota: string;
  id_servico: string;
  id_transacao: string | null;
  status: StatusNotaFiscal;
  numero_nota: string | null;
  id_externo_provedor: string | null;
  url_pdf: string | null;
  erro: string | null;
  emitida_em: string | null;
  created_at: string;
  updated_at: string;
}

export async function criarNotaFiscalPendente(dados: {
  idServico: string;
  idTransacao: string;
}): Promise<NotaFiscal> {
  const { rows } = await pool.query<NotaFiscal>(
    `INSERT INTO notas_fiscais (id_servico, id_transacao)
     VALUES ($1, $2)
     RETURNING id_nota, id_servico, id_transacao, status, numero_nota,
               id_externo_provedor, url_pdf, erro, emitida_em, created_at, updated_at`,
    [dados.idServico, dados.idTransacao],
  );
  return rows[0];
}

export async function buscarNotaFiscalDoServico(idServico: string): Promise<NotaFiscal | null> {
  const { rows } = await pool.query<NotaFiscal>(
    `SELECT id_nota, id_servico, id_transacao, status, numero_nota,
            id_externo_provedor, url_pdf, erro, emitida_em, created_at, updated_at
       FROM notas_fiscais
      WHERE id_servico = $1
      ORDER BY created_at DESC
      LIMIT 1`,
    [idServico],
  );
  return rows[0] ?? null;
}
