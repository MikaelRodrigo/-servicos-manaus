# Guia para continuar o projeto — Serviços Manaus

Bem-vindo(a)! Este documento é para quem vai colaborar no projeto a partir de agora. Ele explica como configurar o backend e o app, e onde encontrar o que já foi feito e o que falta.

---

## 1. Onde ver o que já foi feito

Antes de mexer em qualquer coisa, leia o **[`PROGRESSO.md`](./PROGRESSO.md)** na raiz do repositório. Lá tem o log de cada sessão de trabalho: o que foi construído, bugs encontrados e o que ficou pendente. É o jeito mais rápido de entender onde o projeto parou sem precisar ler todo o histórico de commits.

Resumo rápido da stack:
- **Backend:** Node.js + TypeScript + Express + PostgreSQL/PostGIS (hospedado no [Neon](https://neon.tech)).
- **App:** Flutter (roda em mobile, web e desktop), usando Provider para estado, `flutter_map`/OpenStreetMap para o mapa.

---

## 2. Configurar o backend

```bash
cd backend
npm install
```

Copie o `.env.example` para `.env` e preencha com os dados do banco Neon (peça a senha para quem administra o banco, **nunca** por chat público):

```bash
# Windows (PowerShell)
copy .env.example .env
```

### Rodando as migrações do banco

O banco já existe no Neon (não é do zero). As migrações em `database/` precisam ser aplicadas **na ordem**, uma vez cada, direto no SQL Editor do Neon (ou via `psql`):

1. `01_schema.sql` — schema base (tabelas, PostGIS, views, triggers)
2. `02_seed_teste.sql` — dados de exemplo (opcional)
3. `03_auth_alter.sql` — colunas de autenticação (senha com hash)
4. `04_perfil_profissional.sql` — colunas `descricao` e `url_foto_perfil` do profissional

> **Se o banco do time já está rodando há um tempo**, provavelmente só a **migração 04** ainda não foi aplicada — é a mais recente. Rode ela e reinicie o backend antes de testar qualquer coisa relacionada a perfil de profissional.

Depois, suba o servidor:

```bash
npm run dev
```

Se aparecer `[http] Servidor ouvindo em http://localhost:3333`, está no ar. Teste em `http://localhost:3333/health`.

---

## 3. Configurar o app Flutter

```bash
cd app
flutter pub get
```

Confirme que o Flutter está instalado e configurado:

```bash
flutter doctor
```

Rode o app (mais simples para testar, funciona em qualquer máquina sem emulador):

```bash
flutter run -d chrome
```

Para rodar num emulador/celular Android, veja `lib/core/config/api_config.dart` — o endereço da API muda dependendo de onde o app roda (emulador Android usa `10.0.2.2`, não `localhost`). Já está tratado no código, mas é bom entender o porquê se algo não conectar.

---

## 4. O que já existe hoje (visão geral do app)

- Login e cadastro (cliente ou profissional, pessoa física ou jurídica).
- Mapa com busca de profissionais próximos por geolocalização, com filtro por profissão.
- Perfil público do profissional (toque no pino do mapa): foto, descrição, avaliações e portfólio de serviços anteriores.
- Edição do próprio perfil (só profissional): trocar foto e descrição.
- Fluxo completo de serviço: solicitar → aceitar/recusar → iniciar → concluir/cancelar, com botões que mudam conforme o papel logado (cliente ou profissional) e o status do serviço.
- Avaliação bilateral ao final de um serviço concluído (cliente avalia profissional com foto opcional; profissional avalia cliente).

---

## 5. Pendências conhecidas

Sempre confira o `PROGRESSO.md` para a lista atualizada, mas as principais no momento são:

- **Portabilidade:** as fotos de usuário (avaliações e perfil) ainda ficam salvas em disco local no servidor (`backend/uploads/`). Isso **não sobrevive a um deploy de verdade** em serviços como Render/Railway/Fly.io, que usam containers efêmeros. Antes de colocar em produção, trocar por um storage S3-compatible (ex.: Cloudflare R2) — o código já isola isso em `middlewares/upload.ts`, então a troca é localizada.
- Testar ponta a ponta o perfil público e a edição de perfil depois de rodar a migração 04.
- O emulador Android tem apresentado instabilidade (crash nativo) em uma das máquinas de desenvolvimento — testar em Chrome web contorna o problema, mas a causa raiz não foi confirmada.

---

## 6. Convenções do projeto (siga para manter consistência)

- **Nomes em português** em variáveis, funções, rotas e comentários — é assim em todo o código, mantenha o padrão.
- **Nenhuma query SQL solta em rotas.** Toda query mora em `backend/src/repositories/`. As rotas só validam entrada e chamam o repository.
- **Toda validação de entrada** usa os helpers de `backend/src/utils/validacao.ts` (ex.: `uuidObrigatorio`, `textoOpcional`) — não valide "na mão" dentro da rota.
- **Erros de negócio** usam as classes `ErroDeValidacao` (400), `ErroDeConflito` (409), `ErroNaoEncontrado` (404), `ErroDeAutenticacao` (401/403) — nunca `res.status(...).json(...)` direto numa rota; sempre `throw` e deixe o middleware de erro em `app.ts` tratar.
- **Nunca commitar** `.env`, `node_modules/`, `dist/`, ou qualquer coisa em `backend/uploads/` — o `.gitignore` já cobre isso, mas confira com `git status` antes de commitar.
- **Fotos públicas vs. sensíveis:** `url_foto_com_rg` (verificação de cadastro) **nunca** pode ser exposta em rota pública. Só `url_foto_perfil` aparece no perfil público.

---

## 7. Fluxo de trabalho recomendado

```bash
git pull                     # sempre antes de começar a mexer
# ... faça suas alterações ...
git add .
git commit -m "feat: descreva o que voce fez"
git push
```

Depois de terminar uma etapa, atualize o `PROGRESSO.md` com um resumo do que foi feito — ajuda muito quem for continuar depois de você.
