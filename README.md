# Serviços Manaus

API de serviços geolocalizados focada em Manaus/AM. Conecta clientes a profissionais próximos por meio de um mapa interativo, com um sistema de avaliação bilateral (cliente avalia profissional e vice-versa).

**Stack:** Node.js · TypeScript · Express · PostgreSQL + PostGIS (hospedado no Neon) · Flutter (mobile, em desenvolvimento).

> **Novo no projeto?** Veja **[`CONTRIBUTING.md`](./CONTRIBUTING.md)** para o guia completo de setup (backend + app Flutter) e **[`PROGRESSO.md`](./PROGRESSO.md)** para o histórico de sessões e pendências atuais.

---

## Antes de começar

Você precisa ter instalado na sua máquina:

- **Node.js 20+** — https://nodejs.org (baixe a versão LTS)
- **Git** — https://git-scm.com
- Um editor de código (recomendado: **VS Code**)

Para conferir se o Node está instalado, rode no terminal:

```bash
node -v
npm -v
```

Se aparecerem números de versão, está tudo certo.

> **Windows:** se ao rodar `npm` aparecer o erro *"a execução de scripts foi desabilitada neste sistema"*, rode uma única vez no PowerShell:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```
> e confirme com `S`. Isso libera o `npm` sem reduzir a segurança do sistema.

---

## Como rodar o projeto (passo a passo)

### 1. Clonar o repositório

```bash
git clone <URL_DO_REPOSITORIO>
cd projetos-servicos-manaus/backend
```

### 2. Instalar as dependências

```bash
npm install
```

Isso cria a pasta `node_modules` a partir do `package.json`. Ela é grande e **não** vai para o Git — cada dev recria a sua com este comando.

### 3. Configurar as variáveis de ambiente

O arquivo `.env` guarda a senha do banco e **nunca** é enviado ao Git. Você precisa criar o seu a partir do modelo:

```bash
# Linux / Mac
cp .env.example .env

# Windows (PowerShell)
copy .env.example .env
```

Depois, abra o `.env` e preencha o campo `DB_PASSWORD` com a senha do banco Neon.

> **Onde conseguir a senha:** ela não está no repositório (de propósito). Peça ao responsável pelo banco por um canal privado — nunca por chat de grupo, e-mail aberto ou dentro de um commit.

O `.env` final deve ter esta cara (com a senha real no lugar):

```
PORT=3333
NODE_ENV=development
DB_HOST=ep-old-fog-acwztrpz-pooler.sa-east-1.aws.neon.tech
DB_PORT=5432
DB_NAME=neondb
DB_USER=neondb_owner
DB_PASSWORD=coloque_a_senha_aqui
RAIO_MAXIMO_KM=50
```

### 4. Subir o servidor

```bash
npm run dev
```

Se tudo deu certo, você verá:

```
[db] Conectado em neondb@ep-old-fog-acwztrpz-pooler.sa-east-1.aws.neon.tech
[db] PostGIS: 3.6 ...
[http] Servidor ouvindo em http://localhost:3333
```

Deixe esse terminal aberto — é o servidor rodando. Para parar, aperte `Ctrl+C`.

> A primeira conexão pode demorar alguns segundos: o banco no Neon "dorme" quando não está em uso e precisa acordar.

---

## Testando a API

Com o servidor rodando, abra no navegador ou use `curl`:

**Verificar se o servidor está no ar:**
```
http://localhost:3333/health
```

**Buscar profissionais próximos** (exemplo: até 15 km do Teatro Amazonas):
```
http://localhost:3333/profissionais/proximos?latitude=-3.13013&longitude=-60.02340&raio_km=15
```

### Endpoint principal

`GET /profissionais/proximos`

| Parâmetro | Obrigatório | Padrão | Descrição |
|-----------|-------------|--------|-----------|
| `latitude` | sim | — | Latitude do ponto de busca (-90 a 90) |
| `longitude` | sim | — | Longitude do ponto de busca (-180 a 180) |
| `raio_km` | não | 5 | Raio de busca em km (máx. definido em `RAIO_MAXIMO_KM`) |
| `profissao` | não | — | Filtra por profissão/categoria (ex: `eletricista`) |
| `pagina` | não | 1 | Página dos resultados |
| `limite` | não | 20 | Itens por página (máx. 100) |

---

## Estrutura de pastas

```
projetos-servicos-manaus/
├── database/                        # Scripts SQL do banco
│   ├── 01_schema.sql                # Tabelas, índices, views, triggers
│   └── 02_seed_teste.sql            # Dados de exemplo (Manaus)
│
└── backend/                         # API Node + TypeScript
    ├── src/
    │   ├── server.ts                # Ponto de entrada
    │   ├── app.ts                   # Configuração do Express e middlewares
    │   ├── database.ts              # Pool de conexão com o Postgres/Neon
    │   ├── env.ts                   # Leitura e validação das variáveis de ambiente
    │   ├── routes/                  # Rotas HTTP
    │   ├── repositories/            # Acesso ao banco (queries SQL)
    │   └── utils/                   # Validação de entrada e helpers
    ├── .env.example                 # Modelo de configuração (sem senha)
    ├── package.json
    └── tsconfig.json
```

---

## Banco de dados

O banco roda no **Neon** (PostgreSQL na nuvem) com a extensão **PostGIS** para consultas geoespaciais.

Se precisar recriar o banco do zero (em um projeto Neon novo, por exemplo), rode no SQL Editor do Neon, nesta ordem:

1. Ative as extensões:
   ```sql
   CREATE EXTENSION IF NOT EXISTS postgis;
   CREATE EXTENSION IF NOT EXISTS pgcrypto;
   CREATE EXTENSION IF NOT EXISTS unaccent;
   ```
2. Rode o conteúdo de `database/01_schema.sql` (cria as tabelas).
3. Opcional: rode `database/02_seed_teste.sql` para inserir dados de exemplo.

---

## Regras importantes para a equipe

- **Nunca** faça commit do arquivo `.env`. Ele está no `.gitignore`, mas confira sempre com `git status` antes de commitar.
- **Nunca** compartilhe a senha do banco em canais públicos (chat de grupo, e-mail aberto, print de tela).
- A pasta `node_modules` não vai para o Git — quem clonar roda `npm install`.
- Antes de começar a trabalhar, rode `git pull` para pegar as alterações dos colegas.

---

## Scripts disponíveis

| Comando | O que faz |
|---------|-----------|
| `npm run dev` | Sobe o servidor em modo desenvolvimento (recarrega ao salvar) |
| `npm run build` | Compila o TypeScript para JavaScript (pasta `dist/`) |
| `npm start` | Roda a versão compilada (produção) |
| `npm run typecheck` | Verifica erros de tipo sem gerar arquivos |
