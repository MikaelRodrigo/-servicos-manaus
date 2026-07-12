# Progresso do Projeto — Serviços Manaus

Log de avanços por sessão de trabalho. Serve para retomar rápido de onde parou, sem precisar reler todo o histórico de conversa.

---

## Sessão de 12/07/2026

### Contexto no início do dia
O backend (Node/TypeScript/Express + PostgreSQL/PostGIS no Neon) já estava com auth, módulo de serviços (solicitar/aceitar/recusar/iniciar/concluir/cancelar) e avaliações (com upload de foto) prontos. O app Flutter já tinha login/cadastro, mapa com busca de profissionais próximos, navegação por abas (Mapa / Meus Serviços), tela de detalhe de serviço com ações por papel, e tela de avaliação.

### O que foi feito hoje

**1. Perfil público do profissional** (toque no pino do mapa → tela cheia com foto, descrição, avaliações e portfólio)

- Backend:
  - Migração `database/04_perfil_profissional.sql` — novas colunas `profissionais.descricao` e `profissionais.url_foto_perfil` (nullable). `url_foto_perfil` é **separada** de `url_foto_com_rg` de propósito: a do RG é dado sensível (LGPD), nunca pode virar foto pública.
  - `profissionais.repository.ts` — nova função `buscarPerfilPublico(id)`, que devolve o perfil sem o campo `email` (evita scraping/spam).
  - `profissionais.routes.ts` — nova rota pública `GET /profissionais/:id`.
- Flutter:
  - Novo model `PerfilProfissional` / `ResumoAvaliacoes` / `ItemPortfolio` (`lib/data/models/perfil_profissional.dart`).
  - `ProfissionaisService` ganhou `buscarPerfilPublico`, `buscarResumoAvaliacoes`, `buscarPortfolio` (as três rodam em paralelo com `Future.wait`).
  - Nova tela `PerfilProfissionalScreen`: foto, nome, atuação, descrição, médias por critério (técnico/comportamental/econômico), quantidade de serviços prestados, botão "Solicitar serviço" e lista de portfólio (foto + comentário + estrelas de cada cliente).
  - `ApiConfig.urlAbsoluta()` — helper novo para transformar os caminhos relativos do backend (`/uploads/...`) em URLs completas que o `Image.network` carrega.
  - `MapaScreen` agora navega direto para essa tela ao tocar no pino (removido o bottom sheet resumido antigo).

**2. Editar perfil do profissional** (foto + descrição — sem isso, os campos novos ficariam sempre vazios)

- Backend:
  - Nova rota `PATCH /profissionais/me` — autenticada, só para papel `profissional`, sempre edita o dono do token (nunca aceita um ID escolhido pelo cliente da API).
  - `middlewares/upload.ts` — novo middleware `uploadFotoPerfil` (campo `foto_perfil`, pasta `uploads/perfis/`, separada da pasta de fotos de avaliação).
  - `profissionais.repository.ts` — nova função `atualizarPerfilProfissional` (update parcial via `COALESCE`, só troca o que veio no request).
- Flutter:
  - `ApiClient.postMultipart` foi generalizado (antes só funcionava com POST e campo fixo `foto_servico`) em `_enviarMultipart` + dois métodos específicos: `postMultipart` (avaliação) e `patchMultipart` (perfil).
  - `ProfissionaisService.atualizarMeuPerfil()`.
  - Nova tela `EditarPerfilScreen`: mostra a foto atual, permite trocar (câmera/galeria), campo de texto "sobre mim", botão salvar.
  - Ícone de lápis no AppBar do mapa, visível só para profissional, abre essa tela.

### Bug encontrado ao testar (ainda não resolvido)
Ao buscar profissionais no mapa, apareceu **"Erro interno do servidor"**. Causa provável: a query `buscarProximos` já seleciona a coluna `url_foto_perfil`, mas a migração `04_perfil_profissional.sql` ainda não foi rodada no banco Neon — a coluna não existe de verdade lá, o Postgres reclama, e isso cai no handler de erro genérico (500).

**Solução:** rodar a migração no Neon (SQL Editor ou `psql`) e reiniciar o backend. Instruções detalhadas já foram passadas no chat.

### Pendências para a próxima sessão
1. **Rodar a migração 04 no Neon** e reiniciar o backend — sem isso, a busca no mapa continua quebrada.
2. Testar ponta a ponta: buscar no mapa → abrir perfil de um profissional → editar o próprio perfil (logado como profissional) → foto e descrição aparecendo certo.
3. Confirmar se o fix de upload de foto na avaliação (Content-Type/MediaType, feito antes de hoje) realmente resolveu o erro "Envie uma imagem JPEG, PNG ou WEBP."
4. **Task pendente (arquitetura):** portabilidade — Dockerfile do backend + trocar armazenamento de fotos em disco local por algo S3-compatible (ex.: Cloudflare R2) antes de qualquer deploy real. Ainda não iniciado, só planejado.
5. Emulador Android com crash nativo (ART) segue sem solução confirmada — desenvolvimento tem sido feito via Chrome web como alternativa. Cold boot do emulador foi sugerido, não testado.
6. Considerar permitir limpar a descrição (hoje, mandar texto vazio é tratado como "não mudar nada" — comportamento consistente dos dois lados, mas vale documentar/ajustar se incomodar no uso real).

### Arquivos novos ou alterados hoje

**Backend**
- `database/04_perfil_profissional.sql` (novo)
- `backend/src/repositories/profissionais.repository.ts`
- `backend/src/routes/profissionais.routes.ts`
- `backend/src/middlewares/upload.ts`

**Flutter (`app/`)**
- `lib/data/models/perfil_profissional.dart` (novo)
- `lib/data/models/profissional.dart`
- `lib/data/services/profissionais_service.dart`
- `lib/data/services/api_client.dart`
- `lib/core/config/api_config.dart`
- `lib/screens/perfil_profissional_screen.dart` (novo)
- `lib/screens/editar_perfil_screen.dart` (novo)
- `lib/screens/mapa_screen.dart`

### Como retomar na próxima sessão
1. Rodar `database/04_perfil_profissional.sql` no Neon (SQL Editor, ou `psql` com os dados do `.env`).
2. `cd backend` → `npm run dev`.
3. `cd app` → `flutter run -d chrome` (ou o device que estiver usando).
4. Testar: mapa → toque num pino → perfil público carrega sem erro → (logado como profissional) ícone de lápis → editar perfil → salvar → voltar ao mapa e conferir se a foto/descrição aparecem no perfil público.

---

## Sessão de 12/07/2026 (continuação — "Portfólio estilo Shopee")

### Contexto no início desta continuação
Ao retomar, o repositório tinha uma quantidade grande de mudanças NÃO commitadas (backend + app) implementando a etapa "múltiplas fotos por avaliação + curtidas ('Útil') no portfólio", além da migração `database/05_avaliacoes_fotos_curtidas.sql` (nova) e do router `backend/src/routes/curtidas.routes.ts` (novo). Essa etapa não estava documentada aqui ainda.

**O que essa etapa mudou (resumo):**
- Backend: `avaliacoes_profissional_fotos` (1 avaliação → N fotos, substitui a antiga coluna única `url_foto_servico`) e `avaliacoes_profissional_curtidas` (like/unlike por usuário). Upload passou de `.single('foto_servico')` para `.array('fotos_servico', 5)`. Nova rota pública-mas-sensível-a-login `GET /profissionais/:id/portfolio` (via `autenticacaoOpcional`) devolvendo `curtido_por_mim`. Nova rota `POST /avaliacoes/:avaliacaoId/curtir` (toggle).
- Flutter: `ItemPortfolio` ganhou `avaliacaoId`, `urlsFotos` (lista), `totalCurtidas`, `curtidoPorMim`. Tela de avaliação (`avaliacao_screen.dart`) ganhou seletor de várias fotos (até 5, com miniaturas e botão remover). Mapa ganhou marcador com foto de perfil do profissional (`_MarcadorProfissional`, com fallback e "raboinho").

### Bug encontrado e corrigido nesta continuação
`app/lib/screens/perfil_profissional_screen.dart` **não tinha sido atualizado** junto com o resto — `_CartaoPortfolio` ainda lia `item.urlFotoServico` (campo removido do model `ItemPortfolio`). Isso quebrava a compilação do app inteiro. Também foi encontrado (e corrigido) um `mapa_screen.dart` com o final do arquivo truncado no ambiente de execução (a classe `_AvisoFaixa` cortada no meio) — o conteúdo real no editor estava íntegro, mas valia a pena registrar: se algo parecer truncado de novo, comparar tamanho do arquivo antes de assumir que está tudo certo.

**Correção:** `_CartaoPortfolio` virou `StatefulWidget` (`_CartaoPortfolioState`) com:
- `_GaleriaDeFotos`: galeria de fotos com `PageView` + bolinhas de posição (estilo Shopee/Mercado Livre), some quando só tem 1 foto.
- Botão "Útil" (`Icons.thumb_up`) chamando `ProfissionaisService.curtirAvaliacao`, com estado local otimista atualizado pela resposta do servidor, e aviso pedindo login para quem não está autenticado.

### Verificação feita
- `cd backend && npx tsc --noEmit` → sem erros.
- Não foi possível rodar `flutter analyze` neste ambiente (Flutter SDK não instalado no sandbox) — checagem de sintaxe feita manualmente (balanceamento de chaves/parênteses/colchetes nos arquivos alterados) e revisão linha a linha de cada diff.
- Mudanças commitadas em `git` (branch `main`) ao final desta sessão.

### Pendências para a próxima sessão
1. **Rodar as migrações `04_perfil_profissional.sql` e `05_avaliacoes_fotos_curtidas.sql` no Neon** (nenhuma das duas foi confirmada como aplicada no banco real ainda) e reiniciar o backend.
2. Testar ponta a ponta no Flutter de verdade (`flutter run`) — este ambiente não tem o SDK do Flutter, então a tela nova (`_GaleriaDeFotos` + botão "Útil") nunca foi executada de fato, só revisada estaticamente.
3. Testar o fluxo completo: avaliar um profissional com várias fotos → abrir o perfil dele → ver a galeria deslizando → curtir/descurtir uma avaliação → conferir que o contador muda.
4. Itens antigos ainda pendentes (não avançaram nesta sessão): Dockerfile do backend + trocar uploads em disco por armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.
