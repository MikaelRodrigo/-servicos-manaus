import { Router, Request, Response, NextFunction } from 'express';
import {
  emailValido,
  textoObrigatorio,
  senhaObrigatoria,
  apenasDigitos,
  dataObrigatoria,
  tipoPessoaObrigatorio,
  numeroDoBody,
  inteiroPositivoObrigatorio,
  entre,
  ErroDeValidacao,
  ErroDeConflito,
} from '../utils/validacao';
import { gerarHashSenha, conferirSenha } from '../utils/senha';
import { gerarToken, Papel } from '../utils/jwt';
import { exigirAutenticacao } from '../middlewares/autenticacao';
import {
  ehErroDePostgres,
  PG_UNIQUE_VIOLATION,
  PG_FOREIGN_KEY_VIOLATION,
} from '../utils/erros-postgres';
import {
  buscarClientePorEmail,
  buscarProfissionalPorEmail,
  criarClientePF,
  criarClientePJ,
  criarProfissionalPF,
  criarProfissionalPJ,
} from '../repositories/auth.repository';

export const authRouter = Router();

/** Lê latitude/longitude OPCIONAIS do body. Ou vêm as duas, ou nenhuma (regra do banco). */
function lerCoordenadasOpcionais(body: Record<string, unknown>): {
  latitude?: number;
  longitude?: number;
} {
  const temLatitude = body.latitude !== undefined && body.latitude !== null;
  const temLongitude = body.longitude !== undefined && body.longitude !== null;

  if (!temLatitude && !temLongitude) {
    return {};
  }
  if (temLatitude !== temLongitude) {
    throw new ErroDeValidacao('Informe latitude E longitude juntas, ou nenhuma das duas.');
  }

  const latitude = entre(numeroDoBody(body.latitude, 'latitude'), -90, 90, 'latitude');
  const longitude = entre(numeroDoBody(body.longitude, 'longitude'), -180, 180, 'longitude');
  return { latitude, longitude };
}

/* ============================================================================
   POST /auth/cadastro/cliente

   Body PF:  { tipo_pessoa: "PF", email, senha, contato, nome, cpf }
   Body PJ:  { tipo_pessoa: "PJ", email, senha, contato, razao_social, cnpj, data_criacao? }
   ========================================================================= */
authRouter.post(
  '/cadastro/cliente',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Record<string, unknown>;

      const tipoPessoa = tipoPessoaObrigatorio(body.tipo_pessoa);
      const email = emailValido(body.email);
      const senha = senhaObrigatoria(body.senha);
      const contato = apenasDigitos(body.contato, 'contato', 11); // ex: 92988887777
      const senhaHash = await gerarHashSenha(senha);
      const coordenadas = lerCoordenadasOpcionais(body);

      const criado =
        tipoPessoa === 'PF'
          ? await criarClientePF({
              email,
              senhaHash,
              contato,
              nome: textoObrigatorio(body.nome, 'nome', { min: 3, max: 150 }),
              cpf: apenasDigitos(body.cpf, 'cpf', 11),
              ...coordenadas,
            })
          : await criarClientePJ({
              email,
              senhaHash,
              contato,
              razaoSocial: textoObrigatorio(body.razao_social, 'razao_social', {
                min: 2,
                max: 200,
              }),
              cnpj: apenasDigitos(body.cnpj, 'cnpj', 14),
              dataCriacao:
                body.data_criacao !== undefined
                  ? dataObrigatoria(body.data_criacao, 'data_criacao')
                  : undefined,
              ...coordenadas,
            });

      return res.status(201).json({ cliente_id: criado.id, tipo_pessoa: tipoPessoa, email });
    } catch (erro) {
      if (ehErroDePostgres(erro) && erro.code === PG_UNIQUE_VIOLATION) {
        return next(new ErroDeConflito('Já existe um cliente cadastrado com este e-mail/CPF/CNPJ.'));
      }
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /auth/cadastro/profissional

   Body PF:  { tipo_pessoa: "PF", email, senha, contato, nome, cpf, data_nascimento, categoria_id, subcategoria_id }
   Body PJ:  { tipo_pessoa: "PJ", email, senha, contato, razao_social, cnpj, categoria_id, subcategoria_id, data_criacao? }

   `categoria_id`/`subcategoria_id` (migração 09) são OBRIGATÓRIOS para os
   dois tipos de pessoa -- vêm do seletor em cascata do app (GET /categorias
   alimenta a lista), nunca de texto livre digitado. Isso substitui os
   antigos `profissao` (PF) e `categoria_atuacao` (PJ), que ficaram
   deprecados no banco (ver migração 09).
   ========================================================================= */
authRouter.post(
  '/cadastro/profissional',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Record<string, unknown>;

      const tipoPessoa = tipoPessoaObrigatorio(body.tipo_pessoa);
      const email = emailValido(body.email);
      const senha = senhaObrigatoria(body.senha);
      const contato = apenasDigitos(body.contato, 'contato', 11);
      const senhaHash = await gerarHashSenha(senha);
      const coordenadas = lerCoordenadasOpcionais(body);

      // Validados aqui em cima porque são idênticos para PF e PJ -- não faz
      // sentido duplicar a chamada dentro dos dois ramos abaixo.
      const categoriaId = inteiroPositivoObrigatorio(body.categoria_id, 'categoria_id');
      const subcategoriaId = inteiroPositivoObrigatorio(body.subcategoria_id, 'subcategoria_id');

      const criado =
        tipoPessoa === 'PF'
          ? await criarProfissionalPF({
              email,
              senhaHash,
              contato,
              nome: textoObrigatorio(body.nome, 'nome', { min: 3, max: 150 }),
              cpf: apenasDigitos(body.cpf, 'cpf', 11),
              dataNascimento: dataObrigatoria(body.data_nascimento, 'data_nascimento'),
              categoriaId,
              subcategoriaId,
              ...coordenadas,
            })
          : await criarProfissionalPJ({
              email,
              senhaHash,
              contato,
              razaoSocial: textoObrigatorio(body.razao_social, 'razao_social', {
                min: 2,
                max: 200,
              }),
              cnpj: apenasDigitos(body.cnpj, 'cnpj', 14),
              categoriaId,
              subcategoriaId,
              dataCriacao:
                body.data_criacao !== undefined
                  ? dataObrigatoria(body.data_criacao, 'data_criacao')
                  : undefined,
              ...coordenadas,
            });

      return res
        .status(201)
        .json({ profissional_id: criado.id, tipo_pessoa: tipoPessoa, email });
    } catch (erro) {
      if (ehErroDePostgres(erro) && erro.code === PG_UNIQUE_VIOLATION) {
        return next(
          new ErroDeConflito('Já existe um profissional cadastrado com este e-mail/CPF/CNPJ.'),
        );
      }
      // `subcategoria_id` não existe, ou existe mas não pertence à
      // `categoria_id` informada -- a FK composta da migração 09
      // (fk_profissionais_subcategoria_categoria) recusa o INSERT nos dois
      // casos. Traduzimos para uma mensagem que o app consegue mostrar,
      // em vez do erro cru do Postgres.
      if (ehErroDePostgres(erro) && erro.code === PG_FOREIGN_KEY_VIOLATION) {
        return next(
          new ErroDeValidacao('Categoria/subcategoria inválida. Selecione novamente na lista.'),
        );
      }
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /auth/login

   Body: { papel: "cliente" | "profissional", email, senha }

   Repare que o cliente do app PRECISA dizer qual papel está tentando logar
   -- não adivinhamos, porque a mesma pessoa pode ter conta nas duas tabelas.
   ========================================================================= */
authRouter.post('/login', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const body = req.body as Record<string, unknown>;

    const papel = body.papel;
    if (papel !== 'cliente' && papel !== 'profissional') {
      throw new ErroDeValidacao('O campo "papel" deve ser "cliente" ou "profissional".');
    }

    const email = emailValido(body.email);
    const senha = textoObrigatorio(body.senha, 'senha', { min: 1, max: 200 });

    const usuario =
      papel === 'cliente'
        ? await buscarClientePorEmail(email)
        : await buscarProfissionalPorEmail(email);

    /* -----------------------------------------------------------------------
       MENSAGEM GENÉRICA DE PROPÓSITO.

       "E-mail não encontrado" vs "senha incorreta" parece mais gentil, mas
       entrega de graça para um atacante quais e-mails existem no seu banco
       (enumeração de usuários). A resposta é SEMPRE a mesma nos dois casos.
       ----------------------------------------------------------------------- */
    const CREDENCIAIS_INVALIDAS = 'E-mail ou senha inválidos.';

    if (!usuario) {
      throw new ErroDeValidacao(CREDENCIAIS_INVALIDAS);
    }

    const senhaCorreta = await conferirSenha(senha, usuario.senha_hash);
    if (!senhaCorreta) {
      throw new ErroDeValidacao(CREDENCIAIS_INVALIDAS);
    }

    const token = gerarToken({ sub: usuario.id, papel: papel as Papel, email: usuario.email });

    return res.json({
      token,
      papel,
      usuario: {
        id: usuario.id,
        email: usuario.email,
        nome: usuario.nome_exibicao,
        url_foto_perfil: usuario.url_foto_perfil,
      },
    });
  } catch (erro) {
    return next(erro);
  }
});

/* ============================================================================
   GET /auth/me  -- rota protegida de exemplo.

   Prova de que o middleware funciona: sem token válido, cai em 401 antes
   de chegar aqui. Com token válido, devolve o que está DENTRO do token
   (não faz SELECT nenhum -- é só para você visualizar o payload).
   ========================================================================= */
authRouter.get('/me', exigirAutenticacao, (req: Request, res: Response) => {
  res.json({ usuario: req.usuario });
});
