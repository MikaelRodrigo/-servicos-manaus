import { Router, Request, Response, NextFunction } from 'express';
import { apenasDigitos } from '../utils/validacao';
import { buscarEnderecoPorCep } from '../services/cep';

export const cepRouter = Router();

/* ============================================================================
   GET /cep/:cep -- PÚBLICA (sem login).

   Devolve só o ENDEREÇO (rua/bairro/cidade/UF) de um CEP, via ViaCEP --
   SEM geocodificar. Serve para o autofill em tempo real dos formulários que
   pedem CEP (hoje: editar perfil do profissional): o app chama esta rota
   assim que o usuário termina de digitar os 8 dígitos, e mostra o endereço
   na hora, como confirmação visual, antes mesmo de salvar.

   Por que uma rota separada de `PATCH /profissionais/me`? Porque aquela
   rota faz a geocodificação de verdade (ViaCEP + escada de tentativas no
   Nominatim, ver services/cep.ts) -- é mais lenta e só faz sentido rodar
   quando o formulário É DE FATO salvo. Chamar a geocodificação completa a
   cada tecla digitada seria desperdício (e mais lento pro usuário ver o
   preview). Esta rota reaproveita só a metade rápida (`buscarEnderecoPorCep`).
   ========================================================================= */
cepRouter.get('/:cep', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const cep = apenasDigitos(req.params.cep, 'cep', 8);
    const endereco = await buscarEnderecoPorCep(cep);

    return res.json({
      logradouro: endereco.logradouro ?? null,
      bairro: endereco.bairro ?? null,
      cidade: endereco.localidade ?? null,
      uf: endereco.uf ?? null,
    });
  } catch (erro) {
    return next(erro);
  }
});
