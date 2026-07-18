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
       * preenchido pelo `verify` callback em `app.ts`. Não é lido por
       * nenhuma rota hoje (o webhook de pagamentos verifica só um segredo
       * simples em header, não uma assinatura HMAC) -- mantido pronto para
       * quando a futura API Pix própria (`services/pix-proprio.ts`) definir
       * um esquema de assinatura sobre o corpo bruto.
       */
      rawBody?: Buffer;
    }
  }
}

export {};
