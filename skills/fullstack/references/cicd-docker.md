# Docker en Producción

---

## Dockerfile del API (NestJS) — multi-stage build

```dockerfile
# apps/api/Dockerfile

# ─── STAGE 1: Dependencias ────────────────────────────────────────
FROM node:24-alpine AS deps
WORKDIR /app

# Instalar pnpm
RUN corepack enable pnpm

# Copiar manifests del monorepo primero — aprovechar cache de Docker
# Si solo cambia el código fuente, esta capa no se reconstruye
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY apps/api/package.json ./apps/api/
COPY packages/shared-types/package.json ./packages/shared-types/
COPY packages/typescript-config/package.json ./packages/typescript-config/

# Instalar solo dependencias de producción
RUN pnpm install --frozen-lockfile --prod

# ─── STAGE 2: Build ───────────────────────────────────────────────
FROM node:24-alpine AS builder
WORKDIR /app

RUN corepack enable pnpm

COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY apps/api/package.json ./apps/api/
COPY packages/shared-types/package.json ./packages/shared-types/
COPY packages/typescript-config/package.json ./packages/typescript-config/

# Instalar todas las dependencias (incluye devDependencies para build)
RUN pnpm install --frozen-lockfile

# Copiar código fuente
COPY apps/api ./apps/api
COPY packages ./packages

# Generar Prisma client
RUN pnpm --filter api prisma generate

# Compilar TypeScript
RUN pnpm --filter api build

# ─── STAGE 3: Producción ──────────────────────────────────────────
FROM node:24-alpine AS production
WORKDIR /app

# Usuario sin privilegios — nunca correr como root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

# Solo copiar lo necesario para correr
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/apps/api/dist ./dist
COPY --from=builder --chown=appuser:appgroup /app/apps/api/prisma ./prisma
COPY --from=builder --chown=appuser:appgroup /app/node_modules/.prisma ./node_modules/.prisma

# Variables de entorno — solo las no sensibles
ENV NODE_ENV=production
ENV PORT=3001

# Health check interno del contenedor
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3001/api/v1/health || exit 1

EXPOSE 3001

CMD ["node", "dist/main.js"]
```

---

## Dockerfile del Web (Next.js) — multi-stage build

```dockerfile
# apps/web/Dockerfile

FROM node:24-alpine AS deps
WORKDIR /app
RUN corepack enable pnpm
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY apps/web/package.json ./apps/web/
COPY packages/shared-types/package.json ./packages/shared-types/
COPY packages/typescript-config/package.json ./packages/typescript-config/
RUN pnpm install --frozen-lockfile

# ─── Build ────────────────────────────────────────────────────────
FROM node:24-alpine AS builder
WORKDIR /app
RUN corepack enable pnpm

COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY apps/web/package.json ./apps/web/
COPY packages/shared-types/package.json ./packages/shared-types/
COPY packages/typescript-config/package.json ./packages/typescript-config/
RUN pnpm install --frozen-lockfile

COPY apps/web ./apps/web
COPY packages ./packages

# NEXT_PUBLIC_* se necesitan en BUILD TIME (se embeben en el bundle)
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL

RUN pnpm --filter web build

# ─── Producción ───────────────────────────────────────────────────
FROM node:24-alpine AS production
WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

ENV NODE_ENV=production
ENV PORT=3000

# Next.js standalone output — incluye solo lo necesario
COPY --from=builder --chown=appuser:appgroup /app/apps/web/.next/standalone ./
COPY --from=builder --chown=appuser:appgroup /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder --chown=appuser:appgroup /app/apps/web/public ./apps/web/public

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/health || exit 1

EXPOSE 3000

CMD ["node", "apps/web/server.js"]
```

```javascript
// apps/web/next.config.js — habilitar standalone output
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone", // ← Necesario para el Dockerfile de producción
};

module.exports = nextConfig;
```

---

## docker-compose de producción

```yaml
# /apps/production/docker-compose.yml
# Este archivo vive en el servidor, no en el repo
# Las imágenes se referencian por tag — nunca build en producción

version: "3.8"

services:
  api:
    image: ghcr.io/tu-usuario/tu-repo/api:${IMAGE_TAG}
    container_name: myapp-api
    restart: unless-stopped
    env_file: .env # Variables de entorno desde archivo en el servidor
    ports:
      - "127.0.0.1:3001:3001" # Solo localhost — Nginx hace el proxy externo
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3001/api/v1/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
    networks:
      - app-network
    # Límites de recursos
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M

  web:
    image: ghcr.io/tu-usuario/tu-repo/web:${IMAGE_TAG}
    container_name: myapp-web
    restart: unless-stopped
    environment:
      - NODE_ENV=production
      - NEXT_PUBLIC_API_URL=https://tudominio.com/api/v1
    ports:
      - "127.0.0.1:3000:3000"
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000"]
      interval: 30s
      timeout: 5s
      retries: 3
    networks:
      - app-network
    deploy:
      resources:
        limits:
          cpus: "1.0"
          memory: 512M

  postgres:
    image: postgres:16-alpine
    container_name: myapp-postgres
    restart: unless-stopped
    env_file: .env.db # Archivo separado solo para credenciales de DB
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:5432:5432" # Solo localhost — nunca exponer a internet
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  redis:
    image: redis:7-alpine
    container_name: myapp-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    ports:
      - "127.0.0.1:6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
```

---

## .dockerignore — optimizar el build context

```dockerignore
# apps/api/.dockerignore  y  apps/web/.dockerignore
node_modules
.next
dist
coverage
.env
.env.*
*.log
.git
.github
README.md
playwright-report
```

---

## Comandos de operación en el servidor

```bash
# Ver estado de todos los contenedores
docker-compose ps

# Ver logs en tiempo real
docker-compose logs -f api
docker-compose logs -f web --tail=100

# Actualizar a una imagen específica
IMAGE_TAG=abc1234 docker-compose up -d --no-deps api web

# Rollback al tag anterior
IMAGE_TAG=$(cat .prev-tag) docker-compose up -d --no-deps api web

# Ver uso de recursos
docker stats

# Limpiar imágenes antiguas — liberar espacio en disco
docker image prune -f
docker system prune -f --volumes  # ⚠️ Borra volúmenes no usados — cuidado

# Ejecutar comando dentro del contenedor
docker exec -it myapp-api sh

# Correr migration manualmente
docker run --rm \
  --env-file /apps/production/.env \
  ghcr.io/tu-usuario/tu-repo/api:latest \
  npx prisma migrate deploy
```

---

## Seguridad en imágenes Docker

```dockerfile
# ✅ Usar imagen Alpine — menor superficie de ataque
FROM node:24-alpine

# ✅ Usuario sin privilegios
RUN adduser -S appuser
USER appuser

# ✅ No copiar archivos sensibles
# El .dockerignore excluye .env, node_modules, etc.

# ❌ Nunca secrets como ARG o ENV en el Dockerfile
# ARG DB_PASSWORD   ← Visible en docker history
# ENV JWT_SECRET=secreto   ← Visible en la imagen

# ✅ Los secrets entran como variables de entorno en runtime
# docker run --env-file .env  o  env_file en docker-compose
```

```bash
# Auditar la imagen con Trivy — busca CVEs en dependencias del sistema
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image ghcr.io/tu-usuario/tu-repo/api:latest
```
