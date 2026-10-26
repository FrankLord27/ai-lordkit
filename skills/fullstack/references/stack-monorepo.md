# Monorepo + Infraestructura — Turborepo + pnpm + Docker

---

## Turborepo — por qué y cómo

Turborepo orquesta múltiples apps y paquetes en un solo repositorio. El beneficio principal es el paquete `shared-types`: los schemas Zod y tipos TypeScript se comparten entre `web` y `api`. Si cambias un schema, TypeScript falla en compilación en ambas apps — no en runtime.

### turbo.json

```json
{
  "$schema": "https://turbo.build/schema.json",
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": [".next/**", "!.next/cache/**", "dist/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "lint": { "outputs": [] },
    "typecheck": { "outputs": [] },
    "test": { "outputs": ["coverage/**"] }
  }
}
```

### pnpm-workspace.yaml

La configuración mínima declara los workspaces. **Siempre agregar las secciones de seguridad** para protección contra supply-chain attacks:

```yaml
packages:
  - "apps/*"
  - "packages/*"
  - "e2e" # si el proyecto tiene tests E2E

# ─── Seguridad contra supply-chain attacks ────────────────────────────────────

# Solo paquetes publicados hace más de 24 horas pueden instalarse.
# La mayoría de paquetes maliciosos son detectados y removidos en ~1 hora.
minimumReleaseAge: 1440

# Bloquea fuentes exóticas (git repos, URLs de tarballs) en dependencias
# transitivas. Solo dependencias directas pueden usarlas.
blockExoticSubdeps: true

# Falla si el nivel de confianza de un paquete decrece respecto a versiones
# anteriores (ej: antes tenía provenance, ahora no).
trustPolicy: no-downgrade

# Verifica la integridad del store antes de enlazar paquetes.
verifyStoreIntegrity: true

# Solo permite scripts de build a los paquetes que realmente los necesitan.
# CRÍTICO: bloquea que cualquier paquete no listado ejecute código arbitrario
# durante `pnpm install`. Agregar solo los que realmente usan postinstall.
onlyBuiltDependencies:
  - "@prisma/client"
  - prisma
  - esbuild
  - sharp # solo si se usa procesamiento de imágenes
  - bcrypt # solo si se usa directamente

# ─── Resolución de dependencias ───────────────────────────────────────────────

# Instala versiones mínimas compatibles de dependencias directas.
# Reduce la superficie de subdependencias no auditadas.
resolutionMode: lowest-direct

# ─── Lockfile ─────────────────────────────────────────────────────────────────

# Headless install cuando el lockfile ya satisface package.json.
# Más rápido y predecible en CI — sin resolución sorpresiva.
preferFrozenLockfile: true
```

**Notas importantes:**

- `onlyBuiltDependencies` es la defensa más crítica. Si agregas una nueva dependencia que necesita `postinstall` (ej: `canvas`, `node-gyp`, `better-sqlite3`), debes añadirla explícitamente a esta lista o `pnpm install` fallará.
- `minimumReleaseAge: 1440` puede bloquear instalaciones si urgentemente necesitas un hotfix recién publicado. En ese caso, usa `minimumReleaseAgeExclude` para eximir ese paquete temporalmente.
- `trustPolicy: no-downgrade` requiere pnpm v10.21.0+.

### package.json raíz

```json
{
  "name": "mi-proyecto",
  "private": true,
  "scripts": {
    "dev": "turbo run dev",
    "build": "turbo run build",
    "lint": "turbo run lint",
    "typecheck": "turbo run typecheck",
    "test": "turbo run test"
  },
  "devDependencies": {
    "turbo": "latest"
  },
  "engines": {
    "node": ">=20",
    "pnpm": ">=8"
  }
}
```

---

## Paquetes compartidos

### shared-types — el más importante

Contiene los schemas Zod y tipos TypeScript que usan tanto `web` como `api`.

```
packages/shared-types/
├── package.json
└── src/
    ├── index.ts              ← Re-exporta todo
    ├── schemas/              ← Schemas Zod por dominio
    │   ├── auth.schema.ts
    │   └── [dominio].schema.ts
    └── types/                ← Tipos puros TypeScript
        └── api.types.ts
```

```json
// packages/shared-types/package.json
{
  "name": "@mystack/shared-types",
  "version": "0.0.1",
  "private": true,
  "main": "./src/index.ts",
  "types": "./src/index.ts",
  "dependencies": { "zod": "^4.0.0" }
}
```

```typescript
// packages/shared-types/src/index.ts
export * from "./schemas/auth.schema";
export * from "./schemas/[dominio].schema";
export * from "./types/api.types";
```

```typescript
// packages/shared-types/src/types/api.types.ts
export interface ApiError {
  statusCode: number;
  message: string;
  error: string;
  timestamp: string;
  path: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  hasNextPage: boolean;
}
```

### typescript-config

```
packages/typescript-config/
├── package.json
├── base.json       ← Strict, opciones comunes
├── nextjs.json     ← Extiende base, agrega opciones de Next.js
└── nestjs.json     ← Extiende base, agrega emitDecoratorMetadata
```

```json
// base.json
{
  "compilerOptions": {
    "strict": true,
    "strictNullChecks": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  }
}
```

```json
// nextjs.json
{
  "extends": "./base.json",
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "module": "esnext",
    "moduleResolution": "bundler",
    "allowJs": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  }
}
```

```json
// nestjs.json
{
  "extends": "./base.json",
  "compilerOptions": {
    "target": "ES2021",
    "module": "commonjs",
    "moduleResolution": "node",
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "outDir": "./dist"
  }
}
```

### Cómo referenciar paquetes internos

```json
// apps/web/package.json
{
  "name": "@myproject/web",
  "dependencies": {
    "@mystack/shared-types": "workspace:*"
  },
  "devDependencies": {
    "@mystack/typescript-config": "workspace:*"
  }
}
```

```json
// apps/web/tsconfig.json
{
  "extends": "@mystack/typescript-config/nextjs.json",
  "compilerOptions": {
    "paths": { "@/*": ["./src/*"] }
  }
}
```

---

## Docker Compose — solo dev

Las apps (`web` y `api`) corren en local con hot reload. Solo PostgreSQL y Redis en Docker.

```yaml
# docker-compose.yml
version: "3.8"

services:
  postgres:
    image: postgres:16-alpine
    container_name: myproject-postgres
    environment:
      POSTGRES_USER: devuser
      POSTGRES_PASSWORD: devpassword
      POSTGRES_DB: myproject_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U devuser"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: myproject-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  redis_data:
```

Comandos:

```bash
docker-compose up -d      # Levantar en background
docker-compose down       # Parar
docker-compose down -v    # Parar y borrar volúmenes (reset DB)
```

---

## Variables de entorno

### .env.example — siempre commiteado con documentación

```env
# ─── API ──────────────────────────────────────────
# PostgreSQL connection string
DATABASE_URL=postgresql://devuser:devpassword@localhost:5432/myproject_db

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# JWT — mínimo 32 caracteres para el secret
JWT_SECRET=CAMBIA_ESTO_minimo_32_caracteres_aqui
JWT_EXPIRES_IN=15m
REFRESH_TOKEN_EXPIRES_IN=7d

# Server
PORT=3001
NODE_ENV=development
FRONTEND_URL=http://localhost:3000

# ─── WEB ──────────────────────────────────────────
NEXT_PUBLIC_API_URL=http://localhost:3001/api/v1
```

### .gitignore raíz

```gitignore
# Entorno
.env
.env.local
.env.*.local

# Dependencias
node_modules/

# Build outputs
dist/
.next/
build/

# Turborepo cache
.turbo/

# IDEs
.vscode/
.idea/

# Logs
*.log
npm-debug.log*
```

---

## Git y commits — Conventional Commits

Configurar desde el día 1 con `commitlint` + `husky`:

```bash
pnpm add -D @commitlint/cli @commitlint/config-conventional husky -w
npx husky init
echo "npx commitlint --edit \$1" > .husky/commit-msg
```

`commitlint.config.js`:

```javascript
module.exports = { extends: ["@commitlint/config-conventional"] };
```

### Formato de commits

```
tipo(scope): descripción corta en imperativo

feat(auth): add refresh token rotation
fix(items): correct price calculation for discounted items
refactor(booking): extract booking validation to separate service
chore(deps): update prisma to v5.8
docs(readme): add local setup instructions
test(items): add unit tests for search service
```

### Tipos permitidos

| Tipo       | Cuándo                           |
| ---------- | -------------------------------- |
| `feat`     | Nueva funcionalidad              |
| `fix`      | Corrección de bug                |
| `refactor` | Cambio de código sin fix ni feat |
| `chore`    | Cambios de build, deps, config   |
| `docs`     | Solo documentación               |
| `test`     | Agregar o corregir tests         |
| `perf`     | Mejora de performance            |

---

## Checklist de inicio — cualquier proyecto nuevo

### Día 1 — Setup

- [ ] `mkdir proyecto && cd proyecto && git init`
- [ ] `pnpm init -y && pnpm add -D turbo`
- [ ] Crear `turbo.json`, `pnpm-workspace.yaml` (con secciones de seguridad: `minimumReleaseAge`, `blockExoticSubdeps`, `trustPolicy`, `onlyBuiltDependencies`)
- [ ] Crear `packages/typescript-config` con `base.json`, `nextjs.json`, `nestjs.json`
- [ ] Crear `packages/shared-types` con estructura base
- [ ] `npx create-next-app@latest apps/web --typescript --app --src-dir --no-tailwind` (sin Tailwind v3 — instalar v4 manualmente)
- [ ] `pnpm add tailwindcss @tailwindcss/postcss postcss` en `apps/web`
- [ ] `npx @nestjs/cli new apps/api --strict --skip-git --package-manager pnpm`
- [ ] Actualizar `tsconfig.json` de ambas apps para extender configs compartidas
- [ ] Crear `docker-compose.yml`
- [ ] Copiar `.env.example` y crear `.env` local
- [ ] `docker-compose up -d`
- [ ] `pnpm install`

### Día 1 — NestJS base

- [ ] `main.ts` con Helmet, CORS, GlobalPrefix, ValidationPipe, ExceptionFilter, TransformInterceptor, Swagger
- [ ] `config/configuration.ts` con validación Zod de variables de entorno
- [ ] `prisma/prisma.service.ts` y `prisma/prisma.module.ts`
- [ ] `redis/redis.service.ts` y `redis/redis.module.ts`
- [ ] `npx prisma init` en `apps/api`
- [ ] Schema Prisma inicial con entidades del proyecto
- [ ] `npx prisma migrate dev --name init`

### Día 1 — Next.js base

- [ ] `lib/api-client.ts` con fetch wrapper tipado
- [ ] `lib/query-client.ts` con QueryClient configurado
- [ ] `app/layout.tsx` con QueryClientProvider
- [ ] `styles/globals.css` con `@import "tailwindcss"` y tokens en `@theme`
- [ ] `postcss.config.mjs` con `@tailwindcss/postcss`

### Día 1 — Git

- [ ] `.gitignore` con node_modules, .env, .next, dist, .turbo
- [ ] `commitlint` + `husky` configurados
- [ ] Primer commit: `chore: initial project setup`

---

## Fases de evolución del stack

```
FASE 1 — LANZAR              FASE 2 — CRECER            FASE 3 — ESCALAR
────────────────────────     ──────────────────────     ─────────────────────
Stack completo descrito      + Bull Queue                + GraphQL
aquí                         + S3 / Cloudinary           + Apollo Client
                             + Sentry                    + Microservicios
                             + GitHub Actions CI/CD      + Kubernetes
                             + Tests E2E Playwright
                             + Rate limiting avanzado
```

Nada de Fase 2 o Fase 3 entra al proyecto hasta que hay un problema medido que lo justifica.
