# 03 — Partida Doble + Libro Mayor Inmutable

## La ecuación fundamental

$$\text{Activos} = \text{Pasivos} + \text{Patrimonio}$$

Equivalente operativo: **la suma algebraica de todos los movimientos de un asiento debe ser exactamente cero.**

```
Débitos − Créditos = 0
```

Si alguna vez no es cero (ni siquiera por un centavo), el asiento se rechaza. Sin excepciones.

---

## Modelo conceptual: teoría de grafos

- **Nodos = Cuentas** (Caja, Ventas, ITBIS por Pagar, Inventario, etc.)
- **Aristas = Líneas de asiento** (movimientos de valor entre cuentas)
- **Saldo de una cuenta** = suma de aristas entrantes − suma de aristas salientes

No guardamos el saldo. Lo derivamos. Punto.

---

## Schema Prisma del libro mayor

```prisma
enum AccountType {
  ASSET
  LIABILITY
  EQUITY
  INCOME
  EXPENSE
}

model Account {
  id          String       @id @default(uuid())
  tenantId    String
  code        String       // Ej: "1101" Caja General
  name        String
  type        AccountType
  parentId    String?
  parent      Account?     @relation("AccountHierarchy", fields: [parentId], references: [id])
  children    Account[]    @relation("AccountHierarchy")
  isLeaf      Boolean      @default(true)  // solo las hojas reciben movimientos
  currency    String       @default("DOP")
  deletedAt   DateTime?
  createdAt   DateTime     @default(now())

  lines       JournalLine[]

  @@unique([tenantId, code])
  @@index([tenantId, type])
}

model JournalEntry {
  id              String        @id @default(uuid())
  tenantId        String
  entryNumber     String        // secuencia por tenant
  entryDate       DateTime      // fecha contable, no de creación
  description     String
  reference       String?       // ej: número de factura, ID de venta
  sourceModule    String        // "POS", "PURCHASES", "MANUAL", etc.
  sourceEntityId  String?
  idempotencyKey  String        @unique
  postedAt        DateTime      @default(now())
  postedById      String
  reversedById    String?       // si es un asiento de reversión
  reversedBy      JournalEntry? @relation("Reversal", fields: [reversedById], references: [id])
  reversedEntries JournalEntry[] @relation("Reversal")

  lines           JournalLine[]

  @@unique([tenantId, entryNumber])
  @@index([tenantId, entryDate])
  @@index([tenantId, sourceModule, sourceEntityId])
}

model JournalLine {
  id            String       @id @default(uuid())
  tenantId      String
  entryId       String
  entry         JournalEntry @relation(fields: [entryId], references: [id])
  accountId     String
  account       Account      @relation(fields: [accountId], references: [id])
  amount        Decimal      @db.Decimal(18, 2)  // POSITIVO o NEGATIVO, con signo
  currency      String       @default("DOP")
  description   String?
  lineOrder     Int

  @@index([tenantId, accountId])
  @@index([tenantId, entryId])
}
```

### Decisión clave: amounts con signo, no columnas separadas

Una sola columna `amount` con signo (positivo = débito, negativo = crédito) en lugar de `debit` / `credit` separados:

- Simplifica la validación: `SUM(amount) == 0`.
- Evita lógica condicional.
- Permite agregaciones rápidas: `SUM(amount) GROUP BY accountId` = saldo.

---

## Trigger PostgreSQL: inmutabilidad real

La ORM puede ser vulnerada. El último guardián es la DB.

```sql
-- migrations/sql/journal_immutability.sql

CREATE OR REPLACE FUNCTION reject_journal_entry_mutation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'Journal entries are immutable. Create a reversal entry instead.'
    USING ERRCODE = '23000', HINT = 'Use a compensating JournalEntry to correct mistakes.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_journal_entry_update
  BEFORE UPDATE ON "JournalEntry"
  FOR EACH ROW
  WHEN (OLD."reversedById" IS NULL AND NEW."reversedById" IS NULL)
  EXECUTE FUNCTION reject_journal_entry_mutation();

CREATE TRIGGER prevent_journal_entry_delete
  BEFORE DELETE ON "JournalEntry"
  FOR EACH ROW
  EXECUTE FUNCTION reject_journal_entry_mutation();

CREATE TRIGGER prevent_journal_line_update
  BEFORE UPDATE ON "JournalLine"
  FOR EACH ROW EXECUTE FUNCTION reject_journal_entry_mutation();

CREATE TRIGGER prevent_journal_line_delete
  BEFORE DELETE ON "JournalLine"
  FOR EACH ROW EXECUTE FUNCTION reject_journal_entry_mutation();
```

> **Nota:** la regla del `WHEN` en update permite UNA mutación controlada: marcar el campo `reversedById` cuando se vincula la reversión. Todo lo demás explota.

---

## Domain Service: validador de partida doble

```typescript
// domain/services/double-entry-validator.service.ts
import Decimal from "decimal.js";
import { JournalLine } from "../entities/journal-line.entity";
import { BalanceViolationError } from "../errors/balance-violation.error";

export class DoubleEntryValidator {
  static assertBalanced(lines: JournalLine[]): void {
    if (lines.length < 2) {
      throw new BalanceViolationError(
        "Journal entry must have at least 2 lines",
      );
    }

    const total = lines.reduce(
      (sum, line) => sum.plus(line.amount.toDecimal()),
      new Decimal(0),
    );

    if (!total.isZero()) {
      throw new BalanceViolationError(
        `Journal entry unbalanced: sum = ${total.toFixed(2)} (must be 0)`,
      );
    }

    // Validar que todas las líneas comparten moneda
    const currencies = new Set(lines.map((l) => l.amount.currency));
    if (currencies.size > 1) {
      throw new BalanceViolationError(
        `Mixed currencies in single entry: ${[...currencies].join(", ")}`,
      );
    }
  }
}
```

---

## Asientos típicos en un POS / ERP

### Venta al contado con ITBIS

| Cuenta                   | Débito | Crédito |
| ------------------------ | ------ | ------- |
| 1101 Caja                | 1,180  |         |
| 4101 Ingresos por ventas |        | 1,000   |
| 2101 ITBIS por pagar     |        | 180     |

Vector con signo: `[+1180, -1000, -180]`. Suma = 0. ✓

### Venta a crédito

| Cuenta                   | Débito | Crédito |
| ------------------------ | ------ | ------- |
| 1201 CxC Clientes        | 1,180  |         |
| 4101 Ingresos por ventas |        | 1,000   |
| 2101 ITBIS por pagar     |        | 180     |

### Cobro de factura a crédito

| Cuenta            | Débito | Crédito |
| ----------------- | ------ | ------- |
| 1101 Caja         | 1,180  |         |
| 1201 CxC Clientes |        | 1,180   |

### Compra a crédito de mercancía con ITBIS

| Cuenta               | Débito | Crédito |
| -------------------- | ------ | ------- |
| 1301 Inventario      | 5,000  |         |
| 1102 ITBIS a favor   | 900    |         |
| 2102 CxP Proveedores |        | 5,900   |

### Costo de la mercancía vendida (COGS)

Se asienta junto con la venta:

| Cuenta               | Débito | Crédito |
| -------------------- | ------ | ------- |
| 5101 Costo de ventas | 700    |         |
| 1301 Inventario      |        | 700     |

---

## Reversión de asiento (la única forma de "corregir")

```typescript
// application/use-cases/reverse-journal-entry.use-case.ts
async execute(originalEntryId: string, reason: string) {
  const original = await this.journalRepo.findById(this.tenantId, originalEntryId);
  if (!original) throw new EntryNotFoundError(originalEntryId);
  if (original.isReversed) throw new AlreadyReversedError(originalEntryId);

  // Crear asiento espejo con signos invertidos
  const reversal = JournalEntry.create({
    tenantId: this.tenantId,
    entryDate: new Date(),
    description: `Reversión de ${original.entryNumber}: ${reason}`,
    sourceModule: original.sourceModule,
    sourceEntityId: original.sourceEntityId,
    reversedById: original.id,
    lines: original.lines.map((l) => ({
      accountId: l.accountId,
      amount: l.amount.multiply(-1),  // invertir signo
      description: `Reverso: ${l.description}`,
      lineOrder: l.lineOrder,
    })),
  });

  await this.journalRepo.save(reversal);

  // Marcar original como reversado (única mutación permitida por trigger)
  await this.journalRepo.markAsReversed(original.id, reversal.id);

  return reversal;
}
```

---

## Cálculo de saldos (sin tabla de saldos)

```sql
-- Saldo de una cuenta a una fecha
SELECT
  SUM("amount") AS balance
FROM "JournalLine" jl
JOIN "JournalEntry" je ON je.id = jl."entryId"
WHERE jl."tenantId" = $1
  AND jl."accountId" = $2
  AND je."entryDate" <= $3;

-- Balanza de comprobación
SELECT
  a.code,
  a.name,
  SUM(CASE WHEN jl.amount > 0 THEN jl.amount ELSE 0 END) AS debit_total,
  SUM(CASE WHEN jl.amount < 0 THEN -jl.amount ELSE 0 END) AS credit_total,
  SUM(jl.amount) AS balance
FROM "Account" a
LEFT JOIN "JournalLine" jl ON jl."accountId" = a.id
LEFT JOIN "JournalEntry" je ON je.id = jl."entryId"
WHERE a."tenantId" = $1
  AND je."entryDate" BETWEEN $2 AND $3
GROUP BY a.code, a.name
ORDER BY a.code;
```

Para tenants con millones de movimientos, materializá vistas mensuales:

```sql
CREATE MATERIALIZED VIEW account_monthly_balance AS
SELECT
  jl."tenantId",
  jl."accountId",
  DATE_TRUNC('month', je."entryDate") AS period,
  SUM(jl.amount) AS net_movement
FROM "JournalLine" jl
JOIN "JournalEntry" je ON je.id = jl."entryId"
GROUP BY jl."tenantId", jl."accountId", DATE_TRUNC('month', je."entryDate");

CREATE UNIQUE INDEX ON account_monthly_balance ("tenantId", "accountId", period);
```

Refrescar al cerrar el período: `REFRESH MATERIALIZED VIEW CONCURRENTLY account_monthly_balance;`

---

## Tests obligatorios

```typescript
describe("JournalEntry double-entry rules", () => {
  it("accepts a balanced entry", () => {
    const lines = [
      JournalLine.of("cash", Money.of("1180", "DOP")),
      JournalLine.of("sales", Money.of("-1000", "DOP")),
      JournalLine.of("itbis-payable", Money.of("-180", "DOP")),
    ];
    expect(() => DoubleEntryValidator.assertBalanced(lines)).not.toThrow();
  });

  it("rejects an unbalanced entry by 1 cent", () => {
    const lines = [
      JournalLine.of("cash", Money.of("1180", "DOP")),
      JournalLine.of("sales", Money.of("-1000", "DOP")),
      JournalLine.of("itbis-payable", Money.of("-179.99", "DOP")),
    ];
    expect(() => DoubleEntryValidator.assertBalanced(lines)).toThrow(
      BalanceViolationError,
    );
  });

  it("rejects single-line entries", () => {
    const lines = [JournalLine.of("cash", Money.of("100", "DOP"))];
    expect(() => DoubleEntryValidator.assertBalanced(lines)).toThrow();
  });

  it("rejects mixed currencies", () => {
    const lines = [
      JournalLine.of("cash-dop", Money.of("100", "DOP")),
      JournalLine.of("cash-usd", Money.of("-100", "USD")),
    ];
    expect(() => DoubleEntryValidator.assertBalanced(lines)).toThrow(
      /Mixed currencies/,
    );
  });
});

describe("Journal immutability (integration)", () => {
  it("PostgreSQL trigger blocks UPDATE on JournalEntry", async () => {
    const entry = await postValidEntry();
    await expect(
      prisma.$executeRaw`UPDATE "JournalEntry" SET description = 'hack' WHERE id = ${entry.id}`,
    ).rejects.toThrow(/Journal entries are immutable/);
  });

  it("PostgreSQL trigger blocks DELETE on JournalLine", async () => {
    const entry = await postValidEntry();
    await expect(
      prisma.$executeRaw`DELETE FROM "JournalLine" WHERE "entryId" = ${entry.id}`,
    ).rejects.toThrow();
  });
});
```

---

## Cierre de período

```typescript
// application/use-cases/close-fiscal-period.use-case.ts
async execute(period: { year: number; month: number }) {
  return this.prisma.$transaction(async (tx) => {
    // 1. Validar que no haya períodos posteriores ya cerrados
    // 2. Sumar todas las cuentas de Ingresos y Gastos
    // 3. Generar asiento de cierre: traspasa resultado a Patrimonio
    // 4. Marcar período como CLOSED en tabla FiscalPeriod
    // 5. Bloquear escrituras: los triggers PG verifican período abierto

    await this.assertNoLaterClosedPeriods(period);
    const profitOrLoss = await this.calculatePeriodResult(period);
    const closingEntry = JournalEntry.createClosingEntry(profitOrLoss, period);
    await this.journalRepo.save(closingEntry);
    await tx.fiscalPeriod.update({
      where: { tenantId_year_month: { tenantId: this.tenantId, ...period } },
      data: { status: 'CLOSED', closedAt: new Date() },
    });
  });
}
```

Trigger adicional para bloquear asientos en períodos cerrados:

```sql
CREATE OR REPLACE FUNCTION reject_entries_on_closed_periods()
RETURNS TRIGGER AS $$
DECLARE
  period_status TEXT;
BEGIN
  SELECT status INTO period_status
  FROM "FiscalPeriod"
  WHERE "tenantId" = NEW."tenantId"
    AND year = EXTRACT(YEAR FROM NEW."entryDate")
    AND month = EXTRACT(MONTH FROM NEW."entryDate");

  IF period_status = 'CLOSED' THEN
    RAISE EXCEPTION 'Cannot post entries to closed period';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_period_open
  BEFORE INSERT ON "JournalEntry"
  FOR EACH ROW EXECUTE FUNCTION reject_entries_on_closed_periods();
```
