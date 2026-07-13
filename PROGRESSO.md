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

---

## Sessão de 12/07/2026 (continuação 2 — Perfil do cliente + endereço de atuação do profissional)

### Pedido
Cliente precisava de um perfil próprio (foto, dados pessoais visíveis, edição, endereço fixo). Profissional precisava de um campo de "endereço de atuação padrão" para dar ao cliente uma noção de onde ele atende, sem depender só do pino no mapa.

### O que foi feito

**Backend**
- `database/06_perfil_cliente_endereco.sql` (nova migração) — `clientes.url_foto_perfil`, `clientes.endereco` (texto livre, não geocodificado) e `profissionais.endereco_atuacao` (também texto livre, só informativo — não entra no cálculo de distância, que continua vindo de latitude/longitude).
- `backend/src/repositories/clientes.repository.ts` (novo) — espelha o padrão de `profissionais.repository.ts`: `buscarMeuPerfil(clienteId)` e `atualizarMeuPerfil(clienteId, dados)` com `COALESCE` para update parcial. Diferente do perfil público do profissional, aqui `email` é devolvido normalmente — a rota é sempre o próprio dono do token, sem risco de scraping.
- `backend/src/routes/clientes.routes.ts` (novo) — `GET /clientes/me` e `PATCH /clientes/me` (multipart, campos `contato`/`endereco`/`foto_perfil`, todos opcionais mas ao menos um obrigatório), ambas atrás de `exigirAutenticacao` + `exigirPapel('cliente')`. Registrado em `app.ts` (`app.use('/clientes', clientesRouter)`).
- `profissionais.repository.ts` / `profissionais.routes.ts` — `PerfilPublicoProfissional`, `buscarPerfilPublico`, `AtualizacaoPerfilProfissional` e `atualizarPerfilProfissional` passam a expor/aceitar `endereco_atuacao`. `PATCH /profissionais/me` aceita o novo campo (texto, até 500 caracteres).

**Flutter**
- `lib/data/models/perfil_cliente.dart` (novo) — model `PerfilCliente` espelhando `GET /clientes/me`.
- `lib/data/services/clientes_service.dart` (novo) — `buscarMeuPerfil()` e `atualizarMeuPerfil(contato, endereco, foto)`.
- `lib/screens/perfil_cliente_screen.dart` (novo) — visualização + edição na MESMA tela (diferente do profissional, que tem tela pública separada da tela de edição): foto (avatar tocável), nome/e-mail somente leitura, contato e endereço editáveis, botão salvar que só manda os campos que de fato mudaram.
- `lib/screens/home_shell.dart` — ganhou 3ª aba "Perfil" na navegação inferior, visível **só para clientes** (o profissional já tem acesso à própria edição de perfil por outro caminho, então duplicar a aba seria redundante). Índice da aba atual é resetado com segurança se a lista de abas encolher.
- `lib/data/models/perfil_profissional.dart`, `lib/data/services/profissionais_service.dart`, `lib/screens/editar_perfil_screen.dart`, `lib/screens/perfil_profissional_screen.dart` — todos ganharam suporte a `enderecoAtuacao`: campo no model, parâmetro no `atualizarMeuPerfil`, novo `TextField` na tela de edição, e exibição (ícone de localização) no perfil público.

### Verificação feita
- Balanceamento de chaves/parênteses/colchetes em todos os arquivos Dart novos/alterados (script Python) — todos OK.
- `cd backend && npx tsc --noEmit` — sem erros.
- Não foi possível rodar `flutter analyze`/`flutter run` neste ambiente (sem SDK Flutter instalado) — checagem só estática.
- Mudanças commitadas em `git` (branch `main`).

### Pendências para a próxima sessão
1. **Rodar a migração `06_perfil_cliente_endereco.sql` no Neon** e reiniciar o backend — sem isso, `GET/PATCH /clientes/me` e o novo campo do profissional vão quebrar com "column does not exist".
2. Testar ponta a ponta no Flutter de verdade: login como cliente → aba "Perfil" aparece → editar foto/contato/endereço → salvar → conferir persistência. Login como profissional → editar perfil → preencher "endereço de atuação" → abrir o próprio perfil público (ou pedir para outro usuário abrir) → conferir que aparece.
3. Migrações `04` e `05` (sessões anteriores) — confirmar se já foram de fato aplicadas no Neon; se não, aplicar junto com a `06` na mesma sessão de banco.
4. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.


---

## Sessão de 12/07/2026 (continuação 3 — foto do cliente no portfólio + CEP do profissional)

### Pedido
1. Associar a foto de perfil do cliente às avaliações que ele faz para profissionais (no portfólio).
2. O profissional passa a informar um CEP (em vez de texto livre) para definir sua localização no mapa; remover o número de contato do profissional do portfólio público.

### Descoberta importante
Pesquisa mostrou que `latitude`/`longitude` de `profissionais`/`clientes` NUNCA foram capturadas em lugar nenhum (a tela de cadastro não envia coordenadas, e não existia via de edição depois). Ou seja, até esta sessão, **nenhum profissional aparecia na busca por proximidade do mapa** — bug latente, não só uma melhoria. A etapa do CEP resolve isso de verdade, não é só um "extra".

### O que foi feito

**1. Foto do cliente no portfólio**
- `database/07_foto_cliente_portfolio.sql` — `vw_historico_portifolio` passa a expor `clientes.url_foto_perfil` como `url_foto_cliente` (DROP+CREATE VIEW, mesmo padrão da migração 05).
- Backend: `ItemDePortfolio` ganha `url_foto_cliente` (o `SELECT v.*` em `buscarPortifolio` já propaga a coluna nova, sem precisar mudar a query).
- Flutter: `ItemPortfolio` ganha `urlFotoCliente`; `_CartaoPortfolio` usa a foto real do cliente no avatar do card, com fallback para iniciais quando o cliente não tiver foto.

**2. CEP define localização do profissional + remoção do contato**
- `database/08_cep_profissional.sql` — nova coluna `profissionais.cep`. `endereco_atuacao` muda de significado: era texto livre digitado, agora é AUTOMÁTICO (derivado do CEP).
- `backend/src/services/cep.ts` (novo, primeira pasta `services/` do projeto — para chamadas a APIs externas, diferente de `repositories/` que só fala com o Postgres) — consulta a BrasilAPI (`GET /api/cep/v2/{cep}`, gratuita, sem chave) usando `fetch` nativo do Node 18+ (nenhuma dependência nova). Devolve `{latitude, longitude, enderecoFormatado}` ou lança `ErroDeValidacao` amigável (CEP inexistente, serviço fora do ar, ou CEP sem coordenada geocodificável).
- `PATCH /profissionais/me` troca o campo `endereco_atuacao` (texto livre) por `cep` (8 dígitos): a rota geocodifica e grava `cep`+`latitude`+`longitude`+`endereco_atuacao` de uma vez só (os quatro sempre juntos, nunca parciais).
- Removido `contato` de `PerfilPublicoProfissional`, `buscarPerfilPublico` e `atualizarPerfilProfissional` (SELECT e RETURNING) — não é só ocultado na tela, o backend PARA de devolver o telefone nessa rota pública. (`buscarProximos`/`/proximos`, usada só para os pinos do mapa, não foi alterada — fora do escopo do pedido.)
- Flutter: `editar_perfil_screen.dart` troca o campo de texto livre por um campo de CEP (numérico, 8 dígitos, `FilteringTextInputFormatter.digitsOnly`), sempre vazio ao abrir a tela (mesmo padrão do seletor de foto — é só ENTRADA), mostrando "Localização atual: ..." como texto informativo abaixo. `PerfilProfissional` e a tela de perfil público perderam o campo/exibição de `contato`.

### Verificação feita
- Balanceamento de chaves/parênteses/colchetes (script Python) em todos os arquivos Dart alterados — OK.
- `cd backend && npx tsc --noEmit` — sem erros.
- `grep` confirmando que `contato` só aparece em comentários explicativos e no código de `/proximos` (fora do escopo), nunca mais em `PerfilPublicoProfissional`/`PerfilProfissional`/perfil público.
- Não foi possível testar a chamada real à BrasilAPI neste ambiente (sandbox sem acesso de rede a domínios externos) nem rodar `flutter run` — checagem só estática + revisão de tipos.
- Mudanças commitadas em `git` (branch `main`), dois commits.

### Pendências para a próxima sessão
1. **Rodar as migrações `07_foto_cliente_portfolio.sql` e `08_cep_profissional.sql` no Neon** (e confirmar que as anteriores, 04–06, já foram aplicadas) — sem isso, o app quebra com "column/view does not exist".
2. Testar de verdade a chamada à BrasilAPI a partir do backend rodando fora deste sandbox (ambiente do usuário tem rede de verdade) — confirmar que o formato de resposta bate com o que `cep.ts` espera (`location.coordinates.latitude/longitude` como string).
3. Testar ponta a ponta: profissional edita perfil → digita CEP válido → salva → confere que aparece na busca do mapa (`/profissionais/proximos`) e que o "endereço de atuação" no perfil público bate com o CEP informado. Testar também um CEP inválido/inexistente (mensagem de erro amigável esperada).
4. Confirmar visualmente que a foto do cliente aparece nos cards de avaliação do portfólio (depende de o cliente ter preenchido foto de perfil — ver sessão anterior).
5. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.

