# Tech Context

> **Cómo usar esta plantilla:** declarar el stack VIGENTE. Actualizar cuando
> agregás/quitás dependencias o subís versiones mayores. Debe matchear
> `package.json`.

---

## Stack canónico

| Capa             | Tecnología                         | Versión mínima | Notas                               |
| ---------------- | ---------------------------------- | -------------- | ----------------------------------- |
| Lenguaje         | TypeScript                         | 5.4+           | strict: true                        |
| Runtime          | Node.js                            | 22 LTS         | usar `engines` en package.json      |
| Package manager  | pnpm                               | 9+             | workspaces                          |
| Monorepo         | Turborepo                          | 2+             | cache local + remoto                |
| Backend          | NestJS                             | 11+            | App Module + decorators             |
| ORM              | Prisma                             | 7+             | Client Extensions para multi-tenant |
| BD               | PostgreSQL                         | 16+            | Triggers, JSONB, opcional RLS       |
| Cache / Colas    | Redis (ioredis)                    | 7+             | persistencia AOF                    |
| Job queue        | BullMQ                             | 5+             | workers separados de la API         |
| Frontend         | Next.js                            | 15+            | App Router, RSC                     |
| UI Library       | React                              | 19+            | concurrent rendering                |
| Estado servidor  | TanStack Query                     | 5+             | offlineFirst networkMode            |
| Estado cliente   | Zustand                            | 5+             | persist en localStorage             |
| Formularios      | React Hook Form + Zod              | 7+ / 4+        | validación cruzada                  |
| Estilos          | SCSS Modules + BEM                 | —              | **prohibido Tailwind**              |
| Dinero           | decimal.js                         | 10+            | ROUND_HALF_EVEN global              |
| Object storage   | MinIO                              | latest         | compatible S3                       |
| Auth             | JWT + Passport                     | —              | RBAC con roles + permisos           |
| Tests            | Vitest                             | 1+             | jsdom para front                    |
| Property tests   | fast-check                         | 3+             | para precisión financiera           |
| Mutation testing | Stryker                            | —              | opcional, en CI nocturno            |
| Lint             | ESLint + Prettier                  | —              | + dependency-cruiser                |
| CI               | [GitHub Actions / GitLab CI / ...] | —              |                                     |

## Dependencias críticas (versiones fijas)

```json
{
  "decimal.js": "^10.4.3",
  "@prisma/client": "^7.0.0",
  "@nestjs/core": "^11.0.0",
  "next": "^15.0.0",
  "@tanstack/react-query": "^5.0.0",
  "zustand": "^5.0.0",
  "bullmq": "^5.0.0",
  "ioredis": "^5.0.0",
  "zod": "^4.0.0",
  "class-validator": "latest",
  "fast-check": "^3.0.0"
}
```

## Servicios externos

| Servicio   | Uso                      | Endpoint / Notas                        |
| ---------- | ------------------------ | --------------------------------------- |
| DGII e-CF  | Facturación electrónica  | TesteCF (sandbox), CerteCF (producción) |
| [Pasarela] | Pagos con tarjeta        | [URL / SDK]                             |
| MinIO      | XMLs, PDFs, comprobantes | self-hosted o S3 compatible             |
| SMTP       | Notificaciones           | [SES / Resend / ...]                    |

## Variables de entorno requeridas

```bash
# Database
DATABASE_URL=postgresql://user:pass@host:5432/dbname
SHADOW_DATABASE_URL=postgresql://user:pass@host:5432/shadow

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=...

# JWT
JWT_SECRET=...
JWT_EXPIRES_IN=15m
JWT_REFRESH_SECRET=...
JWT_REFRESH_EXPIRES_IN=7d

# MinIO
MINIO_ENDPOINT=...
MINIO_ACCESS_KEY=...
MINIO_SECRET_KEY=...
MINIO_BUCKET=...

# DGII
DGII_ENV=test|cert|prod
DGII_RNC_EMISOR=...
DGII_CERT_PATH=...
DGII_CERT_PASSWORD=...

# Tenant
DEFAULT_TENANT_ID=...  # solo para dev
```

## Comandos críticos

```bash
# Desarrollo
pnpm install
pnpm dev                            # arranca todos los apps en watch
pnpm dev --filter=api               # solo backend
pnpm dev --filter=web               # solo frontend

# Database
pnpm prisma generate
pnpm prisma migrate dev --name [nombre]
pnpm prisma migrate deploy          # CI / producción
pnpm prisma studio

# Tests
pnpm test                           # vitest
pnpm test:watch
pnpm test:coverage
pnpm test:integration               # con DB de test

# Lint / Arquitectura
pnpm lint
pnpm dep:check                      # dependency-cruiser
pnpm arch:score                     # architecture-guard

# Build / Deploy
pnpm build
pnpm start
```

## Versiones de runtime requeridas

```json
{
  "engines": {
    "node": ">=22.0.0",
    "pnpm": ">=9.0.0"
  }
}
```

## Dependencias deprecated / a remover

- [ ] [Si hay alguna lib en proceso de salida, listarla]

## Dependencias candidatas (evaluando)

- [ ] [Cosas que estamos considerando agregar]

## Notas de upgrade

- **YYYY-MM-DD:** [Si subiste algo importante, dejar nota — ej. "Subido a Prisma 7, breaking changes en X migrados."]

---

_Última actualización: [YYYY-MM-DD]_
