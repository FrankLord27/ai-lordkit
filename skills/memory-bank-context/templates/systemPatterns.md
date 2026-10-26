# System Patterns

> **Cómo usar esta plantilla:** documentar patrones arquitectónicos que se aplican
> en MÁS DE UN módulo. Crece con el tiempo. Ver `patterns-update.md` para criterios.

---

## Bounded Contexts

[Lista de contextos del proyecto. Comunicación entre contextos: solo vía eventos.]

- `accounting` — Libro mayor, asientos, cuentas, períodos.
- `pos` — Terminal de venta, sesiones de caja, cierre ciego.
- `inventory` — Stock, ajustes, traslados.
- `invoicing` — Facturas, notas crédito/débito.
- `fiscal-dgii` — e-CF, NCF, formatos 606/607/608.
- `auth` — Usuarios, roles, tenants.
- [agregar más...]

## Convenciones de Naming

- **Carpetas de módulo:** `modules/<context-name>/{domain,application,infrastructure,presentation}`
- **Use Cases:** `<Verb><Entity>UseCase` — ej. `PostJournalEntryUseCase`.
- **Eventos:** `<Entity><PastVerb>Event` — ej. `JournalEntryPostedEvent`.
- **Repositorios (interface):** `I<Entity>Repository`.
- **Repositorios (impl):** `<Entity><Tech>Repository` — ej. `JournalPrismaRepository`.
- **Errores de dominio:** `<Problem>Error` — ej. `BalanceViolationError`.
- **Value Objects:** sufijo `.vo.ts`.
- **Tests:** `*.spec.ts` junto al archivo. Integration en `test/integration/`.

## Patrones aplicados

### Repository Pattern (Domain interface + Infra impl)

**Problema:** El dominio no debe conocer Prisma/Postgres.
**Solución:** Interface en `domain/repositories/`, implementación en `infrastructure/prisma/`.
**Ejemplo:**

```typescript
// domain/repositories/journal.repository.ts
export interface IJournalRepository {
  findById(tenantId: string, id: string): Promise<JournalEntry | null>;
  save(entry: JournalEntry): Promise<void>;
}

// infrastructure/prisma/journal.prisma-repository.ts
@Injectable()
export class JournalPrismaRepository implements IJournalRepository { ... }
```

**Visto en:** todos los módulos.

### Outbox Pattern

**Problema:** Publicar eventos fuera del `prisma.$transaction` permite inconsistencias.
**Solución:** Persistir el evento en `OutboxEvent` dentro de la misma transacción. Worker separado lee y publica a BullMQ.
**Ejemplo:**

```typescript
await prisma.$transaction(async (tx) => {
  const sale = await tx.sale.create({ data });
  await tx.outboxEvent.create({
    data: { eventName: "SaleCompleted", payload: { saleId: sale.id } },
  });
});
```

**Visto en:** `pos`, `purchasing`, `invoicing`.

### Multi-Tenant via Prisma Client Extension

**Problema:** Olvidar `tenantId` en una query = filtración cross-tenant.
**Solución:** `tenantExtension` con `AsyncLocalStorage` inyecta `tenantId` automáticamente en todas las queries.
**Visto en:** global, via `shared/infrastructure/prisma/`.

### Idempotency Key + Redis + @unique

**Problema:** Doble clic / retry de red = doble cobro.
**Solución:** Frontend genera UUID, backend valida en Redis (3 estados: IN_PROGRESS, COMPLETED, ausente) + restricción `@unique([tenantId, idempotencyKey])` en DB como última barrera.
**Visto en:** `pos/CompleteSaleUseCase`, `accounting/PostJournalEntryUseCase`.

### Banker Rounding Global

**Problema:** Redondeo aritmético acumula sesgo positivo en agregados.
**Solución:** `Decimal.set({ rounding: Decimal.ROUND_HALF_EVEN })` global al boot.
**Visto en:** `shared/kernel/decimal.config.ts`.

### Triggers PG para inmutabilidad contable

**Problema:** ORM puede ser bypasseada; el libro mayor debe ser inalterable.
**Solución:** Triggers `BEFORE UPDATE/DELETE` en `JournalEntry` y `JournalLine` que lanzan `RAISE EXCEPTION`. La única "corrección" es asiento compensatorio.
**Visto en:** `migrations/sql/journal_immutability.sql`.

## Reglas de import (dependency-cruiser)

- `domain/` NO puede importar de `infrastructure/`, `presentation/`, NestJS, Prisma.
- `application/` solo importa `domain/`.
- `infrastructure/` implementa interfaces de `domain/`.
- Módulo A no importa de módulo B; usar eventos.

Configurado en `.dependency-cruiser.cjs` y validado en CI.

## Anti-patrones rechazados

| Anti-patrón                    | Por qué                       | Reemplazo               |
| ------------------------------ | ----------------------------- | ----------------------- |
| `amount: number` para dinero   | Pérdida de precisión IEEE 754 | `Decimal`               |
| `UPDATE journal_entry` directo | Rompe inmutabilidad           | Asiento compensatorio   |
| `findMany()` sin filtros       | Filtra cross-tenant           | Prisma Client Extension |
| Total calculado en frontend    | Manipulable                   | Backend recalcula       |
| Importar Prisma en domain      | Acopla a infraestructura      | Interface en domain     |

## Decisiones técnicas pendientes

- [ ] [Algo que aún no se ha decidido]
- [ ] [...]

## Historial de cambios de patrones

- **YYYY-MM-DD:** Agregado patrón [X].
- **YYYY-MM-DD:** Deprecado patrón [Y], reemplazado por [Z].

---

_Última actualización: [YYYY-MM-DD]_
