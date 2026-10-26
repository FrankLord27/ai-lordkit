---
name: backend-quality-gate
description: >
  Workflow obligatorio de 5 fases para diseñar, implementar y validar cada módulo
  backend (NestJS 11 + Prisma 7) antes de permitir trabajo frontend. Quality Gate
  por módulo/bounded context — cada módulo puede desbloquearse independientemente.
  ACTIVA ESTA SKILL siempre que el usuario diga "construir un sistema", "diseñar
  backend", "nuevo módulo", "validar backend", "quality gate", "escenarios de negocio",
  "primero el backend", "frontend unlocked", "auditar módulo", "build me a...",
  "necesito un sistema de...", o describa un producto nuevo (POS, ERP, logística,
  escuela, e-commerce, rental, etc.). NO usar para: scripts aislados, fixes de
  endpoints existentes, o tareas puramente de frontend.
---

# Backend Quality Gate

Proceso estricto de **5 fases** para diseñar, implementar y validar cada módulo
backend. Ningún módulo pasa al frontend sin evidencia de que cumple las reglas
de negocio. El gate se aplica **por módulo** — puedes desbloquear `auth` mientras
`inventory` aún está en Fase 2.

---

## Mapa de references

| Necesito saber... | Leer |
|---|---|
| Ejemplo completo de Scenario Matrix | `references/scenario-matrix-template.md` |
| Guía paso a paso para implementar un módulo NestJS | `references/implementacion-nestjs.md` |
| Checklist del Quality Gate por módulo | `references/quality-gate-checklist.md` |
| Template de Audit Matrix (12 dimensiones) | `references/audit-matrix-template.md` |
| Template de Traceability Matrix | `references/traceability-matrix-template.md` |
| Self-test de la skill (adversarial prompts) | `references/skill-self-test.md` |

---

## Inputs a recopilar

Antes de iniciar la Fase 1 de cualquier módulo, confirmar con el usuario:

1. **Nombre del módulo** — el bounded context (e.g., `auth`, `pos`, `trips`, `billing`)
2. **Contexto de negocio** — qué hace este módulo, para quién, por qué existe
3. **Alcance MVP** — qué funcionalidades son obligatorias para la primera versión
4. **Dependencias** — de qué otros módulos depende (e.g., `billing` depende de `auth`)
5. **Fuera de alcance** — qué NO se construye ahora

Si el usuario da una idea vaga ("hazme un sistema de camiones"), la Fase 1 se
ejecuta como entrevista estructurada antes de escribir código.

---

## Procedimiento: 5 fases por módulo

```
Fase 1         Fase 2              Fase 3              Fase 4         Fase 5
Descubrimiento → Contrato + Diseño → Implementación → Validación → Quality Gate
(matrix)         (schema, API)       (código)          (tests)       (auditoría)
                                                                       │
                                                                       ▼
                                                              FRONTEND UNLOCKED
                                                              (solo este módulo)
```

### Fase 1 — Descubrimiento

**Objetivo:** Mapear TODAS las reglas de negocio del módulo antes de tocar código.

**Entregable:** `docs/scenario-matrix-<módulo>.md`

**Acciones:**
1. Extraer actores, entidades, reglas de negocio, flujos
2. Definir happy paths como historias completas (no endpoints CRUD)
3. Para cada happy path, identificar 4-6 failure paths y edge cases
4. Documentar transiciones de estado de cada entidad con ciclo de vida
5. Llenar la authorization matrix (quién puede hacer qué)
6. Definir audit requirements (qué debe ser trazable)
7. Establecer requisitos no funcionales medibles

**Template:** ver `references/scenario-matrix-template.md`

Cada fila recibe un ID estable: `BSM-<MÓDULO>-<NÚMERO>` (e.g., `BSM-AUTH-001`).
Este ID se usa en tests, auditoría y veredicto. Si no está en la matrix, no se
construye.

> **No saltarse esta fase.** Es la razón #1 por la que los tests de backend se
> convierten en "el endpoint devuelve 200" sin historia de negocio.

### Fase 2 — Contrato + Diseño

**Objetivo:** Definir las interfaces y la estructura de datos sin implementar lógica.

**Entregable:** `docs/backend-contract-<módulo>.md` + schema Prisma actualizado

**Acciones:**
1. Diseñar el schema Prisma del módulo (con `@db.Decimal`, `tenantId`, `deletedAt`)
2. Definir endpoints (URL, método, payload, respuesta, errores)
3. Diseñar modelo de dominio (entidades, value objects, servicios de dominio)
4. Documentar qué servicio/use-case enforce cada regla de negocio
5. Definir eventos (síncronos y asíncronos con BullMQ)
6. Establecer boundaries de transacción (qué es atómico)
7. Definir estrategia de validación (input → business → output)

**Cross-references:**
- Schema Prisma → skill `prisma7-docs`
- Estructura de módulo NestJS → skill `nestjs-docs`
- Si el módulo toca dinero → skill `erp-saas-core` (Decimal, partida doble, etc.)

### Fase 3 — Implementación

**Objetivo:** Escribir el código del módulo siguiendo el contrato de la Fase 2.

**Entregable:** Código fuente del módulo en `src/modules/<módulo>/`

**Acciones** (en este orden):
1. Generar migración Prisma
2. Implementar entidades de dominio (sin dependencias de framework)
3. Definir interfaces de repository (puertos)
4. Implementar repositories con Prisma
5. Crear use cases / services de aplicación
6. Crear DTOs con Zod en `packages/shared-types`
7. Crear controllers (solo routing + validación, sin lógica)
8. Registrar en el module NestJS
9. Configurar estructura de tests

**Guía detallada con ejemplos de código:** ver `references/implementacion-nestjs.md`

**Reglas de implementación:**
- Lógica de negocio en `domain/` o `application/`, **nunca** en controllers
- Dinero siempre con `Decimal` de `decimal.js`, nunca `number`
- `tenantId` se obtiene del JWT, nunca del body — inyectado via Prisma Client Extensions
- Nunca retornar entidades de Prisma al cliente — siempre Mapper
- Operaciones multi-tabla siempre en `prisma.$transaction`

### Fase 4 — Validación

**Objetivo:** Demostrar con evidencia que el código cumple la Scenario Matrix.

**Entregable:** Tests pasando + evidencia en `docs/e2e-evidence/<módulo>/`

**Categorías de tests obligatorias:**

| Categoría | Qué prueba | Ejemplo |
|---|---|---|
| **Unit** | Reglas de negocio en aislamiento | `test/unit/trips/r1-total-calculation.spec.ts` |
| **Integración** | Service + DB real | `test/integration/trips/trip-repository.spec.ts` |
| **E2E escenario** | Historia completa: HTTP → DB → respuesta | `test/e2e/trips/bsm-trk-001.spec.ts` |
| **Failure** | Lo que debe fallar | `test/e2e/trips/bsm-trk-020.spec.ts` |
| **Edge case** | Boundaries (0, negativo, máximo) | `test/e2e/trips/bsm-trk-021.spec.ts` |
| **Autorización** | Rol A no puede hacer la acción de rol B | `test/integration/trips/auth-matrix.spec.ts` |
| **Idempotencia** | Replay no produce doble efecto | `test/e2e/trips/bsm-trk-022.spec.ts` |
| **Rollback** | Fallo parcial no deja estado inconsistente | `test/integration/trips/transaction-rollback.spec.ts` |
| **Invariantes** | Balances, conteos, completitud de audit | `test/integration/trips/invariants.spec.ts` |

**Regla:** Cada test debe referenciar un ID de la Scenario Matrix. Un test que no
traza a un BSM, R*, AU* o NF* es rechazado.

**Regla:** Tests E2E usan DB real (Testcontainers o esquema dedicado). Mockear
Prisma en tests E2E es BLOCK.

**Evidencia obligatoria por escenario:**
- Input payload
- Respuesta esperada vs real
- Estado de DB antes / después
- Side effects (eventos, audit rows, notificaciones)
- Timing

### Fase 5 — Quality Gate

**Objetivo:** Emitir veredicto formal de si el módulo está listo para ser consumido.

**Entregable:** Actualización de `docs/module-gates.md` + `docs/quality-gate-<módulo>.md`

**Acciones:**
1. Producir la **Traceability Matrix** (BSM → código → test → resultado) — ver `references/traceability-matrix-template.md`
2. Producir la **Audit Matrix** (12 dimensiones) — ver `references/audit-matrix-template.md`
3. Ejecutar el **Quality Gate Checklist** — ver `references/quality-gate-checklist.md`
4. Emitir veredicto: **FRONTEND DESBLOQUEADO** o **FRONTEND BLOQUEADO**
5. Actualizar `docs/module-gates.md`

**Si hay BLOCK:** retroceder a la fase correspondiente:
- BLOCK por contrato/diseño → volver a Fase 2
- BLOCK por implementación/bug → volver a Fase 3
- BLOCK por tests insuficientes → volver a Fase 4

---

## Gate por módulo

El Quality Gate **NO es global**. Cada bounded context tiene su propio ciclo.

### Tracking en `docs/module-gates.md`

```markdown
# Estado de Quality Gates

| Módulo | Fase actual | Estado | Última revisión | Notas |
|--------|-------------|--------|-----------------|-------|
| auth | Fase 5 | ✅ DESBLOQUEADO | 2026-08-10 | |
| pos | Fase 4 | 🔄 EN PROGRESO | 2026-08-15 | Tests de idempotencia pendientes |
| inventory | Fase 2 | ⏳ PENDIENTE | 2026-08-16 | Diseñando schema |
| billing | Fase 1 | ⏳ PENDIENTE | — | Esperando definición de reglas |
```

### Gate Global del MVP

Solo se declara **MVP FRONTEND UNLOCKED** cuando **todos** los módulos marcados
como MVP tienen estado `DESBLOQUEADO`. Módulos no-MVP pueden seguir en progreso.

---

## Integración con skills hermanas

| Necesidad | Skill | Cuándo consultar |
|---|---|---|
| Patrones NestJS (módulos, guards, pipes, interceptors) | `nestjs-docs` | Fase 2 y 3 |
| Prisma 7 (driver adapters, $extends, transacciones) | `prisma7-docs` | Fase 2 y 3 |
| Reglas financieras (Decimal, partida doble, tenantId) | `erp-saas-core` | Fase 1, 2, 3 y 5 |
| Estándares generales (lint, git, CI, API REST) | `fullstack` | Toda la vida del proyecto |

**Anti-patrón:** Duplicar reglas que ya están en otra skill. Si necesitas las reglas
de `erp-saas-core` para auditar un módulo financiero, referencia la skill — no copies
las reglas aquí.

---

## Manejo de fallos

| Situación | Acción |
|---|---|
| Contexto vago ("hazme un POS") | Fase 1 como entrevista estructurada, no como suposiciones |
| Test runner no configurado | STOP. Configurar antes de escribir tests |
| Un escenario no se puede testear con la arquitectura actual | BLOCK en Fase 2 — rediseñar, no saltar |
| Hardening rompe un test | Revertir el cambio, marcar como regresión |
| El usuario pide saltar una fase | Rechazar. Explicar consecuencia. Si insiste: registrar OVERRIDE con riesgos aceptados |
| No hay tiempo para todas las fases | Cortar alcance de frontend, nunca cortar fases de backend |
| Módulo "solo CRUD" que no necesita gate | Evaluar si realmente no tiene reglas ocultas. Si es puro CRUD sin negocio, gate ligero |
| Se agrega feature a módulo ya desbloqueado | Nuevo BSM → nueva fila en matrix → re-correr gate del módulo |

---

## Ejemplos

**Módulo `auth`** — Fase 1 produce: login/registro, JWT refresh, roles (cashier, manager, owner, auditor),
authorization matrix completa, edge cases (token expirado, credenciales inválidas, rate limiting, session concurrente).

**Módulo `pos`** — Fase 1 produce: venta completa con items → totales → impuestos → descuento →
pago → inventario → recibo → auditoría → cuadre de caja. Más failure paths: pago rechazado,
stock insuficiente, venta concurrente de última unidad.

**Módulo `trips`** — Fase 1 produce: solicitud de viaje → asignación de chofer → inicio → fin →
cobro (MT³ × km × tarifa) → pago → cierre. Edge: sobrecapacidad, chofer inactivo, camión ocupado.

Para ejemplos detallados con tablas completas, ver `references/scenario-matrix-template.md`.

---

## Anti-patrones que esta skill rechaza

- ❌ **"POST /users funciona"** — no es un escenario de negocio, es un smoke test
- ❌ **"Cobertura CRUD 100%"** — cobertura de rutas, no de negocio
- ❌ **"Unit tests del service layer"** — sin integración con DB real, el test es teatro
- ❌ **"Tests pasan, ship it"** — sin Traceability Matrix ni Audit Matrix no hay evidencia
- ❌ **Validación monolítica** — auditar "todo el backend" de golpe en vez de módulo por módulo
- ❌ **Salto de fases** — código sin matrix, tests sin contrato, gate sin auditoría
- ❌ **Gate global prematuro** — decir "frontend unlocked" sin validar cada módulo individual
- ❌ **Duplicar reglas de skills hermanas** — copiar reglas de Prisma, NestJS o ERP aquí
- ❌ **Mockear DB en tests E2E** — los tests de negocio requieren persistencia real

---

## Self-test

Para verificar que esta skill realmente enforce el gate, ver
`references/skill-self-test.md` con 10 prompts adversariales que el agente
debe rechazar correctamente.
