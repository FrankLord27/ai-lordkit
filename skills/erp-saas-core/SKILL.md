---
name: erp-saas-core
description: >
  Reglas arquitecturales inmutables y patrones obligatorios para desarrollar sistemas
  ERP, SaaS multi-tenant y POS con contabilidad de partida doble usando NestJS 11,
  Prisma 7, PostgreSQL 16+, Next.js 16+, TanStack Query 5 y Zustand 5. Úsala SIEMPRE
  que el usuario trabaje en: módulos contables (libro mayor, asientos, cuentas por
  cobrar/pagar, tesorería, cierre fiscal), facturación electrónica DGII (NCF, e-CF,
  formatos 606/607/608), cálculos financieros con Decimal, idempotencia, transacciones
  atómicas, multi-tenancy estricto, offline-first en POS, colas con BullMQ/Redis,
  TDD para lógica financiera, o cuando mencione "ERP", "mini-ERP", "partida doble",
  "Clean Architecture", "DDD", "Bounded Context", "cierre de caja", "discrepancia",
  "ITBIS", "retención", "RNC", "NCF", "B01", "B02", "tenantId", "soft delete",
  "row-level lock", "Decimal.js", "BigInt centavos", o trabaje en un POS, ERP o SaaS
  multi-tenant. Esta skill DEBE consultarse antes de escribir cualquier
  código que toque dinero, inventario, facturas, pagos, cierres contables o reglas
  de aislamiento multi-tenant. Combínala con `memory-bank-context` para mantener
  el estado vivo del proyecto entre sesiones.
compatibility:
  stack:
    - NestJS 11+
    - Prisma 7+
    - PostgreSQL 16+
    - Redis (ioredis)
    - BullMQ
    - Next.js 16+ (App Router)
    - TanStack Query 5+
    - Zustand 5+
    - TypeScript strict
    - Decimal.js
    - SCSS Modules + BEM (no Tailwind)
    - Turborepo + pnpm
  pairs_with:
    - memory-bank-context (estado vivo del proyecto)
    - prisma7-docs (patrones Prisma 7)
    - nestjs-docs (patrones NestJS)
---

# ERP / SaaS Core — Reglas Inmutables de Dominio

Skill maestro para construir sistemas ERP, SaaS multi-tenant y POS con calidad de auditoría. Aplica reglas de Clean Architecture, contabilidad de partida doble, precisión financiera y tolerancia a fallos.

> **Cuándo usar:** Antes de escribir código que toque dinero, inventario, facturas, pagos, cierres o reglas multi-tenant.
> **Cuándo NO usar:** Para tareas puramente de UI sin lógica financiera, o para refactor de presentación.

---

## Mapa de Navegación

| Necesito trabajar en...                                     | Leer                                         |
| ----------------------------------------------------------- | -------------------------------------------- |
| Arquitectura limpia + capas + DDD                           | `references/01-clean-architecture.md`        |
| Multi-tenancy estricto + soft delete                        | `references/02-multi-tenant-rules.md`        |
| Partida doble + libro mayor inmutable                       | `references/03-double-entry-accounting.md`   |
| Precisión financiera (Decimal / BigInt / redondeo bancario) | `references/04-financial-precision.md`       |
| Idempotencia + concurrencia + transacciones                 | `references/05-idempotency-concurrency.md`   |
| Colas asíncronas (BullMQ + Redis)                           | `references/06-async-queues.md`              |
| Offline-first + sincronización                              | `references/07-offline-first.md`             |
| Facturación electrónica DGII (NCF, e-CF, 606/607/608)       | `references/08-dgii-electronic-invoicing.md` |
| TDD para lógica financiera (Vitest/Jest)                    | `references/09-tdd-financial.md`             |
| Diagramas mínimos antes de programar                        | `references/10-required-diagrams.md`         |
| Flujo de trabajo con IA (cómo pedirle código)               | `references/11-ai-workflow.md`               |

---

## 11 Reglas Inmutables (Cero Excepciones)

Estas reglas son inviolables. Si el usuario o la IA quiere romperlas, debe justificar técnicamente por escrito antes.

1. **`tenantId` en cada query.** Se obtiene del JWT, nunca del body. Inyectado vía Prisma Client Extensions, no a mano.
2. **Soft delete obligatorio.** `deletedAt: DateTime?`. Nada se borra físicamente sin un comando explícito del usuario.
3. **Dinero en `Decimal`, no `number`.** Prisma `Decimal @db.Decimal(precision, scale)` + `decimal.js` en dominio. `number` para dinero está prohibido y rechazado en code review.
4. **Redondeo bancario** (`ROUND_HALF_EVEN`) en todos los cálculos fiscales y financieros.
5. **Partida doble validada.** Suma vectorial de un asiento siempre igual a cero. Validación en dominio antes de persistir.
6. **Libro mayor inmutable.** Triggers PostgreSQL `BEFORE UPDATE/DELETE` que lanzan `RAISE EXCEPTION` sobre `JournalEntry` y `JournalLine`. Las correcciones se hacen con asientos compensatorios.
7. **Idempotencia obligatoria** en cualquier endpoint que muta estado financiero. UUID por intento + Redis cache + restricción `@unique` en DB.
8. **Transacciones atómicas con `prisma.$transaction`** en cualquier operación que toque más de una tabla relacionada.
9. **Cero `any`, cero `ts-ignore`, cero `as Tipo` inseguro.** Si el tipo no se infiere, se modela bien (Zod + class-validator).
10. **Tests primero (TDD)** en cualquier lógica de dominio financiero. El test define el contrato, la IA implementa.
11. **Clean Architecture estricta.** `Domain → Application → Infrastructure → Presentation`. Cero imports inversos. Validado con dependency-cruiser si el proyecto lo tiene configurado.

---

## Stack Canónico

| Capa            | Tecnología            | Versión mínima | Notas                                |
| --------------- | --------------------- | -------------- | ------------------------------------ |
| Backend         | NestJS                | 11+            | Decorators + DI estricta             |
| ORM             | Prisma                | 7+             | Client Extensions para multi-tenancy |
| BD              | PostgreSQL            | 16+            | Triggers, RLS opcional, JSONB        |
| Cache           | Redis (ioredis)       | —              | Idempotencia + cache                 |
| Colas           | BullMQ                | —              | Jobs asíncronos contables            |
| Frontend        | Next.js (App Router)  | 15+            | SSR + RSC                            |
| Estado servidor | TanStack Query        | 5+             | Offline-first                        |
| Estado cliente  | Zustand               | 5+             | Persist en localStorage para POS     |
| Formularios     | React Hook Form + Zod | 7+ / 4+        | Validación cruzada                   |
| Estilos         | SCSS Modules + BEM    | —              | Prohibido Tailwind                   |
| Dinero          | decimal.js            | 10+            | Frontend y backend                   |
| Monorepo        | Turborepo + pnpm      | —              | Workspaces                           |

---

## Estructura Canónica de Carpetas (Backend NestJS)

```
apps/api/src/
  modules/
    accounting/              ← Bounded Context: Contabilidad
      domain/
        entities/
          journal-entry.entity.ts
          journal-line.entity.ts
          account.entity.ts
        value-objects/
          money.vo.ts
          cash-denominations.vo.ts
        errors/
          balance-violation.error.ts
        repositories/        ← Interfaces, no implementaciones
          journal.repository.ts
        events/
          journal-entry.created.event.ts
      application/
        use-cases/
          post-journal-entry.use-case.ts
          close-period.use-case.ts
        services/
          double-entry-validator.service.ts
      infrastructure/
        prisma/
          journal.prisma-repository.ts
        queue/
          accounting.processor.ts
      presentation/
        controllers/
          journal.controller.ts
        dtos/
          create-journal-entry.dto.ts
    pos/
      domain/...
      application/...
      infrastructure/...
      presentation/...
    inventory/
    invoicing/
    cash-management/
    fiscal-dgii/             ← NCF, e-CF, formatos 606/607/608
  shared/
    kernel/
      money.vo.ts            ← Value Objects compartidos
    infrastructure/
      prisma/
        prisma.service.ts
        tenant.extension.ts  ← Inyección automática de tenantId
```

> **Regla:** ningún archivo en `domain/` puede importar de `infrastructure/`, `presentation/` o de NestJS/Prisma. El dominio es agnóstico de frameworks.

---

## Bounded Contexts Mínimos para un ERP

| Contexto          | Responsabilidad                                | Eventos que emite                               |
| ----------------- | ---------------------------------------------- | ----------------------------------------------- |
| `accounting`      | Libro mayor, asientos, cuentas                 | `JournalEntryPosted`, `PeriodClosed`            |
| `pos`             | Terminal de venta, carrito, cierre ciego       | `SaleCompleted`, `CashShiftClosed`              |
| `inventory`       | Stock, ajustes, traslados                      | `StockMoved`, `StockAdjusted`                   |
| `invoicing`       | Facturas, notas crédito/débito                 | `InvoiceIssued`, `InvoiceVoided`                |
| `cash-management` | Cajas, sesiones, denominaciones, discrepancias | `DiscrepancyDetected`, `CashShiftOpened`        |
| `purchasing`      | Órdenes de compra, recepción, proveedores      | `PurchaseReceived`, `SupplierInvoiceRegistered` |
| `customers`       | Clientes, CxC, créditos, abonos                | `PaymentApplied`, `CreditLimitExceeded`         |
| `fiscal-dgii`     | NCF, e-CF, formatos 606/607/608, retenciones   | `eCFAccepted`, `eCFRejected`                    |
| `treasury`        | Bancos, conciliación, caja chica               | `BankTransactionImported`                       |
| `auth`            | Usuarios, roles, tenants, RBAC                 | `UserAuthenticated`                             |

Los contextos se comunican vía eventos (BullMQ + Redis), no por imports directos. Esto preserva el aislamiento.

---

## Flujo Síncrono vs Asíncrono (Regla de Oro)

**Síncrono** (responde al usuario en milisegundos):

- Validación de stock + decremento atómico
- Emisión del ticket / número de comprobante
- Cobro inmediato (cash, tarjeta)
- Persistencia de la venta básica

**Asíncrono** (en background, vía BullMQ):

- Generación de asientos contables de partida doble
- Envío del e-CF a la DGII
- Notificaciones (email, push, Slack)
- Sincronización con sistemas externos
- Cálculos pesados de reportería

Ver `references/06-async-queues.md` para implementación completa.

---

## Antes de Programar: Diagramas Mínimos

Para CADA módulo nuevo, exigir antes de escribir código:

| Diagrama                   | Cuándo                                            | Herramienta sugerida              |
| -------------------------- | ------------------------------------------------- | --------------------------------- |
| **ERD (Entidad-Relación)** | Siempre, antes del `schema.prisma`                | dbdiagram.io, Mermaid `erDiagram` |
| **C4 Contenedores**        | Una vez por proyecto, actualizar al agregar infra | Mermaid `flowchart`, Structurizr  |
| **Diagrama de Secuencia**  | Solo para flujos críticos no obvios               | Mermaid `sequenceDiagram`         |
| **Diagrama de Estados**    | Solo si la entidad tiene ciclo de vida complejo   | Mermaid `stateDiagram-v2`         |
| **Diagrama de Actividad**  | Solo si la lógica condicional es densa            | Mermaid `flowchart`               |

**Diagramas que se omiten en el día a día:** Contexto C4 Nivel 1, Componentes C4 Nivel 3, Despliegue. Ver `references/10-required-diagrams.md` para detalles y plantillas Mermaid listas.

---

## Protocolo de Trabajo con IA

Cuando le pidas código a otra IA o agente, exige este flujo:

1. **Cargar contexto:** Leer este skill + `memory-bank-context` antes de proponer.
2. **Plan antes de código:** La IA propone un plan en pasos con archivos a tocar, NUNCA empieza a escribir.
3. **Aprobación explícita:** Vos confirmás el plan.
4. **Implementación fragmentada por capa:** Dominio → Application → Infrastructure → Presentation. Una capa a la vez.
5. **Tests primero** para reglas financieras (TDD).
6. **Validación contra reglas:** La IA verifica las 11 reglas inmutables antes de declarar la tarea completa.
7. **Actualización del Memory Bank:** Al cerrar la tarea, actualizar `activeContext.md` y `progress.md`.

Ver `references/11-ai-workflow.md` con prompts plantilla copiables.

---

## Checklist Pre-Commit (Code Review Mental)

Antes de mergear cualquier PR financiero:

- [ ] ¿Toda query incluye `tenantId`?
- [ ] ¿Soft delete respetado (`deletedAt: null`)?
- [ ] ¿Dinero en `Decimal`, no `number`?
- [ ] ¿Redondeo bancario aplicado donde corresponde?
- [ ] ¿Asientos contables validados (suma = 0)?
- [ ] ¿Operación multi-tabla envuelta en `prisma.$transaction`?
- [ ] ¿Endpoint mutador tiene `idempotencyKey`?
- [ ] ¿Tests cubren reglas de negocio críticas?
- [ ] ¿Cero `any`, cero `ts-ignore`?
- [ ] ¿Imports respetan Clean Architecture?
- [ ] ¿Eventos asíncronos emitidos vía BullMQ?
- [ ] ¿Memory Bank actualizado?

---

## Antipatrones que Esta Skill Rechaza

| Antipatrón                                             | Por qué                       | Reemplazo correcto                                   |
| ------------------------------------------------------ | ----------------------------- | ---------------------------------------------------- |
| `amount: number` para dinero                           | Pérdida de precisión IEEE 754 | `amount: Decimal`                                    |
| `Math.round(value * 100) / 100`                        | Sesgo aritmético, no bancario | `Decimal.set({ rounding: Decimal.ROUND_HALF_EVEN })` |
| `where: { id }` sin `tenantId`                         | Filtración cross-tenant       | Prisma Client Extension automática                   |
| `UPDATE journal_entry` directo                         | Rompe inmutabilidad contable  | Asiento compensatorio + asiento correcto             |
| `for (const item of items) await prisma.x.create(...)` | N+1, sin atomicidad           | `prisma.$transaction([...])` o `createMany`          |
| Cajero ve el monto esperado al cerrar                  | Permite cuadrar el robo       | Cierre ciego: cajero solo declara el conteo          |
| Total de venta calculado en frontend                   | Manipulable                   | Backend recalcula y compara                          |
| `idempotencyKey` opcional                              | Doble cobro garantizado       | Header obligatorio + `@unique` en DB                 |
| Importar Prisma en `domain/`                           | Acopla a infraestructura      | Interface en `domain/repositories/`                  |

---

## Cuándo Combinar con Otras Skills

| Tarea                                            | Skills a cargar                                         |
| ------------------------------------------------ | ------------------------------------------------------- |
| Nuevo módulo desde cero                          | `erp-saas-core` + `memory-bank-context` + `nestjs-docs` |
| Auditoría arquitectural                          | `erp-saas-core` + agent `code-reviewer`                 |
| Subida de archivos (PDFs facturas, comprobantes) | `erp-saas-core` + `minio-docs`                          |
| UI admin del módulo                              | `erp-saas-core` + `ui-ux-polish`                        |
| Construir un SaaS o marketplace concreto        | `erp-saas-core` + CLAUDE.md y `docs/ai/` del proyecto   |

---

## Archivos de Referencia (leer según necesidad)

- `references/01-clean-architecture.md` → Capas, DDD, Bounded Contexts, ejemplos
- `references/02-multi-tenant-rules.md` → Prisma Client Extensions, RLS, JWT
- `references/03-double-entry-accounting.md` → Partida doble, teoría de grafos, schema
- `references/04-financial-precision.md` → Decimal vs BigInt, redondeo bancario
- `references/05-idempotency-concurrency.md` → UUID, Redis, row-level locks
- `references/06-async-queues.md` → BullMQ, processors, retry strategy
- `references/07-offline-first.md` → TanStack Query, IndexedDB, NCF offline
- `references/08-dgii-electronic-invoicing.md` → e-CF, XML, modos contingencia
- `references/09-tdd-financial.md` → Vitest patterns, fórmulas test
- `references/10-required-diagrams.md` → Mermaid plantillas copy-paste
- `references/11-ai-workflow.md` → Prompts maestros para Cursor/Claude/Cline

---

## Documentación oficial (Context7)

Para la doc oficial y actualizada de NestJS, Prisma, PostgreSQL y Redis, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

