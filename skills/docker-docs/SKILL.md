---
name: docker-docs
description: >
  Referencia completa de Docker y Docker Compose para desarrollo y producción del
  stack fullstack. Úsala cuando trabajes con: Dockerfiles multi-stage para NestJS
  y Next.js, docker-compose.yml para entorno local (PostgreSQL, Redis, MinIO),
  redes y volúmenes, variables de entorno en contenedores, health checks, o cuando
  debas dockerizar un servicio nuevo. También activa para: CI/CD con Docker, build
  cache optimization, configuración de registries, o problemas de networking entre
  contenedores.
---

# Docker — Referencia Completa

## Documentación oficial (Context7)

Para la doc oficial y actualizada de Docker, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

## Dockerfile multi-stage (NestJS)

```dockerfile
# Build stage
FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build

# Production stage
FROM node:24-alpine AS production
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 3000
CMD ["node", "dist/main"]
```

## docker-compose.yml estándar (entorno local)

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: app_dev
    ports: ["5432:5432"]
    volumes: [postgres_data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev"]
      interval: 10s
      retries: 5

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    command: redis-server --appendonly yes

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports: ["9000:9000", "9001:9001"]
    volumes: [minio_data:/data]

volumes:
  postgres_data:
  minio_data:
```

## Reglas no negociables

- **Multi-stage builds** siempre para producción — nunca imagen con devDependencies
- **`.dockerignore`** obligatorio: `node_modules`, `.next`, `dist`, `.env*`
- **Health checks** para servicios con dependencias (postgres, redis)
- **`depends_on` con `condition: service_healthy`** para garantizar orden de inicio
- **Variables de entorno** via `env_file` o secrets — nunca hardcodeadas en Compose
