---
name: nestjs-docs
description: >
  Documentación completa de NestJS v11 para construir APIs backend robustas con
  TypeScript. Úsala cuando trabajes en cualquier aspecto de NestJS: estructura de
  módulos, controladores, providers, guards, interceptores, pipes, filtros de
  excepción, autenticación JWT/Passport, validación de DTOs, configuración
  de entorno, integración con Prisma 7, Swagger/OpenAPI, testing con Jest,
  caching con Redis, health checks, rate limiting, scheduling, queues con BullMQ,
  file uploads, API versioning, microservicios, WebSockets, CLI, y patrones avanzados.
  SIEMPRE usa esta skill antes de generar código NestJS para asegurar patrones
  correctos y actualizados.
---

# NestJS Skill — Referencia Completa v11

> ⚠️ **Regla del estándar del usuario (manda sobre estos docs):** la validación se hace con **Zod + `nestjs-zod`** (`createZodDto` + `ZodValidationPipe`), con schemas compartidos en `packages/shared-types`. Los ejemplos con class-validator de estas referencias se TRADUCEN a nestjs-zod al generar código nuevo — class-validator solo se tolera en código legado. Swagger sigue funcionando: nestjs-zod genera el OpenAPI desde los schemas Zod.

## Tabla de Navegación

### Core (empezar aquí)

| Necesito saber sobre...                        | Leer                                 |
| ---------------------------------------------- | ------------------------------------ |
| Módulos, Controllers, Services, DI, Middleware | `references/01-core-concepts.md`     |
| Request pipeline: guards, pipes, interceptors  | `references/02-request-pipeline.md`  |
| Validación DTOs, class-validator, Config/env   | `references/04-validation-config.md` |
| CLI, estructura de proyecto, comandos          | `references/08-cli-structure.md`     |

### Base de datos

| Necesito saber sobre...                     | Leer                             |
| ------------------------------------------- | -------------------------------- |
| **Prisma 7** con driver adapters y $extends | `references/18-prisma-recipe.md` |
| TypeORM, PostgreSQL general                 | `references/05-database.md`      |

### Seguridad y Auth

| Necesito saber sobre...               | Leer                             |
| ------------------------------------- | -------------------------------- |
| JWT + Passport + Guards + RBAC        | `references/03-auth-security.md` |
| CORS, Helmet, CSP, headers HTTP       | `references/16-security-web.md`  |
| **Rate limiting** (@nestjs/throttler) | `references/24-rate-limiting.md` |

### Producción

| Necesito saber sobre...                    | Leer                             |
| ------------------------------------------ | -------------------------------- |
| **Caching con Redis**                      | `references/21-caching-redis.md` |
| **Health checks** (@nestjs/terminus)       | `references/22-health-checks.md` |
| **Scheduling / Cron jobs**                 | `references/23-scheduling.md`    |
| **Queues con BullMQ** (jobs en background) | `references/27-queues-bullmq.md` |

### API Design

| Necesito saber sobre...                      | Leer                                                            |
| -------------------------------------------- | --------------------------------------------------------------- |
| Swagger / OpenAPI                            | `references/06-openapi.md` + `references/17-openapi-swagger.md` |
| **API Versioning** (URI, Header, Media Type) | `references/25-versioning.md`                                   |
| **File uploads** (Multer, S3, Sharp)         | `references/26-file-uploads.md`                                 |

### Testing

| Necesito saber sobre...      | Leer                                                    |
| ---------------------------- | ------------------------------------------------------- |
| Jest: unit, integration, E2E | `references/07-testing.md` + `references/20-testing.md` |

### Avanzado

| Necesito saber sobre...            | Leer                               |
| ---------------------------------- | ---------------------------------- |
| WebSockets, Microservicios, Events | `references/09-advanced.md`        |
| Técnicas misceláneas               | `references/19-techniques-misc.md` |

---

## Arquitectura NestJS en un vistazo

```
Request
  │
  ├─► Middleware         (logger, cors, tenant)
  ├─► Guards             (autenticación / autorización)
  ├─► Interceptors (pre) (logging, transform request)
  ├─► Pipes              (validación y transformación DTOs)
  ├─► Controller Handler (routing)
  ├─► Service            (lógica de negocio)
  ├─► Interceptors (post)(transform response, cache)
  └─► Exception Filters  (manejo de errores)
```

---

## Estructura de un Módulo (patrón estándar)

```
src/
└── modules/
    └── cars/
        ├── cars.module.ts
        ├── cars.controller.ts
        ├── cars.service.ts
        ├── cars.repository.ts      ← Acceso a DB
        ├── dto/
        │   ├── create-car.dto.ts
        │   └── update-car.dto.ts
        └── entities/
            └── car.entity.ts
```

---

## Reglas No Negociables

- **Cada módulo** declara sus `controllers` y `providers` — sin excepciones
- **Nunca** importar `PrismaService`/`ConfigService` entre módulos sin `exports`
- **Siempre** usar `ValidationPipe` global en `main.ts` con `whitelist: true`
- **Nunca** lógica de negocio en controllers — solo en services
- **Guards** para auth/autorización; **Pipes** para validación; **Interceptors** para respuesta
- Variables de entorno siempre via `ConfigService` — nunca `process.env` directo
- **Prisma 7**: usar driver adapters, importar desde ruta generada, `$extends()` en vez de `$use()`

---

## Bootstrap (main.ts)

```typescript
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";
import { ValidationPipe, VersioningType } from "@nestjs/common";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import helmet from "helmet";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.use(helmet());
  app.enableCors({ origin: process.env.FRONTEND_URL });

  // Versionado de API
  app.enableVersioning({
    type: VersioningType.URI,
    defaultVersion: "1",
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  app.setGlobalPrefix("api");

  const config = new DocumentBuilder()
    .setTitle("API")
    .setVersion("1.0")
    .addBearerAuth()
    .build();
  SwaggerModule.setup("docs", app, SwaggerModule.createDocument(app, config));

  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
```

---

## Orden de lectura recomendado

**Proyecto nuevo**: 01 → 04 → 18 (Prisma) → 03 → 06

**Preparar para producción**: 21 (Cache) → 22 (Health) → 24 (Rate Limit) → 23 (Cron)

**Features avanzadas**: 26 (Uploads) → 27 (Queues) → 25 (Versioning)

---

## Documentación oficial (Context7)

Para la doc oficial y actualizada de NestJS 11, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

