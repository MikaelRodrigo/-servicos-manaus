import { PayloadToken } from '../utils/jwt';

/* ============================================================================
   Por que este arquivo existe.

   TypeScript não sabe, por padrão, que um `Request` do Express pode ter uma
   propriedade `usuario` -- ela não existe na tipagem original do Express.
   Este arquivo faz "module augmentation": ele ENXERTA um campo novo na
   interface Request, só dentro do nosso projeto. É isso que permite escrever
   `req.usuario.papel` no controller sem o TypeScript reclamar "Property
   'usuario' does not exist on type 'Request'".

   O arquivo não precisa ser importado em lugar nenhum -- o `include` do
   tsconfig.json já pega tudo dentro de src/, e um arquivo .d.ts é aplicado
   globalmente sozinho.
   ========================================================================= */
declare global {
  namespace Express {
    interface Request {
      /** Presente SOMENTE depois que o middleware `exigirAutenticacao` rodou. */
      usuario?: PayloadToken;

      /**
       * Bytes CRUS do body, antes do `express.json()` desserializar --
       * preenchido pelo `verify` callback em `app.ts`. Existe só para o
       * webhook de pagamentos (`routes/pagamentos.routes.ts`): a
       * assinatura HMAC do Pagar.me (`X-Hub-Signature-256`) é calculada
       * sobre os bytes EXATOS que o gateway enviou -- reserializar
       * `req.body` de volta para JSON (`JSON.stringify`) não garante o
       * mesmo texto byte a byte (ordem de chaves, espaçamento), então
       * validar a assinatura contra o objeto já parseado seria frágil.
       * Qualquer outra rota pode ignorar este campo.
       */
      rawBody?: Buffer;
    }
  }
}

export {};
