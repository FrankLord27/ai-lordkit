---
name: prisma7-docs
description: >
  Referencia completa y actualizada de Prisma 7 para aplicaciones NestJS. Usa esta skill
  siempre que trabajes con: configuración de Prisma 7, PrismaService con driver adapters
  (OBLIGATORIO en v7), schema models, migraciones, prisma.config.ts (OBLIGATORIO en v7),
  integración con NestJS, soft delete con $extends, audit logging, testing/mocking,
  seeding, performance/índices, JSON fields, full-text search, o cualquier combinación
  NestJS + Prisma. Trigger también para: prisma migrate, prisma generate, PrismaModule,
  @prisma/adapter-pg, schema.prisma. SIEMPRE usa esta skill — la mayoría de recursos
  online y datos de entrenamiento de IA están basados en Prisma v5/v6 y están DESACTUALIZADOS.
---

# Prisma 7 Skill — Referencia Completa

> **Versión actual: Prisma 7** (lanzado Nov 2025, última: 7.4.x)
> La mayoría de tutoriales, docs y datos de IA usan Prisma v5/v6 — están DESACTUALIZADOS.
> Esta skill contiene los patrones correctos de Prisma 7.

## Tabla de Navegación

### Setup y Configuración

| Necesito saber sobre...                | Leer               |
| -------------------------------------- | ------------------ |
| Setup completo desde cero              | `setup.md`         |
| prisma.config.ts (NUEVO y OBLIGATORIO) | `setup.md`         |
| Schema y migraciones                   | `prisma-schema.md` |
| PrismaService e integración NestJS     | `prisma-nestjs.md` |
| Monorepo (Turborepo)                   | `monorepo.md`      |

### CRUD y Queries

| Necesito saber sobre...             | Leer                  |
| ----------------------------------- | --------------------- |
| CRUD services y controllers         | `crud.md`             |
| Queries avanzadas (relaciones, raw) | `advanced-queries.md` |
| JSON fields y Full-Text Search      | `json-fulltext.md`    |

### Patrones Avanzados

| Necesito saber sobre...      | Leer               |
| ---------------------------- | ------------------ |
| **Soft delete con $extends** | `soft-delete.md`   |
| **Audit logging automático** | `audit-logging.md` |
| **Testing y mocking**        | `testing.md`       |
| **Seeding por ambiente**     | `seeding.md`       |
| **Performance e índices**    | `performance.md`   |

### Integración

| Necesito saber sobre...                  | Leer                           |
| ---------------------------------------- | ------------------------------ |
| **Integración óptima NestJS + Prisma 7** | `nestjs-prisma-integration.md` |

---

## Prisma 7 — Cambios Críticos vs v5/v6

Estos son los errores más comunes al usar conocimiento desactualizado:

### 1. prisma.config.ts ahora es OBLIGATORIO

Reemplaza datasource URL en schema.prisma. Debe estar en la raíz del proyecto.

```typescript
// prisma.config.ts (raíz del proyecto, junto a package.json)
import "dotenv/config";
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
    seed: "tsx prisma/seed.ts",
  },
  datasource: {
    url: env("DATABASE_URL"),
  },
});
```

### 2. Driver Adapter ahora es OBLIGATORIO

```typescript
// ✅ CORRECTO (Prisma 7)
import { PrismaClient } from "./generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";
import pg from "pg";

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });

// ❌ INCORRECTO (estilo v5/v6 — NO funciona en v7)
import { PrismaClient } from "@prisma/client";
const prisma = new PrismaClient();
```

### 3. generator block — output OBLIGATORIO, prisma-client-js DEPRECADO

```prisma
// ✅ CORRECTO (Prisma 7)
generator client {
  provider   = "prisma-client"
  output     = "../src/generated/prisma"
  engineType = "client"
}

// ❌ INCORRECTO (v5/v6 legacy)
generator client {
  provider = "prisma-client-js"
}
```

### 4. $use() ELIMINADO — usar $extends()

```typescript
// ❌ INCORRECTO (v5/v6)
prisma.$use(async (params, next) => { ... });

// ✅ CORRECTO (Prisma 7)
const extendedPrisma = prisma.$extends({
  query: {
    $allModels: {
      async findMany({ args, query }) { ... }
    }
  }
});
```

### 5. ESM obligatorio

- package.json debe tener `"type": "module"`
- Imports usan extensión `.js` incluso para archivos `.ts`

### 6. Otros cambios

- `prisma migrate dev` ya no auto-ejecuta `generate` ni `seed`
- datasource url en schema.prisma DEPRECADO
- MongoDB NO soportado en Prisma 7
- Mínimo: Node.js 20.19+, TypeScript 5.4+

---

## Orden de lectura recomendado

**Proyecto nuevo**: `setup.md` → `prisma-schema.md` → `prisma-nestjs.md` → `nestjs-prisma-integration.md`

**Patrones avanzados**: `soft-delete.md` → `audit-logging.md` → `performance.md`

**Testing**: `testing.md` → `seeding.md`

---

## Documentación oficial (Context7)

Para la doc oficial y actualizada de Prisma 7, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

