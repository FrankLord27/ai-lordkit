---
name: fullstack
description: >
  Estándar fullstack: Next.js 16 + Tailwind v4, NestJS 11, Prisma 7, PostgreSQL 16,
  Redis, Zod compartido, Turborepo + pnpm, y Expo cuando hay app móvil. Úsala SIEMPRE al arrancar un
  proyecto o al decidir arquitectura, estructura de carpetas, módulos NestJS, Server vs Client Components,
  TanStack Query, formularios con React Hook Form + Zod, estilos, diseño de APIs REST, auth, multi-tenant,
  testing, CI/CD, performance, calidad de código, roadmap/MVP, o la app móvil (Expo, React Native, offline,
  APK). También si el usuario dice "mi estándar", "el stack", "como lo hacemos" o "el fullstack".
---

# Fullstack — el estándar

Un solo estándar para todo proyecto. Las referencias se leen según lo que toques; no hace falta cargarlas todas.

**Proyecto existente que no sigue el estándar** (por ejemplo, estilos con Sass/BEM): se respeta su convención y no se migra sin pedirlo. Para Sass/BEM está `references/legacy-sass-bem.md`.

## Stack

| Tecnología            | Capa      | Rol                                                         |
| --------------------- | --------- | ----------------------------------------------------------- |
| Next.js 16 App Router | Web       | Routing, rendering, páginas                                 |
| Tailwind CSS v4       | Web       | Estilos con utilidades; tokens en `@theme`                  |
| TanStack Query v5     | Web/móvil | Estado del servidor: fetch, caché, revalidación             |
| React Hook Form + Zod | Web/móvil | Formularios con el mismo schema del backend                 |
| Zustand 5             | Web/móvil | Solo estado UI compartido (wizard, carrito) y cola offline  |
| NestJS 11             | Backend   | API modular                                                 |
| Prisma 7              | Backend   | Acceso tipado a PostgreSQL                                  |
| `nestjs-zod`          | Backend   | DTOs desde los schemas Zod + OpenAPI                        |
| JWT + Passport        | Backend   | Auth; refresh tokens opacos rotados en Redis                |
| Redis 7               | Backend   | Caché, refresh tokens, colas (BullMQ)                       |
| PostgreSQL 16         | Infra     | Fuente de verdad                                            |
| MinIO                 | Infra     | Archivos (S3-compatible)                                    |
| Expo SDK + Expo Router| Móvil     | Solo si el proyecto tiene app; `StyleSheet` + tokens        |
| Turborepo + pnpm      | Monorepo  | Apps y paquetes compartidos                                 |
| Docker Compose        | Infra dev | PostgreSQL + Redis + MinIO locales                          |

## Estructura del monorepo

```
apps/
  api/        NestJS + Prisma (schema, migraciones y seed viven aquí)
  web/        Next.js 16 + Tailwind v4
  mobile/     Expo + Expo Router (solo si hay app)
packages/
  shared-types/   Schemas Zod compartidos — compilan a dist/ (Metro no lee .ts crudo)
```

## Reglas que nunca se rompen

- TypeScript `strict: true`. Sin `any`, sin `@ts-ignore` sin justificación.
- Un schema Zod valida web, móvil y backend. Vive en `packages/shared-types`. Cero class-validator en código nuevo.
- Nunca devolver entidades de Prisma al cliente: `select` explícito o mapper.
- Redis es caché; PostgreSQL es la fuente de verdad.
- Secretos solo en variables de entorno, validadas con Zod al arrancar.
- Seguridad de backend según la skill `nestjs-security-hardening` (auth deny-by-default, Helmet, CORS estricto, rate limit, argon2id).
- Multi-tenant: `tenantId` en todo `where`; RLS como segunda capa (`references/multi-tenant.md`).
- Paginación siempre. URLs kebab-case en plural, versionadas desde el día 1 (`/api/v1/...`).
- Swagger en `/docs` (dev/staging): si un endpoint no aparece ahí, no está terminado.
- Tests antes del merge; el CI bloquea si fallan. Lint + Husky + lint-staged antes de cada commit.
- Dinero nunca en `number`: Decimal.js o centavos en BigInt.

## Flujo de datos

```
UI (evento)
  → TanStack Query (lecturas)  /  Zustand (estado UI o cola offline en móvil)
  → apiClient (fetch tipado, maneja 401 con refresh)
  → NestJS Controller (ZodValidationPipe)
  → Service (Redis → miss → Prisma → PostgreSQL → guarda en Redis con TTL)
  → TransformInterceptor ({ data })
  → TanStack Query (cachea, revalida) → render
```

## Fases de un proyecto

```
FASE 0  Fundación       Monorepo, Docker, base NestJS y Next.js
FASE 1  Auth            Autenticación completa antes de cualquier feature
FASE 2  Dominio core    La feature principal del producto
FASE 3  Features clave  Lo que hace útil el producto
FASE 4  Calidad         Tests, CI/CD, monitoreo, hardening
FASE 5  Escala          Solo con un problema medido que lo justifique
```

## Mapa de referencias

> Algunas referencias todavía muestran ejemplos con `class-validator`/`ValidationPipe` o `bcrypt`. Son patrones viejos: tradúcelos a Zod (`nestjs-zod`) y argon2id. En seguridad manda `nestjs-security-hardening`.

| Tema | Leer |
| --- | --- |
| Frontend web: carpetas, Server vs Client, TanStack Query, RHF, Tailwind | `references/stack-frontend.md` |
| Backend: módulos NestJS, services, repositories, Redis, JWT, main.ts | `references/stack-backend.md` |
| Monorepo: Turborepo, pnpm workspace, shared-types, Docker Compose, checklist día 1 | `references/stack-monorepo.md` |
| Errores unificados (TanStack + Next.js + NestJS) | `references/error-handling.md` |
| Prisma Studio, seeding, migraciones avanzadas, backups | `references/database-admin.md` |
| Multi-tenant: tenantId, RLS, subdominios | `references/multi-tenant.md` |
| Logs, Sentry, métricas, alertas | `references/observability.md` |
| Roadmap: fases, análisis y MVP, dependencias entre features | `references/roadmap-phases.md`, `roadmap-analysis.md`, `roadmap-dependencies.md` |
| Seguridad web, auth, base de datos, servidor | `references/security-web.md`, `security-auth.md`, `security-database.md`, `security-server.md` |
| Testing: Jest backend, RTL + MSW frontend, Playwright E2E | `references/testing-backend.md`, `testing-frontend.md`, `testing-e2e.md` |
| CI/CD: GitHub Actions, Docker, deploy a VPS, monitoreo post-deploy | `references/cicd-github-actions.md`, `cicd-docker.md`, `cicd-deployment.md`, `cicd-monitoring.md` |
| Performance: base de datos, caché, backend, frontend | `references/performance-database.md`, `performance-cache.md`, `performance-backend.md`, `performance-frontend.md` |
| APIs REST: URLs y verbos, contratos y paginación, Swagger, versionado | `references/api-endpoints.md`, `api-contracts.md`, `api-swagger.md`, `api-versioning.md` |
| Calidad: linting, Git, code review, clean code | `references/quality-linting.md`, `quality-git.md`, `quality-code-review.md`, `quality-clean-code.md` |
| Proyecto existente con Sass + CSS Modules + BEM | `references/legacy-sass-bem.md` |

## App móvil (solo si el proyecto la tiene)

**Un backend, dos clientes.** El API no sabe si le habla el navegador o el teléfono; cero lógica de negocio duplicada en el cliente. Para las APIs de Expo, usa el plugin oficial de Expo (`expo:expo-overview` enruta).

| Tema | Leer |
| --- | --- |
| Estructura, Expo Router, grupos, layouts, tabs | `references/mobile-estructura.md` |
| Zustand en móvil, SecureStore, hidratación | `references/mobile-estado.md` |
| Cola offline, idempotencia, backoff | `references/mobile-offline.md` |
| Permisos nativos | `references/mobile-permisos.md` |
| Metro en monorepo pnpm | `references/mobile-monorepo.md` |
| Assets, íconos, splash, versionado del APK, EAS | `references/mobile-distribucion.md` |

Reglas de móvil:

1. Jamás fabricar una sesión ni pantallas con datos de mentira: si falla, se muestra el error real.
2. Tokens en `expo-secure-store`, nunca en AsyncStorage.
3. La URL del API sale de `EXPO_PUBLIC_API_URL` o `Constants.expoConfig.hostUri`, nunca una IP escrita a mano.
4. Todo envío offline lleva `clientUuid` (idempotencia); el backend devuelve el registro original si ya lo recibió.
5. Un 4xx sale de la cola y se le muestra al usuario; solo 5xx y errores de red se reintentan con backoff.
6. La sincronización es automática al recuperar conexión, no depende de que el usuario pulse "enviar".
7. Dependencias nativas con `npx expo install` (alineadas al SDK), nunca `pnpm add` a ciegas.
8. Tailwind no cruza a móvil: `StyleSheet.create` con tokens compartidos. NativeWind solo si el proyecto lo pide.

## Documentación oficial (Context7)

Para la doc oficial y actualizada de cada tecnología del stack, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de usar APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.
