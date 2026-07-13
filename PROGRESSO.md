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
5. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.

---

## Sessão de 13/07/2026 (continuação — busca global de subcategoria no mapa do cliente)

### Pedido
Componente de busca na tela do CLIENTE (mapa): uma única barra que filtra em tempo real TODAS as subcategorias de TODAS as categorias (sem exigir escolher a categoria pai antes), com autocomplete mostrando a categoria pai como contexto ("Eletricista (em: Manutenção e Reforma)"). Ao selecionar, vira Chip e a busca no mapa passa a filtrar exatamente por aquela subcategoria. Sem texto livre -- só itens da árvore já cadastrada.

### Achado inesperado: commit concorrente de outro colaborador
No meio desta etapa, um `git log` revelou um commit novo (`54f1c0c`, autor "Alexandre Martins", diferente do "Mikael Rodrigo" de todos os commits anteriores) que já tocava os mesmos três arquivos de backend que eu estava editando (`validacao.ts`, `profissionais.routes.ts`, `profissionais.repository.ts`) -- aparentemente uma versão paralela/anterior do mesmo trabalho. Esse commit carregava um bug: um comentário SQL com crase (`` `subcategoria_id` ``) dentro de um template literal JS também delimitado por crase, o que fecha a string prematuramente e quebra a compilação (`tsc` acusava `Unterminated template literal`). Corrigido removendo as crases do comentário; o restante do commit (função `inteiroPositivoOpcional`, parâmetro `subcategoria_id` na rota) já batia com o que eu ia implementar, então não precisou reverter nada, só consertar o bug e seguir.

**Lição:** como o repositório local É a mesma pasta que outras pessoas/ferramentas podem tocar, vale sempre rodar `git log --oneline -5` antes de commitar algo que mexe em arquivo compartilhado, para não sobrescrever trabalho concorrente sem perceber.

### O que foi feito

**Backend**
- `profissionais.repository.ts` -- corrigido o bug de crase citado acima (SQL do `buscarProximos` volta a compilar).

**Flutter**
- Novo widget `app/lib/widgets/busca_subcategoria_autocomplete.dart` (`BuscaSubcategoriaAutocomplete`): usa o `Autocomplete<T>` nativo do Flutter. A lista de subcategorias é "achatada" (cada subcategoria pareada com sua categoria-pai) UMA VEZ em `initState`/`didUpdateWidget`, não a cada tecla -- digitar só filtra esse array pequeno em memória, sem chamada de rede. Busca por "começa com" (prioridade) e "contém", normalizando acento/maiúscula. Resultado escolhido vira `InputChip` removível (campo de busca some enquanto o chip existir); dropdown redimensiona com `LayoutBuilder` para acompanhar a largura do campo (responsivo).
- `profissionais_service.dart`/`profissionais_provider.dart` -- `buscarProximos` ganha `subcategoriaId` (filtro exato), complementar ao `profissao` textual legado que já existia.
- `mapa_screen.dart` -- troca o `TextField` de busca livre por profissão pelo novo `BuscaSubcategoriaAutocomplete`. Categorias carregadas uma vez no `initState` (falha silenciosa se a rede falhar -- o mapa em si continua funcionando). Selecionar/remover uma especialidade rebusca automaticamente no mapa, sem botão "aplicar" separado.

### Verificação feita
- `cd backend && npx tsc --noEmit` -- sem erros (depois de corrigir o bug de crase).
- Balanceamento de chaves/parênteses/colchetes verificado de duas formas: script Python com remoção de strings/comentários (deu falso positivo em `mapa_screen.dart` por causa de `'Olá, ${usuario?.nome ?? ''}'` -- aspas simples aninhadas dentro de uma interpolação confundem uma regex simples) E contagem bruta sem nenhuma remoção (que teoricamente pode ter o problema oposto, mas bateu limpo em todos os arquivos: chaves/parênteses/colchetes exatamente iguais). Tratado como confiável dado que os dois métodos, juntos, cobrem os casos problemáticos.
- **Armadilha de sincronização confirmada de novo:** em pelo menos 4 arquivos nesta etapa (`validacao.ts`, `profissionais.repository.ts`, `profissionais.routes.ts`, `profissionais_provider.dart`), o conteúdo visto pela ferramenta de edição (lado "Windows") não bateu com o que o `bash`/mount enxergava logo em seguida -- em alguns casos por truncamento (arquivo cortado no meio), em outros por bytes nulos sobrando no fim do arquivo. Sempre que isso aconteceu, a causa raiz só foi confirmada comparando `wc -l`/conteúdo bruto dos dois lados e reescrevendo o arquivo inteiro via heredoc no mount. **Conclusão prática: não dá mais para presumir sincronização "ao vivo" entre os dois lados -- todo arquivo tocado precisa ser conferido (grep/wc -l/`file`) no mount antes de rodar `tsc`/commitar.**
- `git status`/`git ls-tree` confirmando árvore com 204 arquivos (203 anteriores + 1 novo) e commit `e4a357c` só com os 5 arquivos esperados.

### Pendências para a próxima sessão
1. Testar de verdade no Flutter (`flutter run`): digitar no campo de busca do mapa, conferir que o dropdown aparece com "em: Categoria", selecionar um resultado, ver o Chip aparecer, conferir que o mapa refiltra pelos profissionais daquela subcategoria exata, remover o Chip e ver a busca voltar ao normal.
2. Migrações `07` a `09` seguem pendentes de rodar no Neon (ver seções anteriores).
3. Confirmar com o time/colaborador (autor do commit `54f1c0c`) se há mais trabalho em andamento nos mesmos arquivos, para evitar decisões de arquitetura divergentes no backend de categorias.
4. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.

---

## Sessão de 13/07/2026 (continuação — editar categoria/subcategoria e CEP no perfil)

### Pedido
"Permitir editar a categoria, subcategoria, e o cep." Até aqui, categoria/subcategoria só podiam ser definidas uma vez, no cadastro (não existia campo para trocar depois); a edição de CEP já existia de uma sessão anterior.

### O que foi feito

**Backend**
- `profissionais.repository.ts` — `AtualizacaoPerfilProfissional` ganhou `categoriaId?`/`subcategoriaId?` (mesmo espírito do trio cep/latitude/longitude: só existem JUNTOS). `atualizarPerfilProfissional` agora também atualiza `categoria_id`/`subcategoria_id` via `COALESCE` no mesmo `UPDATE`.
- `profissionais.routes.ts` — `PATCH /profissionais/me` passa a aceitar `categoria_id`/`subcategoria_id` no corpo multipart. Validação: os dois precisam vir juntos ou nenhum (erro 400 amigável se só um vier); passam a contar também no "ao menos um campo precisa vir". Violação da FK composta (par categoria/subcategoria incoerente) vira o mesmo erro amigável já usado no cadastro (`ErroDeValidacao` traduzindo `PG_FOREIGN_KEY_VIOLATION`).

**Flutter**
- `perfil_profissional.dart` — `PerfilProfissional` ganha campo `categoria` (nome da categoria-mãe), espelhando o que o backend já devolvia desde a etapa da hierarquia mas o app ainda não lia.
- `profissionais_service.dart` — `atualizarMeuPerfil` ganha `categoriaId`/`subcategoriaId` (enviados como string no multipart, igual ao padrão dos outros campos).
- `editar_perfil_screen.dart` — ganhou o `SeletorCategoriaCascata` (reaproveitado do cadastro), seguindo a MESMA convenção já usada pelo campo de CEP: o seletor começa sempre vazio (nunca pré-preenchido com a categoria atual), e a categoria/especialidade atual aparece só como texto informativo abaixo ("Categoria atual: Eletricista (em: Manutenção e Reforma)"). Validação bloqueia salvar se só a categoria for escolhida sem a subcategoria. Ao salvar com sucesso, o seletor volta a ficar vazio e o texto informativo é atualizado com o novo valor.

### Verificação feita
- `cd backend && npx tsc --noEmit` — sem erros.
- Balanceamento de chaves/parênteses/colchetes (script Python, raw count + stripped) em todos os arquivos Dart alterados — OK nos dois métodos.
- `git log --oneline -5`/`git status` checados ANTES de commitar (lição da sessão anterior) — sem commits concorrentes desta vez, só os 5 arquivos esperados no `git status`.
- **Sincronização mount vs. Windows conferida de novo:** todos os 5 arquivos (2 backend + 3 Flutter) vieram truncados no mount depois das edições (`file`/`wc -l`/`tail` confirmaram corte no meio do conteúdo). Reescritos por inteiro via heredoc a partir do conteúdo autoritativo (lado Windows), reconferidos (`file` voltou "UTF-8 text" limpo, `wc -l` bateu com o esperado, `tail` mostrou o fim real do arquivo) antes de compilar/commitar.
- Commit `ef5713a`.
- Não foi possível rodar `flutter analyze`/`flutter run` neste ambiente (sem SDK Flutter instalado no sandbox) — checagem só estática (leitura manual + balanceamento) + `tsc` no backend.

### Pendências para a próxima sessão
1. Testar de verdade no Flutter: abrir "Editar meu perfil" como profissional, conferir que aparece "Categoria atual: ...", escolher uma categoria/subcategoria nova, salvar, e confirmar que o perfil público passa a mostrar a nova subcategoria/categoria.
2. Migrações `07` a `09` seguem pendentes de rodar no Neon (bloqueiam tudo que depende de categoria/subcategoria/CEP em produção).
3. Rodar `flutter pub get && flutter analyze` de verdade num ambiente com SDK Flutter, já que este sandbox não tem o toolchain — a verificação desta sessão ficou só em nível estático/manual do lado Flutter.
4. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.

---

## Sessão de 13/07/2026 (continuação — redesign visual global do app)

### Pedido
Aplicar um redesign na interface para deixá-la mais moderna, clean e sofisticada, seguindo 6 diretrizes: bordas arredondadas (≥12-16px) em cards/botões/campos; sombras suaves em vez de bordas pesadas; mais respiro (padding/margin); paleta neutra + uma cor de destaque, tipografia sem serifa com bom espaçamento entre linhas; hover/transições leves (0.3s) em botões e cards; remoção de poluição visual (bordas/divisórias marcadas, cores fortes em excesso). Pedido para aplicar "globalmente".

### O que foi feito
Como é um app Flutter (não CSS web), "global" foi resolvido com um `ThemeData` central que cascateia para todas as telas, combinado com a remoção de overrides locais que bloqueavam esse tema.

- **Novo `app/lib/core/theme/app_theme.dart`** — `AppRadius` (10/14/16/20px) e `AppColors` (paleta neutra: cinza claro `#F6F7F9`, branco, texto `#1F2937`/`#667085`, destaque teal `#12A594`) como tokens centrais. Função `construirTemaClaro()` monta um `ThemeData` (Material 3) cobrindo: `cardTheme` (raio 16px, sombra suave via `shadowColor`+elevação baixa, `surfaceTintColor: transparent` pra não deixar o Material 3 tingir os cards de roxo), `inputDecorationTheme` (campo preenchido cinza claro, raio 14px, sem borda visível), botões (`Elevated`/`Filled`/`Outlined`/`Text`, todos com raio 14px, padding maior, `animationDuration` de 220ms e elevação/overlay reativos a hover via `WidgetStateProperty`), `chipTheme`, `dividerTheme` (mais fino e discreto), `navigationBarTheme`, `snackBarTheme`, `bottomSheetTheme`, `dialogTheme`, `listTileTheme` e um `TextTheme` customizado com mais espaçamento entre linhas (height 1.3–1.5).
- **`main.dart`** — troca o `ThemeData` mínimo inline por `construirTemaClaro()`.
- **Limpeza de overrides locais** que travavam o novo tema: removidos `border: OutlineInputBorder()` hardcoded (cantos retos) de todos os campos de texto em `login_screen.dart`, `cadastro_screen.dart`, `editar_perfil_screen.dart`, `perfil_cliente_screen.dart`, `perfil_profissional_screen.dart`, `avaliacao_screen.dart`, `busca_subcategoria_autocomplete.dart` e `seletor_categoria_cascata.dart` — agora todos herdam o campo preenchido/arredondado do tema.
- **Ajustes pontuais de respiro e cor:** padding maior em `login_screen.dart`/`cadastro_screen.dart` (24→28), `mapa_screen.dart` (12→16) e `servicos_screen.dart` (12→16, espaçamento entre itens 8→12); cartão verde forte de "já avaliado" (`servico_detalhe_screen.dart`) suavizado para um verde-água claro com ícone outline; botão de adicionar foto em `avaliacao_screen.dart` trocado de borda tracejada cinza para container preenchido arredondado; dropdown de busca (`busca_subcategoria_autocomplete.dart`) ganhou sombra mais elevada e raio maior (8→14px).

### Verificação feita
- Balanceamento de chaves/parênteses/colchetes (script Python, raw count + stripped) em todos os 13 arquivos tocados — OK.
- Revisão manual linha a linha de cada diff (sem SDK Flutter neste sandbox, então sem `flutter analyze`/`flutter run`).
- `git fsck --full` e `git show --stat HEAD` depois do commit, confirmando árvore íntegra e sem corrupção.
- Commit único `f362313` (13 arquivos, 322 inserções/45 remoções).

### Dois bugs novos de sandbox descobertos e documentados (para não perder tempo de novo)
1. **"Git racy"/leitura inconsistente:** `git status`/`git diff` deixaram de detectar mudanças reais em 2 arquivos (`mapa_screen.dart`, `servicos_screen.dart`) mesmo com `git hash-object` provando que o conteúdo no worktree era diferente do commitado. Diagnóstico: `git update-index --refresh` (acusa "needs update"). Correção segura: `rm -f .git/index && git reset` (reconstrói o índice a partir do HEAD, SEM tocar no worktree — nunca usar `git reset --hard`, que descartaria as mudanças não commitadas).
2. **Criação de diretório do object database falha silenciosamente:** `git hash-object -w`/`git add` num arquivo novo (`app_theme.dart`) falharam repetidamente com `unable to create temporary file: No such file or directory`. Causa: o subdiretório de dois dígitos hex do SHA1 (`.git/objects/a7/`) não ficava confiavelmente visível no mount deste sandbox mesmo depois de "criado com sucesso" — bug de consistência do bind-mount, não do Git. **Contorno:** loop de retry chamando `git hash-object -w`, adicionando uma quebra de linha no fim do arquivo a cada falha (muda o SHA1/prefixo) até cair num prefixo de diretório que já existia — funcionou na 2ª tentativa. Sempre confirmar o blob resultante com `git cat-file -t`/`-p` antes de seguir.

### Pendências para a próxima sessão
1. Testar de verdade no Flutter (`flutter run`): conferir visualmente cards arredondados, sombras, campos preenchidos sem borda, hover em botões (web/desktop) e espaçamento geral em todas as telas principais (login, cadastro, mapa, meus serviços, perfis).
2. Considerar adicionar a fonte Inter/Poppins via pacote `google_fonts` **num ambiente com acesso de rede/toolchain completo** — não foi feito aqui de propósito, pois este sandbox não consegue verificar se o pacote resolve/compila (ficou só com a Roboto padrão do Flutter + `TextTheme` customizado).
3. Migrações `07` a `09` seguem pendentes de rodar no Neon (itens antigos, não relacionados ao redesign).
4. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real; emulador Android com crash nativo (ART) sem solução confirmada.

### Atualização: emulador Android voltou a funcionar
Nesta mesma sessão (via Android Studio, ver seção abaixo), o emulador Pixel 7 (API 37.1) **bootou normalmente e rodou o app sem o crash nativo (ART)** relatado em sessões anteriores — não precisou de cold boot nem de nenhum contorno especial. O item "emulador Android com crash nativo" acima pode estar resolvido (talvez uma atualização do Android Studio/SDK entre sessões tenha corrigido); vale confirmar de novo se o problema reaparecer.

---

## Sessão de 13/07/2026 (continuação — testar redesign no Android Studio + corrigir filtro de subcategoria)

### Pedido
1. Rodar o app no Android Studio para visualizar o redesign numa interface de dispositivo móvel de verdade (não só Chrome web).
2. Bug relatado pelo usuário: "O sistema não está mais conseguindo filtrar os profissionais depois que colocamos o filtro inteligente e as subcategorias 'pai e filhas'".

### Parte 1 — Rodando no Android Studio
- Projeto aberto em `app/` no Android Studio; plugin Flutter não estava instalado (`Configure plugins...` → instalar → Restart IDE) — depois disso o projeto passou a ser reconhecido como Flutter de verdade.
- `flutter pub get` rodado pela própria IDE — "Got dependencies!" sem erro.
- Tentativa em "Windows (desktop)" falhou: `Unable to find suitable Visual Studio toolchain` (falta o workload de C++ do Visual Studio na máquina). Tentativa em "Chrome (web)" funcionou, mas não serve para ver a interface como dispositivo móvel.
- **Emulador Android Pixel 7 (API 37.1)**, já configurado no Device Manager, foi iniciado e **bootou sem o crash nativo (ART)** documentado em sessões anteriores — rodou o app normalmente (`flutter run` → Gradle `assembleDebug` → instalação do APK). Redesign confirmado visualmente: campos arredondados sem borda pesada, seletor cliente/profissional em pílula, botão de destaque arredondado, bom espaçamento — bateu com as 6 diretrizes pedidas na sessão do redesign.

### Parte 2 — Bug do filtro de subcategoria
**Diagnóstico:** revisão de código completa da cadeia (Flutter `BuscaSubcategoriaAutocomplete` → `mapa_screen.dart` → `ProfissionaisService`/`ApiClient` → rota `GET /profissionais/proximos` → validação → `buscarProximos` no repository → SQL) não encontrou nenhum bug lógico — todo o encadeamento estava correto e consistente. A causa raiz é um problema de **dado, não de código**: profissionais cadastrados **antes** da migração 09 (hierarquia categoria/subcategoria) — incluindo o seed de teste `02_seed_teste_1.sql`, que usa só o campo antigo `profissao` — ficaram com `subcategoria_id = NULL`. O filtro EXATO `p.subcategoria_id = $7` não tinha como casar com eles, então qualquer busca filtrada por especialidade os excluía por completo (mesmo aparecendo normalmente no mapa sem filtro nenhum).

**Correção** (`backend/src/repositories/profissionais.repository.ts`, função `buscarProximos`): o filtro de subcategoria ganhou um FALLBACK — quando `p.subcategoria_id IS NULL` (profissional pré-migração 09), compara o texto livre antigo (`profissao`/`categoria_atuacao`) contra o NOME da subcategoria pedida, com o mesmo `LIKE` já usado no filtro textual legado (`$4`). Profissionais já migrados (com `subcategoria_id` preenchido) continuam usando só o match exato por ID, sem ambiguidade nenhuma.

### Verificação feita
- Revisão de código completa de toda a cadeia Flutter → backend antes de escrever qualquer linha (para não "consertar" algo que já estava certo).
- `cd backend && npx tsc --noEmit` — sem erros.
- `git diff` conferido linha a linha antes do commit — só a mudança pretendida (23 inserções, 3 remoções).
- Commit `2f18c4c`.
- **Não foi possível confirmar contra o banco real** (sandbox sem acesso de rede à Neon) se o problema é exatamente esse ou se as migrações 07-09 nunca chegaram a rodar em produção (pendência antiga, repetida em quase toda sessão) — o fallback cobre AMBOS os cenários prováveis relacionados a dado legado, mas se a rota inteira estiver retornando 500 (colunas/tabelas não existirem de verdade no banco), a causa é outra (migração não aplicada) e este fix sozinho não resolve.

### Pendências para a próxima sessão
1. **Confirmar no ambiente real do usuário** se o filtro por especialidade volta a mostrar profissionais antigos depois deste fix. Se a busca continuar vazia (ou der erro 500), o suspeito nº 1 passa a ser as migrações `07`/`08`/`09` nunca aplicadas no Neon — item pendente há várias sessões, ver seções anteriores.
2. Rodar as migrações `07` a `09` no Neon (segue sem confirmação de que foi feito).
3. Investigar por que "Windows (desktop)" não builda (`Unable to find suitable Visual Studio toolchain`) — instalar o workload "Desktop development with C++" do Visual Studio Build Tools, se um dia for necessário rodar como app desktop nativo.
4. Itens antigos ainda pendentes: Dockerfile do backend + armazenamento S3-compatible antes de deploy real.

---

## Sessão de 13/07/2026 (continuação — backfill de categoria/subcategoria em vez de fallback na query)

### Pedido
Usuário considerou o fix anterior (fallback textual dentro de `buscarProximos`) uma solução inferior: "A melhor solução não seria essa, preciso que vc dê uma classe e categoria para os profissionais que estavam sem." — ou seja, corrigir o DADO na raiz (todo profissional com `categoria_id`/`subcategoria_id` de verdade), não compensar na leitura a cada busca.

### O que foi feito
- **Revertido** o fallback textual em `buscarProximos` (commit `2f18c4c`) de volta ao match exato simples por `subcategoria_id` — a query volta a ser só `AND ($7::int IS NULL OR p.subcategoria_id = $7::int)`, sem comparar contra texto livre antigo.
- **Nova migração `database/10_backfill_categoria_subcategoria.sql`**, em duas passadas:
  1. **Backfill inteligente por nome**: para profissionais com `subcategoria_id IS NULL` e algum texto livre antigo (`profissao`/`categoria_atuacao`), procura a subcategoria cujo NOME aparece dentro desse texto (`unaccent`/`lower`/`LIKE`, igual ao filtro textual legado). Usa `LATERAL` + `ORDER BY length(nome) DESC LIMIT 1` para pegar o match mais específico em caso de ambiguidade (ex.: "Eletricista Residencial" bate com a subcategoria "Eletricista").
  2. **Rede de segurança "Outros"**: nova categoria + subcategoria "Outros" (criadas na própria migração), atribuída a quem sobrou depois do passo 1 — texto vazio ou profissão que não bate com nenhuma subcategoria conhecida. Depois desta migração, NENHUM profissional fica com `categoria_id`/`subcategoria_id` NULL. Quem caiu em "Outros" pode editar o próprio perfil depois (`PATCH /profissionais/me`) para escolher a especialidade certa.
  3. Bloco de verificação (`DO $$ ... RAISE NOTICE`) no final, no mesmo padrão da migração 09, reportando quantos profissionais existem, quantos ainda ficaram sem categoria (esperado: 0) e quantos caíram em "Outros".

### Verificação feita
- `cd backend && npx tsc --noEmit` — sem erros (depois de reverter o fallback).
- `git diff` conferido — a mudança em `profissionais.repository.ts` é exatamente o revert esperado (23 remoções líquidas na cláusula do WHERE).
- **Sincronização mount vs. Windows conferida de novo:** `profissionais.repository.ts` veio com bytes nulos sobrando no fim do arquivo depois da edição (mesmo padrão de sessões anteriores) — reescrito por inteiro via heredoc a partir do conteúdo autoritativo, reconferido (`tail -c | cat -A` limpo) antes de compilar/commitar. A migração nova (arquivo novo) veio íntegra de primeira.
- Commit `c66a712`.
- **Não foi possível rodar a migração contra o banco real nem testar o backfill de verdade** (sandbox sem acesso de rede à Neon) — a lógica do `LIKE`/`LATERAL` foi revisada manualmente linha a linha, mas o comportamento real (quantos profissionais caem em "Outros", se o match por nome funciona como esperado com os dados reais) só pode ser confirmado rodando no Neon.

### Pendências para a próxima sessão
1. **Rodar a migração `10_backfill_categoria_subcategoria.sql` no Neon** (junto com `07`/`08`/`09`, que também seguem pendentes) — sem isso, o filtro por especialidade continua quebrado para profissionais antigos.
2. Depois de rodar, conferir a saída do `RAISE NOTICE` (quantos profissionais caíram em "Outros") e, se for um número alto, considerar revisar manualmente esses casos (talvez o texto livre tivesse profissões válidas que simplesmente não bateram com o `LIKE`).
3. Testar de verdade: filtrar por uma especialidade no mapa e confirmar que profissionais antigos (cadastrados antes da migração 09) voltam a aparecer.
4. Itens antigos ainda pendentes: migrações `07`-`09` no Neon; Dockerfile do backend + armazenamento S3-compatible antes de deploy real; investigar build "Windows (desktop)" (`Visual Studio toolchain`).

---

## Sessão de 13/07/2026 (continuação — recorte de foto de perfil antes do upload)

### Pedido
Usuário pediu recurso de recorte de foto de perfil antes do upload final, especificando `cropper.js` (via CDN/npm), modal com `aspectRatio` 1:1, botão "Confirmar" com `getCroppedCanvas`, e integração no "componente de formulário de cadastro". A especificação usava termos de projeto web puro (input file, cropper.js, form submit) que não existem neste projeto — é Flutter/Dart, não HTML/JS.

### Esclarecimento (via AskUserQuestion)
Como `cropper.js` não roda em Flutter, e a tela de cadastro (`cadastro_screen.dart`) nem sequer tem campo de foto (confirmado via busca — a foto de perfil é escolhida só depois, nas telas de edição de perfil), perguntei ao usuário se queria o equivalente nativo Flutter. Escolheu: "Equivalente em Flutter (Recomendado)" — mesma UX (escolher foto → recortar 1:1 com zoom → confirmar → pronta pro upload), usando um pacote nativo de recorte, integrado nas telas de foto de perfil já existentes.

### O que foi feito
- **Novo widget compartilhado** `app/lib/widgets/selecao_foto_perfil.dart`:
  - `escolherEEditarFotoDePerfil(context)`: função que unifica o fluxo completo — escolher origem (câmera/galeria) → `ImagePicker` → recortar em 1:1 via `ImageCropper` (pacote `image_cropper`) → devolve `XFile` + bytes já lidos, ou `null` se cancelado em qualquer etapa.
  - `AvatarFotoPerfil`: widget visual (avatar redondo + selo de câmera + botão "Trocar foto de perfil"), também compartilhado.
  - As duas telas que tratam foto de perfil (`editar_perfil_screen.dart`, do profissional, e `perfil_cliente_screen.dart`, do cliente) tinham exatamente a mesma lógica de escolha de foto duplicada — agora as duas usam este único widget, eliminando a duplicação e garantindo que nunca divirjam.
- **`app/pubspec.yaml`**: adicionada dependência `image_cropper: ^8.1.0` — equivalente Flutter ao `cropper.js`: tela nativa de recorte com zoom/arraste no Android (UCrop) e iOS (TOCropViewController), implementação em JS por baixo no Flutter Web (mesmo princípio de canvas do cropper.js), tudo sob uma única API Dart.
- **`app/ios/Runner/Info.plist`**: adicionadas `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` — faltavam completamente no projeto (gap pré-existente, não causado por esta feature, mas que bloqueava qualquer acesso a câmera/galeria no iOS: sem essas chaves, o app crasha ao pedir a permissão, sem erro amigável).
- `editar_perfil_screen.dart` e `perfil_cliente_screen.dart`: `_escolherFoto()` (lógica completa duplicada) virou `_trocarFoto()` (chama o widget compartilhado); o bloco de avatar inline em `build()` virou `AvatarFotoPerfil(...)`.

### Verificação feita
- Balanceamento de chaves/parênteses/colchetes (script Python) nos 3 arquivos Dart tocados/criados — OK.
- Revisão manual linha a linha de cada `git diff` (sem SDK Flutter neste sandbox — não é possível rodar `flutter analyze`/`flutter pub get`/`flutter run` aqui).
- **Corrupção de mount de novo** (mesmo bug de sempre): `pubspec.yaml`, `editar_perfil_screen.dart`, `perfil_cliente_screen.dart` e `Info.plist` vieram com bytes nulos sobrando depois das edições — todos reescritos por inteiro via heredoc a partir do conteúdo autoritativo (com `sed -i 's/$/\r/'` para restaurar CRLF em `pubspec.yaml`/`Info.plist`, que usam final de linha do Windows), reconferidos limpos antes de commitar. `selecao_foto_perfil.dart` (arquivo novo) sincronizou limpo de primeira.
- Commit `55bd799` (5 arquivos, 200 inserções/120 remoções).

### Pendências para a próxima sessão
1. **Rodar `flutter pub get` numa máquina com Flutter/rede** (ex.: via Android Studio, como já foi feito com sucesso nesta sessão para outra tarefa) para confirmar que `image_cropper ^8.1.0` resolve e compila sem conflito com as outras dependências — não verificável neste sandbox.
2. Testar o fluxo completo na prática: escolher foto → tela de recorte abre corretamente → confirmar → preview batendo com o que foi salvo, em ambas as telas (profissional e cliente), Android e (se possível) iOS.
3. Itens antigos ainda pendentes: rodar migrações `07`-`10` no Neon; Dockerfile do backend + armazenamento S3-compatible antes de deploy real; investigar build "Windows (desktop)" (`Visual Studio toolchain`).

---

## Sessão de 13/07/2026 (continuação — contagem de profissionais por subcategoria no autocomplete)

### Pedido
No dropdown de busca por especialidade do mapa (`BuscaSubcategoriaAutocomplete`), mostrar quantos profissionais ativos existem em cada subcategoria, no formato "Encanador (9)". Pedido veio com orientação explícita de performance: evitar "N+1" (contar a cada tecla digitada) e preferir uma contagem pré-calculada/indexada, cacheada localmente.

### Decisão de arquitetura
Em vez de uma tabela de contagem mantida por trigger (sugerida como opção no pedido), optei por um `COUNT`+`GROUP BY` agregado direto na MESMA query que já monta a árvore de categorias (`GET /categorias`) — apoiado no índice parcial `idx_profissionais_subcategoria_id`, que já existe desde a migração 09. Motivo: essa árvore já é buscada **uma única vez por tela** (`_carregarCategorias` no `initState` de `mapa_screen.dart`) e cacheada em memória no Flutter — a busca em si (`_buscar` no autocomplete) já filtra 100% em memória, sem nenhuma chamada de rede por tecla. Ou seja, o requisito de "não contar a cada tecla" já estava satisfeito pela arquitetura existente; bastava a contagem vir embutida nessa única busca, sem precisar de tabela/trigger extra (que adicionaria complexidade real: decrementar/incrementar em toda troca de subcategoria de um profissional, sem nenhum ganho de performance perceptível na escala atual do projeto).

**Observação também comunicada:** o schema não tem nenhum conceito de profissional "ativo"/"inativo" hoje (sem coluna de status, sem soft-delete) — a contagem é de todos os profissionais cadastrados naquela subcategoria. Se um conceito de ativo/inativo for necessário no futuro, é uma migração nova separada.

### O que foi feito
- **`backend/src/repositories/categorias.repository.ts`**: a query de `listarCategoriasComSubcategorias` ganhou um segundo `LEFT JOIN` (contra `profissionais`) + `COUNT(p.subcategoria_id)` + `GROUP BY`. Interface `Subcategoria` ganhou `totalProfissionais: number` (convertido de string, já que `COUNT` do Postgres volta como `bigint`/string via `node-postgres`).
- **`app/lib/data/models/categoria.dart`**: `Subcategoria` ganhou `totalProfissionais` (default `0`, para não quebrar nenhum outro ponto que já construía o objeto).
- **`app/lib/widgets/busca_subcategoria_autocomplete.dart`**: `title` de cada linha do dropdown virou um `Row` com o nome da subcategoria + `'(${total})'` num `Text` com `textTheme.bodySmall` + cinza (`Colors.grey.shade600`) — mesmo padrão visual já usado em outros textos informativos secundários do app (ex.: "Localização atual: ..." em `editar_perfil_screen.dart`), pra manter o nome como foco visual principal e o número como detalhe.

### Verificação feita
- `cd backend && npx tsc --noEmit` — sem erros.
- Balanceamento de chaves/parênteses/colchetes (script Python) nos 2 arquivos Dart tocados — OK.
- **Corrupção de mount de novo** (mesmo bug recorrente): os 3 arquivos (`categorias.repository.ts`, `categoria.dart`, `busca_subcategoria_autocomplete.dart`) vieram truncados no mount depois das edições — reescritos por inteiro via heredoc a partir do conteúdo autoritativo, reconferidos (`wc -l`/`file` batendo com o esperado) antes de compilar/commitar.
- `git diff --stat` conferido antes do commit — só os 3 arquivos esperados, tamanho de diff batendo com a mudança pretendida.
- Commit `d9f56a9` (3 arquivos, 63 inserções/6 remoções).
- **Não foi possível testar contra o banco real** (sandbox sem acesso de rede à Neon) — a lógica do `COUNT`+`GROUP BY` foi revisada manualmente, mas o valor exibido em produção só pode ser confirmado depois que as migrações pendentes (`07`-`10`) rodarem no Neon.

### Pendências para a próxima sessão
1. Testar de verdade no Flutter: digitar no campo de busca do mapa e conferir que cada sugestão mostra "(N)" corretamente, com N batendo com a quantidade real de profissionais daquela subcategoria no banco.
2. Itens antigos ainda pendentes: rodar migrações `07`-`10` no Neon; Dockerfile do backend + armazenamento S3-compatible antes de deploy real; investigar build "Windows (desktop)" (`Visual Studio toolchain`); testar fluxo de recorte de foto de perfil numa máquina com Flutter/rede.

---

## Sessão de 13/07/2026 (continuação — corrigir recorte de foto que não respondia no Flutter Web)

### Pedido
Usuário testou o recorte de foto no Chrome web (rodando de fato, pela primeira vez desde que a feature foi implementada) e reportou: o modal "Crop Image" aparece normalmente, mas arrastar a imagem para reposicionar e o slider de zoom não fazem nada.

### Diagnóstico
Pesquisa confirmou que o `image_cropper` usa, no alvo Web, a biblioteca JS **Cropper.js** para implementar o arraste/zoom de verdade — o modal em si (título, imagem, slider, botões) é desenhado pelo plugin em Dart e aparece de qualquer jeito, mas os `<link>`/`<script>` do Cropper.js precisam ser adicionados manualmente em `web/index.html` (documentado no README do pacote, mas não fazia parte do pubspec/scaffold do Flutter). Sem eles, o Cropper.js nunca é carregado, então os controles ficam visíveis só que sem nenhum handler de evento — exatamente o sintoma relatado.

### O que foi feito
`app/web/index.html` — adicionadas as duas tags exigidas pelo pacote, dentro do `<head>`:
```html
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/cropperjs/1.6.2/cropper.css" />
<script src="https://cdnjs.cloudflare.com/ajax/libs/cropperjs/1.6.2/cropper.min.js"></script>
```
Só afeta o alvo Web — Android (UCrop) e iOS (TOCropViewController) usam implementação nativa própria, sem depender dessa biblioteca JS.

### Verificação feita
- `git diff` conferido — só as 13 linhas esperadas (mesmo padrão CRLF do resto do arquivo, restaurado com `sed -i 's/$/\r/'` depois da reescrita via heredoc, já que o mount truncou o arquivo no meio de uma palavra depois da primeira edição — mesmo bug recorrente de sempre).
- Commit `b0e904e`.
- **Não testável neste sandbox** (sem Flutter/Chrome real aqui) — depende do usuário recarregar a página (`flutter run -d chrome` de novo, ou refresh se o hot reload não pegar mudança em `index.html`) e confirmar que arrastar/zoom passam a responder.

### Pendências para a próxima sessão
1. **Confirmar com o usuário** que o recorte responde a arraste/zoom depois desse fix (pode precisar reiniciar `flutter run`, não só hot reload, já que `index.html` é carregado uma vez no boot da página).
2. Testar o mesmo fluxo em Android/iOS (não deveriam ser afetados por este bug, que era só do Web, mas vale confirmar que continuam funcionando).
3. Itens antigos ainda pendentes: rodar migrações `07`-`10` no Neon; Dockerfile do backend + armazenamento S3-compatible antes de deploy real; investigar build "Windows (desktop)" (`Visual Studio toolchain`).

---

## Sessão de 13/07/2026 (continuação — filtros avançados: raio de proximidade + ordenação por avaliação)

### Pedido
Sistema avançado de filtros na busca do cliente: (1) filtro de raio de proximidade com opções 1/2/3/4/5 km, recalculando distância via Haversine entre GPS do usuário e cada profissional; (2) filtro de ordenação por avaliação multicritério ("Melhor Custo-Benefício" vs "Melhores Avaliados"), com o sistema de avaliação descrito como baseado em três critérios (Custo-Benefício, Pontualidade, Qualidade); (3) chips reativos abaixo da busca principal, atualizando mapa/lista instantaneamente; (4) estética clean consistente com o redesign.

### Descobertas antes de implementar
- **O raio já era configurável no backend** desde sempre (`raio_km`, PostGIS `ST_DWithin`/`ST_Distance` sobre `geography`, que já calcula distância geodésica real — o próprio Postgres/PostGIS faz o equivalente a Haversine internamente, de forma mais precisa que uma fórmula manual). O que faltava era só o Flutter deixar de mandar um valor fixo (`raioKm: 10`, hardcoded em `mapa_screen.dart`) e virar uma escolha do usuário.
- **Os critérios de avaliação do schema são outros**: `avaliacoes_profissional` (migração 01) tem `estrelas_tecnico`/`estrelas_comportamental`/`estrelas_economico` — não "Custo-Benefício/Pontualidade/Qualidade" como descrito no pedido. Não existe "pontualidade" em lugar nenhum do banco. Mapeamento adotado (comunicado no commit e aqui): "econômico" (preço justo pelo serviço) é o mais próximo em significado de "custo-benefício"; "média geral" (os três critérios juntos) atende "Melhores Avaliados". Como o filtro pedido só precisava de DOIS critérios de ordenação (não dos três), não foi necessário criar uma migração nova para "pontualidade" — ficaria fora de escopo; fica registrado aqui caso o usuário queira esse critério de verdade no futuro.

### O que foi feito

**Backend**
- `profissionais.repository.ts`: `buscarProximos` ganhou `ordenarPor` (`'distancia' | 'melhor_custo_beneficio' | 'melhores_avaliados'`). As médias de avaliação são pré-agregadas numa ÚNICA subquery (`GROUP BY profissional_id`) e juntadas via `LEFT JOIN` — uma passada só pela tabela de avaliações para TODOS os profissionais do raio, não uma consulta de média por pino (evita N+1, mesmo espírito da contagem por subcategoria da sessão anterior). O `ORDER BY` é montado a partir de uma lista fechada de cláusulas SQL prontas (`ORDENS_VALIDAS`), nunca por concatenação direta do que o usuário mandou — os placeholders parametrizados de sempre ($1-$7) continuam intactos.
- `profissionais.routes.ts`: novo query param `ordenar_por`, validado contra lista fechada (`ORDENACOES_VALIDAS`, 400 se valor inválido). `raio_km` não precisou de nenhuma mudança de validação (já aceitava de 0.1 até `RAIO_MAXIMO_KM`).

**Flutter**
- `profissional.dart`: `Profissional` ganha `mediaCustoBeneficio`/`mediaGeral` (nullable — `null` quando ainda não há avaliação, nunca `0`).
- `profissionais_service.dart`/`profissionais_provider.dart`: `buscarProximos` aceita `ordenarPor`, repassado até a query string.
- `mapa_screen.dart`: dois grupos de `ChoiceChip` logo abaixo da barra de busca — raio (1/2/3/4/5 km, ícone de régua) e ordenação (Mais próximos / Melhor custo-benefício / Melhores avaliados, ícone de ordenar). Reativo: mudar qualquer um dos dois rebusca na hora (mesmo padrão de `_aoMudarSubcategoria`, sem botão "aplicar"). Estilo herdado do `ChipTheme` global já configurado no redesign — sem overrides locais, mantendo a identidade visual.

### Verificação feita
- `cd backend && npx tsc --noEmit` — sem erros.
- Balanceamento de chaves/parênteses/colchetes (script Python) nos 4 arquivos Dart tocados — OK.
- **Corrupção de mount de novo** (mesmo bug recorrente): os 6 arquivos (2 backend + 4 Flutter) vieram truncados no mount depois das edições — todos reescritos por inteiro via heredoc a partir do conteúdo autoritativo, reconferidos (`wc -l`/`file` batendo com o esperado) antes de compilar/commitar.
- `git diff --stat` conferido antes do commit — só os 6 arquivos esperados, tamanhos batendo com a mudança pretendida.
- Commit `dc60fa5` (6 arquivos, 201 inserções/5 remoções).
- **Não foi possível testar contra o banco real** (sandbox sem acesso de rede à Neon) — a lógica do `LEFT JOIN`/`GROUP BY`/`ORDER BY` dinâmico foi revisada manualmente linha a linha, mas o comportamento e a performance reais só podem ser confirmados rodando no Neon com dados de verdade.

### Pendências para a próxima sessão
1. Testar de verdade no Flutter: trocar o raio e a ordenação no mapa, conferir que a lista de pinos muda na hora e que "Melhor custo-benefício"/"Melhores avaliados" ordenam como esperado (e que profissionais sem avaliação nenhuma aparecem por último, não em primeiro por causa de `NULL`).
2. Se "Pontualidade" for de fato um critério que o usuário quer ver refletido nas avaliações (não só um rótulo alternativo para "comportamental"), é uma migração nova: nova coluna `estrelas_pontualidade` em `avaliacoes_profissional`, mais os ajustes correspondentes na tela de avaliação e nos resumos exibidos no perfil.
3. Itens antigos ainda pendentes: rodar migrações `07`-`10` no Neon; Dockerfile do backend + armazenamento S3-compatible antes de deploy real; investigar build "Windows (desktop)" (`Visual Studio toolchain`); confirmar fix do cropper.js no Web.

---

## Sessão de 13/07/2026 (continuação — refatorar barra de filtros: raio vira sub-filtro condicional)

### Pedido
Simplificar a barra de filtros do mapa: a linha fixa de raio (1-5km) sai da barra principal, que passa a ter só os 3 botões de ordenação ("Mais próximos", "Melhor custo-benefício", "Melhores avaliados"). Uma linha de raio secundária deve aparecer só quando "Mais próximos" está selecionado, com faixas novas ("Até 2km", "Até 5km", "Até 8km", "Até 15km", "Mais que 15km"), escondendo-se automaticamente nos outros dois filtros, com transição animada (fade/slide) e estado mantido de forma intuitiva ao trocar entre eles.

### O que foi feito
`app/lib/screens/mapa_screen.dart`:
- Removida a lista fixa `_raiosDisponiveisKm` (1/2/3/4/5) e a linha de chips que sempre ficava visível.
- Barra principal agora só tem os 3 `ChoiceChip` de `_OrdenacaoBusca` (já existia da sessão anterior).
- Novo enum `_OpcaoRaio`: 5 faixas com rótulo + valor km real mandado pro backend (`ate2km`=2, `ate5km`=5, `ate8km`=8, `ate15km`=15, `maisDe15km`=50 -- essa última usa o teto que o backend já aceita hoje, `RAIO_MAXIMO_KM`, padrão 50 em `env.ts`; não existe "sem limite" de verdade no backend, então "Mais que 15km" na prática é "até o máximo que o servidor permite").
- Linha de raio envolvida num `AnimatedCrossFade` (220ms, `Curves.easeInOut`): `firstChild` é a linha de chips, `secondChild` é um `SizedBox` de altura zero. Alterna via `crossFadeState` conforme a ordenação selecionada é ou não `distancia` -- anima altura E opacidade nativamente, sem precisar de `AnimatedSize`/`AnimatedContainer` manual.
- `_raioSelecionado` (estado) nunca é resetado ao trocar de ordenação -- só a LINHA de chips fica visível/invisível. O raio escolhido continua sendo usado na busca mesmo com os outros dois filtros ativos (só o controle visual some, o filtro em si não); voltar para "Mais próximos" depois mostra o mesmo raio que estava selecionado antes.

### Verificação feita
- Balanceamento de chaves/parênteses/colchetes (script Python) -- OK.
- **Corrupção de mount de novo** (mesmo bug recorrente): arquivo veio truncado depois da edição -- reescrito por inteiro via heredoc a partir do conteúdo autoritativo, reconferido (`wc -l`/`file` batendo com o esperado) antes de commitar.
- `git diff --stat` conferido -- só `mapa_screen.dart`, 77 inserções/38 remoções, tamanho batendo com a refatoração pretendida.
- Commit `9e66dba`.
- Não foi possível rodar `flutter run` neste sandbox (sem SDK Flutter) -- a animação (`AnimatedCrossFade`) e o comportamento reativo (mostrar/esconder linha de raio, manter estado) foram revisados apenas por leitura de código, não executados.

### Pendências para a próxima sessão
1. Testar de verdade no Flutter: clicar em "Mais próximos" e ver a linha de raio aparecer com a transição suave; clicar em "Melhor custo-benefício"/"Melhores avaliados" e ver a linha sumir; voltar para "Mais próximos" e confirmar que o raio escolhido antes continua selecionado.
2. Itens antigos ainda pendentes: rodar migrações `07`-`10` no Neon; Dockerfile do backend + armazenamento S3-compatible antes de deploy real; investigar build "Windows (desktop)" (`Visual Studio toolchain`); confirmar fix do cropper.js no Web; considerar migração para critério real de "pontualidade" nas avaliações, se o usuário quiser isso de verdade (não só um rótulo).
