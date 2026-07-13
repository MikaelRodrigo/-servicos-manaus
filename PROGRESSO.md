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

### Ambiente de desenvolvimento configurado (12/07/2026, sessão de setup)
Máquina de desenvolvimento preparada do zero: `npm install` no backend, Flutter SDK 3.44.6 instalado (`C:\src\flutter`, adicionado ao PATH), extensões Dart/Flutter no VS Code, Modo de Desenvolvedor do Windows ativado (necessário para o Flutter criar symlinks de plugins), `flutter pub get` rodado no `app/`. `flutter doctor` mostra Chrome OK; Android toolchain e Visual Studio (apps Windows) pendentes, mas não bloqueiam o fluxo atual (dev via `flutter run -d chrome`).

**Migração 04 aplicada no Neon** (via script Node com o driver `pg`, já que `psql` não está instalado na máquina) — colunas `descricao` e `url_foto_perfil` confirmadas em `profissionais`. Testado `GET /profissionais/proximos`: retorna os profissionais normalmente, bug do "Erro interno do servidor" no mapa **resolvido**.

**Conferido o estado geral do banco:** migrações `05`, `06`, `07` e `08` (das sessões de continuação registradas mais abaixo neste arquivo) já estavam aplicadas no Neon — só a `04` estava pendente de verdade. Banco agora com o schema completo (01 a 08) confirmado por consulta direta ao `information_schema`.

### Pendências para a próxima sessão
1. Testar ponta a ponta no app (Flutter): buscar no mapa → abrir perfil de um profissional → editar o próprio perfil (logado como profissional) → foto e descrição aparecendo certo.
2. Confirmar se o fix de upload de foto na avaliação (Content-Type/MediaType, feito antes de hoje) realmente resolveu o erro "Envie uma imagem JPEG, PNG ou WEBP."
3. **Task pendente (arquitetura):** portabilidade — Dockerfile do backend + trocar armazenamento de fotos em disco local por algo S3-compatible (ex.: Cloudflare R2) antes de qualquer deploy real. Ainda não iniciado, só planejado.
4. Emulador Android com crash nativo (ART) segue sem solução confirmada — desenvolvimento tem sido feito via Chrome web como alternativa. Cold boot do emulador foi sugerido, não testado. Android toolchain do Flutter (Android Studio + SDK) ainda não foi instalado nesta máquina.
5. Considerar permitir limpar a descrição (hoje, mandar texto vazio é tratado como "não mudar nada" — comportamento consistente dos dois lados, mas vale documentar/ajustar se incomodar no uso real).

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

---

## Sessão de 12/07/2026 (continuação 4 — corrigir geocodificação de CEP)

### Pedido
Usuário testou o CEP `69043000` (Manaus, válido) na tela de editar perfil e recebeu erro: "Não foi possível encontrar a localização exata desse CEP."

### Diagnóstico
A BrasilAPI v2 devolve endereço + coordenada numa chamada só, mas a coordenada vem da geocodificação embutida dela via Nominatim/OpenStreetMap — cuja cobertura endereço-a-ponto no Norte do Brasil é bem mais fraca que no Sul/Sudeste. Resultado: endereço encontrado, `location.coordinates` vazio, rota falha mesmo com CEP correto.

### O que foi feito
`backend/src/services/cep.ts` reescrito, separando as duas responsabilidades:
- **ViaCEP** (`viacep.com.br`) — só busca o endereço (rua/bairro/cidade/UF); não geocodifica, então não falha desse jeito.
- **Nominatim** (`nominatim.openstreetmap.org`) — geocodificação feita diretamente por nós, com escada de 3 tentativas cada vez mais genéricas: rua+bairro+cidade → bairro+cidade → só cidade-UF. Cidade inteira quase sempre geocodifica, então o pior caso vira "aparece no centro da cidade" em vez de falhar.
- Timeout de 8s por chamada externa (`AbortController`), como antes.
- Assinatura exportada (`buscarLocalizacaoPorCep(cep): Promise<{latitude, longitude, enderecoFormatado}>`) não mudou — nenhum outro arquivo (rota/repositório) precisou ser alterado.

### Incidente durante o commit (resolvido)
No primeiro commit desta etapa, `git add -A` reportou `error: bad signature 0x00000000` / `fatal: index file corrupt`, mas mesmo assim produziu um commit (`8d6e9ba`) — só que **vazio de conteúdo** (a árvore desse commit tinha 0 arquivos, um `git diff` contra o commit anterior mostrava só remoções). Ou seja, o índice corrompido fez o commit apagar o repositório inteiro do ponto de vista do Git, mesmo a mensagem do commit estando correta.

**Correção:** `git reset --hard HEAD~1` para voltar ao último commit bom (`b80c22a`, 197 arquivos íntegros), reaplicar o conteúdo novo de `cep.ts` e commitar de novo — desta vez com `git add` apontando só para o arquivo específico (não `-A`), evitando depender do índice completo. Novo commit: `abd2927`. Verificado depois: `git ls-tree -r HEAD | wc -l` = 197 (mesma contagem de antes), `git status` limpo, diff do commit mostra só o `cep.ts` (179 inserções, 116 remoções, 1 arquivo).

### Verificação feita
- `cd backend && npx tsc --noEmit` — sem erros.
- `git log --oneline` e `git ls-tree -r HEAD --name-only | wc -l` confirmando que o repositório está íntegro (197 arquivos) e o commit `abd2927` contém só a mudança esperada.
- Não foi possível testar a chamada real ao ViaCEP/Nominatim neste ambiente (sandbox sem acesso de rede a domínios externos).

### Pendências para a próxima sessão
1. **Rodar as migrações `07` e `08` no Neon** (e confirmar `04`–`06` já aplicadas) — segue pendente de sessões anteriores.
2. Testar de verdade o fluxo de CEP (agora ViaCEP + Nominatim) a partir do backend rodando fora deste sandbox, com CEPs reais de Manaus — inclusive o `69043000` que falhou antes.
3. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.

---

## Sessão de 12/07/2026 (continuação 5 — Etapa 9: Docker + storage S3-compatible)

### Contexto no início desta continuação
Ambiente de dev já preparado (sessão de setup anterior): backend rodando, todas as migrações (04-08) confirmadas aplicadas no Neon, bug do mapa resolvido. Faltava só o item de arquitetura "portabilidade" que aparecia como pendência em várias sessões anteriores: Dockerfile + trocar upload de fotos em disco local por storage S3-compatible.

### O que foi feito
Objetivo: tornar a API stateless para poder escalar/redeployar em containers efêmeros sem perder arquivo de usuário.

**1. Storage S3-compatible (Cloudflare R2 ou qualquer S3-compatible)**
- Dependências novas: `@aws-sdk/client-s3`, `multer-s3` (dependencies), `@types/multer-s3` (devDependency — `multer-s3` não vem com tipos próprios).
- `backend/src/services/uploadService.ts` (novo) — `S3Client` (endpoint/região/credenciais vindos de `env.s3`, `forcePathStyle: true` para compatibilidade com R2/MinIO), `criarStorageS3(prefixo)` (storage engine do multer-s3, chave aleatória `prefixo/uuid.ext`, nunca o nome original) e `filtroDeImagem` (mesma validação de tipo de sempre, compartilhada pelos dois uploads).
- `backend/src/middlewares/upload.ts` — reescrito para usar `criarStorageS3('avaliacoes')`/`criarStorageS3('perfis')` em vez de `multer.diskStorage`. Como o multer-s3 já sobe o arquivo pro bucket DURANTE o próprio middleware, `req.file`/`req.files[i]` chegam na rota com `.location` (URL pública) pronta — as funções `urlPublicaDoArquivo`/`urlsPublicasDosArquivos`/`urlPublicaDoArquivoPerfil` continuam existindo (mesma assinatura de chamada nas rotas), só que agora só leem `.location` em vez de montar um caminho local.
- `backend/src/routes/{avaliacoes,clientes,profissionais}.routes.ts` — só precisaram trocar o *type cast* de `Express.Multer.File` para `Express.MulterS3.File` (o `.location` só existe no tipo do multer-s3). Nenhuma outra rota, repository ou lógica de negócio mudou.
- `backend/src/app.ts` — removida a rota estática `/uploads` (`express.static`): não faz mais sentido, nenhum arquivo é mais escrito em disco.
- `backend/src/env.ts` — `env.s3` novo: `endpoint`, `region` (padrão `'auto'`), `bucketName`, `accessKeyId`, `secretAccessKey`. Todos **obrigatórios** (mesmo padrão de `DB_*`/`JWT_SECRET`) — decisão consciente: a API é stateless **inclusive em desenvolvimento**, para o comportamento nunca divergir entre ambientes. **Efeito colateral importante:** rodar `npm run dev` agora exige um bucket S3-compatible de verdade (ex.: Cloudflare R2, tier free) mesmo localmente — antes bastava clonar e rodar. Documentado no `.env.example` e no `CONTRIBUTING.md`.
- App Flutter: **nenhuma mudança necessária**. `ApiConfig.urlAbsoluta()` (`app/lib/core/config/api_config.dart`) já tinha `if (caminhoRelativo.startsWith('http')) return caminhoRelativo;` — como as URLs do multer-s3 já vêm absolutas (`https://...`), o helper só repassa. A promessa antiga do comentário em `upload.ts` ("todo o resto do sistema continua igual, só guardamos uma URL") se confirmou na prática.

**2. Dockerfile**
- `backend/Dockerfile` já existia de uma sessão anterior e já seguia multi-stage build (`node:20-alpine`, estágio `builder` com `npm install` + `npm run build`, estágio `runner` copiando só `package.json`+`dist/` e rodando `npm install --only=production`, `EXPOSE 3333`, `CMD ["node", "dist/server.js"]`) — não precisou de mudança.
- `backend/.dockerignore` estava **vazio** (0 bytes) — populado agora com `node_modules`, `dist`, `.env`/`.env.*` (exceto `.env.example`), `.git`, `uploads`.

### Verificação feita
- `cd backend && npx tsc --noEmit` — sem erros (inclusive depois de trocar os type casts para `Express.MulterS3.File`).
- `npm run build` — sem erros.
- Confirmado que `npm run dev` agora falha rápido e com mensagem clara (`[env] Variavel de ambiente obrigatoria ausente: S3_ENDPOINT...`) se as variáveis `S3_*` não estiverem no `.env` — comportamento esperado, mesmo padrão de erro já usado para `DB_*`.
- **Não foi possível testar um upload real** (nenhuma credencial S3/R2 configurada neste ambiente ainda) nem `docker build` (Docker não está instalado nesta máquina).

### Pendências para a próxima sessão
1. Se quiser validar a imagem Docker, instalar o Docker Desktop nesta máquina e rodar `docker build` a partir de `backend/`.
2. Rodar as migrações `07` e `08` no Neon se ainda não tiver feito (ver sessão anterior).
3. Emulador Android com crash nativo (ART) segue sem solução confirmada.
4. Apagar a conta de teste criada durante a validação (`teste.upload.r2@example.com`, profissional PF "Teste Upload R2") quando não precisar mais dela.

### Bucket R2 configurado e testado ponta a ponta (mesmo dia, continuação)
Bucket `servicos-manaus-uploads` criado no Cloudflare R2, público via R2.dev subdomain, API Token de conta gerado. `.env` preenchido com `S3_ENDPOINT`/`S3_BUCKET_NAME`/`S3_ACCESS_KEY_ID`/`S3_SECRET_ACCESS_KEY`.

**Bug pego e corrigido antes mesmo do teste manual:** o `.location` que o `multer-s3` devolve é montado a partir do `S3_ENDPOINT` (a API S3, que exige assinatura AWS até para GET) — **não** é a URL pública do bucket. Se tivéssemos usado `.location` direto, toda foto salva no banco teria uma URL que o app nunca conseguiria carregar. Corrigido adicionando `S3_PUBLIC_URL_BASE` (a URL do R2.dev subdomain) ao `env.ts`, e trocando `urlPublicaDoArquivo`/`urlsPublicasDosArquivos`/`urlPublicaDoArquivoPerfil` (`middlewares/upload.ts`) para montar a URL como `${S3_PUBLIC_URL_BASE}/${arquivo.key}` em vez de usar `arquivo.location`.

**Teste manual real, pelo app (Flutter Web/Chrome):** login como profissional de teste → editar perfil → trocar foto + descrição → salvar. Backend salvou a URL certa no banco (confirmado via query direta: `https://pub-....r2.dev/perfis/<uuid>.jpg`) e a URL respondia 200/`image/jpeg` via curl — mas **a foto não aparecia no app**.

**Segundo bug, achado testando de verdade (não teria aparecido só com typecheck/curl):** o bucket R2 não tinha política de **CORS** configurada. `curl` direto funciona sem CORS (não é o navegador aplicando a regra), mas o Flutter Web (renderer CanvasKit) busca a imagem via `fetch()`, que o navegador bloqueia sem os cabeçalhos `Access-Control-Allow-*`. Confirmado com `curl -I -X OPTIONS ... -H "Origin: ..."` devolvendo 403 antes da correção.

**Correção:** usuário adicionou uma CORS Policy no bucket (painel R2 → bucket → Settings → CORS Policy):
```json
[{ "AllowedOrigins": ["*"], "AllowedMethods": ["GET", "HEAD"], "AllowedHeaders": ["*"], "MaxAgeSeconds": 3600 }]
```
`AllowedOrigins: ["*"]` é aceitável nesta fase (dev/teste); quando o app tiver domínio de produção fixo, trocar pelo domínio real. Depois da mudança, `OPTIONS` passou a devolver `204` com `Access-Control-Allow-Origin: *`, e a foto passou a carregar no app. **Confirmado pelo usuário testando ao vivo no Chrome.**

### Verificação feita (atualizada)
- Upload real via app (não só script) testado ponta a ponta: editar perfil → foto sobe pro R2 → URL salva no banco → imagem carrega na tela.
- `curl` confirmando 200 + `Content-Type: image/jpeg` na URL pública, e confirmando os cabeçalhos CORS antes/depois da correção.
- Segue pendente: `docker build` (Docker não instalado nesta máquina).

### Dados fictícios de teste criados
20 profissionais + 20 clientes cadastrados via `POST /auth/cadastro/{profissional,cliente}` (script `seed_fake_users.js`, não versionado — rodou direto contra a API local). Senha padrão de todos: `Manaus123`. E-mails no padrão `nome.sobrenome.prof@teste.com` (profissionais) e `nome.sobrenome.cliente.cli@teste.com` (clientes). Profissionais com profissão variada e coordenadas aleatórias dentro da área urbana de Manaus (aparecem na busca do mapa). **Lembrar de apagar esses registros (e a conta `teste.upload.r2@example.com`) antes de qualquer lançamento real** — são só para preencher o app durante o desenvolvimento.

---

## Sessão de 13/07/2026 — Seleção de categoria em cascata (chip input)

### Pedido
Substituir os campos de texto livre "profissão" (PF) e "categoria de atuação" (PJ) por um único campo de busca que funciona como seletor em cascata: o profissional escolhe primeiro uma CATEGORIA (ex.: "Beleza e Bem-Estar"), depois uma SUBCATEGORIA filtrada por ela (ex.: "Barbeiro"), cada escolha "congelada" dentro do campo como um Chip removível. Sem texto livre — só seleção de uma lista fechada, para garantir integridade no banco. Lista de 7 categorias e ~60 subcategorias fornecida pelo usuário.

### O que foi feito

**Banco de dados**
- `database/09_categorias_subcategorias.sql` — novas tabelas `categorias` (pai) e `subcategorias` (filho, com FK para a categoria). Seed com as 7 categorias e todas as subcategorias fornecidas. `profissionais` ganha `categoria_id`/`subcategoria_id`, com uma **FK composta** `(subcategoria_id, categoria_id) REFERENCES subcategorias (subcategoria_id, categoria_id)` — o truque que faz o Postgres recusar automaticamente um par incoerente (ex.: categoria "Beleza" com subcategoria "Pedreiro"), sem precisar de trigger nem validação duplicada no backend. `profissao`/`categoria_atuacao` (texto livre antigo) ficam **deprecadas** (comentário no banco), mantidas só por causa de cadastros antigos.

**Backend**
- Novo `backend/src/repositories/categorias.repository.ts` + `backend/src/routes/categorias.routes.ts` — `GET /categorias` (pública), devolve a árvore categoria → subcategorias de uma vez (registrado em `app.ts`).
- `auth.repository.ts`/`auth.routes.ts` — cadastro de profissional (PF e PJ) agora EXIGE `categoria_id`/`subcategoria_id` (antes eram `profissao`/`categoria_atuacao`, opcionais e livres). Novo validador `inteiroPositivoObrigatorio` em `validacao.ts`. FK inválida (par categoria/subcategoria incoerente) vira erro 400 amigável, não erro cru do Postgres.
- `profissionais.repository.ts` — `buscarProximos`, `buscarPerfilPublico` e `atualizarPerfilProfissional` trocam `COALESCE(profissao, categoria_atuacao)` por `LEFT JOIN` em `subcategorias`/`categorias`. O campo `atuacao` no JSON continua com o MESMO nome de antes (agora vindo da subcategoria) — o Flutter existente (mapa, perfil público) não precisou de nenhuma mudança para continuar funcionando.

**Flutter**
- Novo model `app/lib/data/models/categoria.dart` (`Categoria` com lista de `Subcategoria` aninhada) e `app/lib/data/services/categorias_service.dart` (`GET /categorias`).
- Novo widget `app/lib/widgets/seletor_categoria_cascata.dart` (`SeletorCategoriaCascata`): campo único estilo `InputDecorator` que abre uma folha de baixo (`showModalBottomSheet` + `DraggableScrollableSheet`) com busca — a busca só FILTRA a lista já carregada, nunca vira texto livre. Categoria escolhida vira `InputChip` (toque no corpo reabre a escolha, toque no "x" remove); depois aparece um `ActionChip` "Escolher especialidade" que abre a mesma folha filtrada pela categoria; ao escolher, vira um segundo `InputChip` ao lado do primeiro. Remover a categoria remove a subcategoria junto.
- `cadastro_screen.dart` — os dois `TextFormField` antigos (`_profissao` do PF, `_categoriaAtuacao` do PJ) foram removidos; um único `SeletorCategoriaCascata` (compartilhado entre PF e PJ) aparece sempre que o papel é "profissional". Lista de categorias é buscada uma vez no `initState`. Validação bloqueia o envio se a categoria+subcategoria não estiverem completas, e `categoria_id`/`subcategoria_id` (inteiros) vão no corpo do cadastro.

### Verificação feita
- `cd backend && npx tsc --noEmit` — sem erros.
- Balanceamento de chaves/parênteses/colchetes (script Python, ignorando strings/comentários) em todos os arquivos Dart novos/alterados — OK.
- `git status`/`git ls-tree` confirmando que só os 12 arquivos esperados entraram no commit (6 novos + 6 alterados), árvore do commit com 203 arquivos (197 anteriores + 6 novos).
- Não foi possível rodar `flutter analyze`/`flutter run` neste ambiente (sem SDK Flutter) nem testar `GET /categorias` contra um Postgres de verdade (sandbox sem acesso de rede) — checagem só estática + revisão de tipos.

### Pendências para a próxima sessão
1. **Rodar a migração `09_categorias_subcategorias.sql` no Neon** (junto com `07`/`08` ainda pendentes) — sem isso, cadastro de profissional quebra (`categoria_id`/`subcategoria_id` não existem no banco).
2. Testar ponta a ponta de verdade: abrir cadastro como profissional (PF e PJ) → tocar no seletor → escolher categoria → escolher subcategoria → ver os dois chips → tentar remover um chip → cadastrar e conferir que o perfil público mostra a subcategoria escolhida em `atuacao`.
3. Considerar expor `categoria` (não só `atuacao`/subcategoria) na tela de perfil público, já que o backend agora devolve os dois — hoje só `atuacao` é exibida.
4. Avaliar se vale permitir EDITAR a categoria depois do cadastro (hoje, igual a antes, só é definida na hora de criar a conta — não existe campo no `PATCH /profissionais/me`).
5. ~~Dockerfile do backend + armazenamento S3-compatible~~ — feito na sessão "Etapa 9" acima (mesmo dia). Emulador Android com crash nativo (ART) segue sem solução confirmada.
