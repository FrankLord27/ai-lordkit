# Workflow de Desarrollo Asistido por IA — v3

Flujo obligatorio para tareas 🟡 Medio y 🔴 Alto (ver Fase 0). Las 🟢 Bajo pueden ir directo a Fase 3 + Quality Gate.

> **v3:** las skills de Expo/EAS vienen del plugin oficial de Expo (no del bundle); docs oficiales vía Context7; seguridad de backend con `nestjs-security-hardening`; se retiró el Anexo de Auth0 (el estándar es JWT + Passport propio).

---

## FASE 0: Triage de la tarea (NUEVA — no skip)

Antes de leer nada, clasifica la tarea. Esto decide qué skills cargar y si necesitas el team.

### Tipo de tarea
- [ ] **Solo backend** (NestJS, Prisma, Redis, MinIO, lógica de negocio)
- [ ] **Solo frontend web** (Next.js / React, Tailwind, TanStack Query, Zustand)
- [ ] **Solo mobile** (Expo / React Native)
- [ ] **Fullstack** (combinación de los anteriores)
- [ ] **Infra / DevOps** (Docker, EAS, deploys)
- [ ] **Calidad / Auditoría** (review, refactor, debug, migración)
- [ ] **Nuevo proyecto / scaffolding**

### Nivel de riesgo
- 🟢 **Bajo** — UI, copy, componentes sin estado
- 🟡 **Medio** — CRUD, formularios, integraciones
- 🔴 **Alto** — dinero, auth, multi-tenant, migraciones de schema, infraestructura, datos sensibles

> **Regla dura:** si tocas algo 🔴, el team mode es obligatorio (productor + verificador independientes).

---

## FASE 1: Carga de contexto (¡CRÍTICO!)

### 1.1 Estándar del proyecto
- Carga la skill `fullstack`. Si el proyecto ya usa otra convención (p. ej. Sass/BEM), respétala.
- Proyecto nuevo → `/new-project` **antes de seguir**.

### 1.2 Exploración del codebase (NUEVO)
Antes de planear, scout pass de 2-5 minutos:
- Estructura de carpetas top-level
- `package.json` / dependencias reales (no asumir)
- Archivos de config clave (`tsconfig`, `tailwind.config`, `prisma/schema.prisma`)
- Patrones ya en uso (cómo se hacen controllers, DTOs, queries, componentes)

> Sin esto, el plan sale de tu cabeza, no del código real.

### 1.3 Skills obligatorias según el área tocada

**Carga explícitamente** las skills que correspondan. No confíes en tu memoria base. Si la skill existe y aplica, se carga — no hay "ya me lo sé".

| Si tocas... | Carga (en este orden) |
|---|---|
| **NestJS / backend core** | `nestjs-docs` → `prisma7-docs` |
| **Auth, sesiones, seguridad de API** | `nestjs-docs` → `nestjs-security-hardening` |
| **Redis / caché** | `nestjs-docs` → `redis-docs` |
| **Storage / archivos (S3-compatible)** | `minio-docs` |
| **HTTP / contratos de API** | `http-query-docs` |
| **Next.js / Server Components** | `nextjs-docs` → `react-docs` → `typescript-docs` |
| **React puro / Vite** | `react-docs` → `typescript-docs` |
| **Estilos** | `tailwind-docs` (proyecto legado con Sass/BEM → `fullstack/references/legacy-sass-bem.md`) |
| **Estado cliente (server state)** | `tanstack-query-docs` |
| **Estado cliente (UI state)** | `zustand-docs` |
| **UI/UX polish / consistencia visual** | `ui-ux-polish` |
| **Expo / React Native / EAS** | `fullstack` (sección móvil) + plugin oficial de Expo (`expo:expo-overview` enruta al resto) |
| **Docker / contenedorización** | `docker-docs` |
| **API de una librería que no dominas** | MCP Context7 (`resolve-library-id` → `query-docs`) |
| **Proyecto fullstack** | `fullstack` |
| **ERP / SaaS / multi-tenant** | `erp-saas-core` |
| **Grafos / knowledge graph** | `graphify` |
| **Diseño de prompts** | `prompt-master` |
| **Crear / mantener skills** | `skill-creator` |
| **Memory Bank** | `memory-bank-context` |

### 1.4 Contexto de negocio
- Proyecto complejo (ERP, SaaS) → `erp-saas-core` + `memory-bank-context`
- Revisar `CLAUDE.md` / `AGENTS.md` locales si existen
- Si el repo usa Memory Bank, leer `activeContext.md` y `progress.md`

### 1.5 Mini-checkpoint (NUEVO)
Escribe internamente antes de pasar a Fase 2:
> "Stack: X. Skills cargadas: Y, Z. Riesgo: 🟢/🟡/🔴. Listo para planear."

Si hay skills aplicables que no cargaste, vuelve a 1.3.

---

## FASE 2: Planificación (Think before you code)

### 2.1 Matriz ask vs assume (NUEVO)

| Tipo de decisión | Acción |
|---|---|
| **Bloqueante** — cambia el resultado, no se revierte fácil | **Preguntar siempre**, con mi recomendación |
| **Decisión de diseño** — varias opciones válidas | **Preguntar con recomendación + 1 línea de "por qué"** |
| **Detalle de implementación** — una opción claramente mejor | **Asumir y avisar en el resumen final** |
| **Convención del repo** | **Seguir la convención, no preguntar** |

### 2.2 Plan en bullets
Antes de codear, escribe (visible al usuario):
- Archivos a tocar (con ruta)
- Endpoints / componentes / migraciones nuevas
- Skills / reglas especiales que aplicarán
- Riesgos detectados
- Si aplicarás AI-TDD (ver 3.3)

### 2.3 Criterio de delegación al team (NUEVO)

**Team mode obligatorio** si:
- Riesgo 🔴
- ≥ 2 capas (backend + frontend, mobile + backend, etc.)
- El usuario lo pidió explícitamente
- Ambigüedad alta en los requirements

**Hazlo tú** si:
- Riesgo 🟢 o 🟡
- Una sola capa
- Tarea pequeña y bien definida

### 2.4 Mini-checkpoint
Si el proyecto usa Memory Bank, actualiza con el plan.

---

## FASE 3: Ejecución y desarrollo

### 3.1 Modificaciones quirúrgicas
- Cambia solo lo necesario. **No** refactors masivos no pedidos.
- Si encuentras código legacy que *debería* refactorizarse, anótalo como follow-up — no lo toques ahora.

### 3.2 Reglas con override (NUEVO)
- Aplica las reglas de las skills cargadas.
- **Excepción:** si una regla del repo entra en conflicto con la práctica actual de la skill, **levanta el conflicto y pregunta** antes de aplicar.
- Prohibido: `any` en TypeScript, `console.log` olvidados, secretos hardcodeados.

### 3.3 AI-TDD (obligatorio en 🟡/🔴)
- Lógica crítica (dinero, multi-tenant, permisos, cálculos): **test que falle primero → implementar → test que pase**.
- Usa el runner que ya tenga el proyecto (Jest, Vitest). No instales uno nuevo sin pedirlo.

### 3.4 Mini-checkpoint
Después de cada cambio significativo (no por cada línea):
- ¿Compila / typecheck pasa?
- ¿El cambio sigue el plan?

---

## FASE 4: Quality Gate (BINARIO — pasa o no pasa)

Esto no es "revisar que esté bien". Es un gate con checks concretos.

### 4.1 Checks técnicos
- [ ] `tsc --noEmit` o equivalente pasa (cero `any` nuevo)
- [ ] Linter pasa (ESLint / Biome)
- [ ] Tests existentes pasan
- [ ] Tests nuevos pasan (si AI-TDD fue obligatorio)
- [ ] Build de producción pasa (si aplica)

### 4.2 Checks de seguridad y multi-tenant (NUEVO)
- [ ] Aislamiento multi-tenant preservado (`tenantId` en queries, middleware activo, sin fugas cross-tenant)
- [ ] Authz validado (no solo authn) — el usuario puede hacer lo que intenta hacer
- [ ] Inputs validados con Zod (`nestjs-zod`); class-validator solo en código legado
- [ ] Si tocaste backend 🔴: checklist de `nestjs-security-hardening` sin FALTA ni RIESGO
- [ ] No se exponen secretos en logs ni en respuestas de error

### 4.3 Checks de UI (si aplica)
- [ ] Consistencia con el design system (cargar `ui-ux-polish` si hay duda)
- [ ] Accesibilidad básica (labels, contraste, foco por teclado)
- [ ] No regresiones visuales en flujos tocados

### 4.4 Si el gate falla
- **No entregar.** Volver a Fase 3, fix, re-ejecutar gate.
- Si el problema es de diseño (no de código), volver a Fase 2.

### 4.5 Mini-checkpoint
Actualizar Memory Bank: `progress.md` con qué se hizo, `activeContext.md` con el estado actual.

---

## FASE 5: Cierre y entrega

### 5.1 Resumen al usuario
- Qué se hizo (1-3 bullets)
- Qué se asumió (si algo)
- Qué NO se hizo (out of scope)
- Cómo verificar (comando / endpoint / pantalla)
- Siguiente paso sugerido

### 5.2 Commit (si el usuario lo pide)
- Conventional Commits en español
- Pre-commit: tests + lint + typecheck
- Trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`

### 5.3 Actualizar Memory Bank
- `progress.md` → qué se entregó
- `activeContext.md` → estado actual del proyecto
- Si el proyecto no usa Memory Bank, no inventar.

---

## Reglas transversales (siempre activas)

1. **No inventar dependencias.** Si la skill dice que X lib está disponible, verificar en `package.json`.
2. **No saltarse skills.** "Ya me lo sé" no es razón para no cargar `prisma7-docs` si vas a tocar Prisma.
3. **No silent failures.** Si un test falla, si el linter se queja, si un endpoint da 500 → decirlo, no esconderlo.
4. **No exponer secretos.** Tokens, API keys, passwords: nada en logs, código, ni commits.
5. **Cuando dudes, escala.** Si no sabes si algo es bloqueante, pregúntale al usuario con tu recomendación.

---

> **Recordatorio para la IA:** El error #1 sigue siendo saltarse la Fase 1 (cargar skills). El error #2 es entregar sin pasar el Quality Gate de Fase 4. Las dos son fatales.
