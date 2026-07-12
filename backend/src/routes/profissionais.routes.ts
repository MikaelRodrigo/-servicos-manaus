import { Router, Request, Response, NextFunction } from 'express';
import { env } from '../env';
import { buscarProximos, buscarPerfilPublico, atualizarPerfilProfissional } from '../repositories/profissionais.repository';
import {
  numeroObrigatorio,
  numeroOpcional,
  textoOpcional,
  entre,
  uuidObrigatorio,
  ErroNaoEncontrado,
  ErroDeValidacao,
} from '../utils/validacao';
import { buscarPortifolio, buscarResumoDeAvaliacoes } from '../repositories/avaliacoes.repository';
import { exigirAutenticacao, exigirPapel } from '../middlewares/autenticacao';
import { uploadFotoPerfil, urlPublicaDoArquivoPerfil } from '../middlewares/upload';

export const profissionaisRouter = Router();

/**
 * GET /profissionais/proximos
 *
 * Query params:
 *   latitude   (obrigatório)  -3.13013
 *   longitude  (obrigatório)  -60.02340
 *   raio_km    (opcional)     padrão 5, máximo RAIO_MAXIMO_KM
 *   profissao  (opcional)     "eletricista"
 *   pagina     (opcional)     padrão 1
 *   limite     (opcional)     padrão 20, máximo 100
 *
 * Exemplo:
 *   /profissionais/proximos?latitude=-3.13013&longitude=-60.02340&raio_km=5
 */
profissionaisRouter.get(
  '/proximos',
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      /* ---------------------------------------------------------------
         PASSO 1 - VALIDAR. Sempre antes de tocar no banco.

         Nada abaixo desta seção pode assumir que a entrada é confiável,
         porque a partir daqui ela é.
         --------------------------------------------------------------- */
      const latitude = entre(
        numeroObrigatorio(req.query.latitude, 'latitude'),
        -90,
        90,
        'latitude',
      );

      const longitude = entre(
        numeroObrigatorio(req.query.longitude, 'longitude'),
        -180,
        180,
        'longitude',
      );

      // O teto do raio vem do .env. Sem teto, `?raio_km=999999` faz o
      // Postgres varrer a tabela inteira a cada request.
      const raioKm = entre(
        numeroOpcional(req.query.raio_km, 'raio_km', 5),
        0.1,
        env.raioMaximoKm,
        'raio_km',
      );

      const profissao = textoOpcional(req.query.profissao, 'profissao', 100);

      const pagina = entre(numeroOpcional(req.query.pagina, 'pagina', 1), 1, 1000, 'pagina');
      const limite = entre(numeroOpcional(req.query.limite, 'limite', 20), 1, 100, 'limite');

      /* ---------------------------------------------------------------
         PASSO 2 - CONVERTER para o que o domínio entende.

         A API fala em quilômetros porque é o que faz sentido para quem
         usa o app. O PostGIS, com geography, fala em metros. A conversão
         acontece aqui, numa linha, e nunca mais se pensa nela.
         --------------------------------------------------------------- */
      const raioMetros = Math.round(raioKm * 1000);
      const offset = (pagina - 1) * limite;

      /* ---------------------------------------------------------------
         PASSO 3 - CONSULTAR.
         --------------------------------------------------------------- */
      const profissionais = await buscarProximos({
        latitude,
        longitude,
        raioMetros,
        profissao,
        limite,
        offset,
      });

      /* ---------------------------------------------------------------
         PASSO 4 - RESPONDER.

         Devolvo um objeto com metadados, não um array cru. Quando o
         Flutter precisar de paginação (Etapa 7), o contrato já existe e
         você não quebra o app dos usuários.
         --------------------------------------------------------------- */
      return res.json({
        parametros: { latitude, longitude, raio_km: raioKm, profissao: profissao ?? null },
        pagi