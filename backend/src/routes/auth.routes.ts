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
  uuidObrigatorio,
  ErroDeValidacao,
  ErroDeConflito,
  ErroTelefoneNaoVerificado,
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
  buscarAdminPorEmail,
  criarClientePF,
  criarClientePJ,
  criarProfissionalPF,
  criarProfissionalPJ,
} from '../repositories/auth.repository';
import {
  gerarEEnviarCodigo,
  confirmarCodigo,
  PapelVerificavel,
} from '../repositories/verificacao-telefone.repository';

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

      // Dispara o primeiro código de verificação (migração 17) já aqui --
      // a conta acabou de nascer com `telefone_verificado = false`, e o
      // app abre a tela de confirmação em seguida. `verificacao.codigo` só
      // vem preenchido em MODO SIMULADO (ver services/sms.ts); em modo
      // real, o campo não existe na resposta -- o código só chega por SMS
      // mesmo.
      const verificacao = await gerarEEnviarCodigo('cliente', criado.id);

      return res.status(201).json({
        cliente_id: criado.id,
        tipo_pessoa: tipoPessoa,
        email,
        verificacao,
      });
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

      // Mesma ideia do cadastro de cliente acima -- ver comentário lá.
      const verificacao = await gerarEEnviarCodigo('profissional', criado.id);

      return res.status(201).json({
        profissional_id: criado.id,
        tipo_pessoa: tipoPessoa,
        email,
        verificacao,
      });
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

   Body: { papel: "cliente" | "profissional" | "admin", email, senha }

   Repare que o cliente do app PRECISA dizer qual papel está tentando logar
   -- não adivinhamos, porque a mesma pessoa pode ter conta nas duas tabelas.
   "admin" (migração 15) segue a MESMA rota -- só troca de onde busca o
   usuário. Sem rota de cadastro correspondente: contas admin são criadas
   por INSERT manual (ver `database/15_*.sql`), nunca por aqui.
   ========================================================================= */
authRouter.post('/login', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const body = req.body as Record<string, unknown>;

    const papel = body.papel;
    if (papel !== 'cliente' && papel !== 'profissional' && papel !== 'admin') {
      throw new ErroDeValidacao('O campo "papel" deve ser "cliente", "profissional" ou "admin".');
    }

    const email = emailValido(body.email);
    const senha = textoObrigatorio(body.senha, 'senha', { min: 1, max: 200 });

    const usuario =
      papel === 'cliente'
        ? await buscarClientePorEmail(email)
        : papel === 'profissional'
          ? await buscarProfissionalPorEmail(email)
          : await buscarAdminPorEmail(email);

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

    // Migração 17 -- e-mail/senha corretos, mas o telefone ainda não foi
    // confirmado. `admin` fica de fora (sempre `telefone_verificado: true`,
    // ver `buscarAdminPorEmail`) -- a checagem abaixo nunca dispara para
    // esse papel, mas o `if` some deixado explícito para o TypeScript
    // estreitar `papel` para `PapelVerificavel` ('cliente' | 'profissional').
    if (papel !== 'admin' && !usuario.telefone_verificado) {
      // Reenvia um código fresco na hora -- garante que a pessoa sempre
      // tem um código válido pronto pra usar, mesmo que o do cadastro já
      // tenha expirado (10 minutos) ou nunca tenha chegado.
      await gerarEEnviarCodigo(papel, usuario.id);
      throw new ErroTelefoneNaoVerificado(papel, usuario.id);
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

/** Lê e valida `papel` restrito a 'cliente' | 'profissional' -- as duas rotas de verificação abaixo nunca lidam com admin (ver comentário em ErroTelefoneNaoVerificado). */
function papelVerificavelObrigatorio(valor: unknown): PapelVerificavel {
  if (valor !== 'cliente' && valor !== 'profissional') {
    throw new ErroDeValidacao(`O campo "papel" deve ser "cliente" ou "profissional". Recebido: ${valor}.`);
  }
  return valor;
}

/* ============================================================================
   POST /auth/verificar-telefone/reenviar

   Body: { papel: "cliente" | "profissional", usuario_id: uuid }

   Gera e envia um código NOVO -- usado quando o código do cadastro expirou
   (10 minutos) ou nunca chegou. Sujeito ao intervalo mínimo entre envios
   (ver SEGUNDOS_ENTRE_ENVIOS em verificacao-telefone.repository.ts).
   ========================================================================= */
authRouter.post(
  '/verificar-telefone/reenviar',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Record<string, unknown>;
      const papel = papelVerificavelObrigatorio(body.papel);
      const usuarioId = uuidObrigatorio(body.usuario_id, 'usuario_id');

      const verificacao = await gerarEEnviarCodigo(papel, usuarioId);
      return res.json({ verificacao });
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   POST /auth/verificar-telefone/confirmar

   Body: { papel: "cliente" | "profissional", usuario_id: uuid, codigo: "123456" }

   Sem autenticação de propósito -- a pessoa ainda não tem token nesse
   momento (o cadastro não faz login automático mais, ver
   `POST /auth/login` acima). A "prova de posse" aqui é o próprio código,
   que só chegou no telefone dela.
   ========================================================================= */
authRouter.post(
  '/verificar-telefone/confirmar',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const body = req.body as Record<string, unknown>;
      const papel = papelVerificavelObrigatorio(body.papel);
      const usuarioId = uuidObrigatorio(body.usuario_id, 'usuario_id');
      const codigo = apenasDigitos(body.codigo, 'codigo', 6);

      await confirmarCodigo(papel, usuarioId, codigo);
      return res.json({ verificado: true });
    } catch (erro) {
      return next(erro);
    }
  },
);

/* ============================================================================
   GET /auth/me  -- rota protegida de exemplo.

   Prova de que o middleware funciona: sem token válido, cai em 401 antes
   de chegar aqui. Com token válido, devolve o que está DENTRO do token
   (não faz SELECT nenhum -- é só para você visualizar o payload).
   ========================================================================= */
authRouter.get('/me', exigirAutenticacao, (req: Request, res: Response) => {
  res.json({ usuario: req.usuario });
});
