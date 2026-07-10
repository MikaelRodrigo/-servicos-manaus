import { app } from './app';
import { env } from './env';
import { testarConexao, fecharConexao } from './database';

/**
 * Ponto de entrada.
 *
 * Repare que ele é separado do `app.ts`. Isso não é frescura: quando você
 * for escrever testes (supertest), você importa o `app` sem subir servidor
 * nenhum na porta 3333. Se estivesse tudo num arquivo só, cada teste tentaria
 * ocupar a porta.
 */
async function iniciar(): Promise<void> {
  // Bate no banco ANTES de abrir a porta. Se o Postgres não está de pé,
  // é melhor o processo morrer agora do que aceitar requests e falhar todos.
  await testarConexao();

  const servidor = app.listen(env.port, () => {
    console.log(`[http] Servidor ouvindo em http://localhost:${env.port}`);
    console.log(`[http] Teste: http://localhost:${env.port}/health`);
  });

  /* -------------------------------------------------------------------------
     GRACEFUL SHUTDOWN

     Quando você aperta Ctrl+C, o SO manda SIGINT. Sem o código abaixo, o Node
     morre no ato -- no meio de qualquer request em andamento, com conexões do
     Postgres penduradas. Aqui a gente para de aceitar novas conexões, termina
     as que estão em curso, fecha o pool e só então sai.
     ------------------------------------------------------------------------- */
  const encerrar = async (sinal: string) => {
    console.log(`\n[http] ${sinal} recebido. Encerrando...`);

    servidor.close(async () => {
      await fecharConexao();
      console.log('[http] Encerrado com sucesso.');
      process.exit(0);
    });

    // Se em 10s não terminou, força a saída.
    setTimeout(() => {
      console.error('[http] Timeout no shutdown. Forçando saída.');
      process.exit(1);
    }, 10_000).unref();
  };

  process.on('SIGINT', () => void encerrar('SIGINT'));
  process.on('SIGTERM', () => void encerrar('SIGTERM'));
}

iniciar().catch((erro) => {
  console.error('[fatal] Falha ao iniciar o servidor:', erro);
  process.exit(1);
});
