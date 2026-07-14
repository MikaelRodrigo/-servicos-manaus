import { Router, Request, Response, NextFunction } from 'express';
import { buscarMeuPerfil, atualizarMeuPerfil } from '../repositories/clientes.repository';
import { textoOpcional, apenasDigitos, ErroDeValidacao, ErroNaoEncontrado } from '../utils/validacao';
import { exigirAutenticacao, exigirPapel } from '../middlewares/autenticacao';
import { uploadFotoPerfil, urlPublicaDoArquivoPerfil } from '../middlewares/upload';

export const clientesRouter = Router();

/* ============================================================================
   GET /clientes/me -- PRIVADA (exige login, só "cliente").

   Devolve os dados do PRÓPRIO cliente logado: nome, e-mail, contato,
   endereço, foto de perfil. Não existe `:id` na URL -- espelha o mesmo
   raciocínio de PATCH /profissionais/me: o cliente é sempre `req.usuario.sub`,
   nunca um ID escolhido de fora.
   ========================================================================= */
clientesRouter.get(
  '/me',
  exigirAutenticacao,
  exigirPapel('cliente'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const perfil = await buscarMeuPerfil(req.usuario!.sub);

      if (!perfil) {
        throw new ErroNaoEncontrado('Cliente não encontrado.');
      }

      return res.json(perfil);
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   PATCH /clientes/me -- PRIVADA (exige login, só "cliente").

   Edita o PRÓPRIO perfil: contato, endereço fixo e/ou foto de perfil.
   Mesmo padrão de PATCH /profissionais/me: multipart/form-data, todos os
   campos opcionais, mas ao menos um precisa vir.

   Content-Type: multipart/form-data
   Campos (todos opcionais, mas ao menos um precisa vir):
     contato     (texto, 11 dígitos -- telefone/WhatsApp)
     endereco    (texto, até 500 caracteres)
     foto_perfil (arquivo -- JPEG, PNG ou WEBP, até 5 MB)
   ========================================================================= */
clientesRouter.patch(
  '/me',
  exigirAutenticacao,
  exigirPapel('cliente'),
  uploadFotoPerfil,
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      // apenasDigitos exige o campo -- aqui o campo é opcional, então só
      // validamos o formato quando ele de fato veio no body.
      const contato =
        req.body.contato !== undefined && req.body.contato !== null && req.body.contato !== ''
          ? apenasDigitos(req.body.contato, 'contato', 11)
          : undefined;

      const endereco = textoOpcional(req.body.endereco, 'endereco', 500);
      const urlFotoPerfil = req.file
        ? urlPublicaDoArquivoPerfil(req.file as Express.MulterS3.File)
        : undefined;

      if (contato === undefined && endereco === undefined && urlFotoPerfil === undefined) {
        throw new ErroDeValidacao(
          'Envie ao menos "contato", "endereco" ou uma foto ("foto_perfil") para atualizar.',
        );
      }

      const perfilAtualizado = await atualizarMeuPerfil(req.usuario!.sub, {
        contato,
        endereco,
        urlFotoPerfil,
      });

      return res.json(perfilAtualizado);
    } catch (erro) {
      return next(erro);
    }
  },
);
