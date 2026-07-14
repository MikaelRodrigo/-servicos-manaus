# 1. Imagem base super leve e segura do Node.js 20 (Alpine Linux)
FROM node:20-alpine AS builder

# 2. Define o diretório de trabalho dentro do contêiner
WORKDIR /app

# 3. Copia apenas os arquivos de dependência primeiro (para usar o cache do Docker)
COPY package*.json ./

# 4. Instala as dependências (incluindo as de desenvolvimento para fazer o build)
RUN npm install

# 5. Copia todo o resto do código da API
COPY . .

# 6. Compila o TypeScript para JavaScript (gera a pasta dist/)
RUN npm run build

# --- ESTÁGIO DE PRODUÇÃO ---
FROM node:20-alpine AS runner
WORKDIR /app

# 7. Copia do estágio 'builder' apenas o package.json e a pasta dist/
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/dist ./dist

# 8. Instala APENAS as dependências de produção (ignora o TypeScript, eslint, etc.)
RUN npm install --only=production

# 9. Define a porta que o contêiner vai expor (a mesma do seu .env)
EXPOSE 3333

# 10. O comando que inicia a aplicação
CMD ["node", "dist/server.js"]