# 09 — TDD para Lógica Financiera

> ⚠️ **Prisma 7:** los ejemplos con `new PrismaClient()` / `extends PrismaClient` asumen el setup v7 con **driver adapter** (`@prisma/adapter-pg`) y `prisma.config.ts` — sin adapter NO compilan. Setup completo en `prisma7-docs`.

## Por qué TDD primero, código después

En dominio financiero:

- Un bug puede costar dinero real al cliente final.
- Las reglas son densas y abstractas: difíciles de comunicar a una IA con prosa.
- Los tests son el contrato más preciso posible.

**Sin TDD, la IA genera código plausible que pasa el smoke test pero rompe en producción con casos borde.**

---

## Flujo AI-TDD

```
1. Vos escribís el test (define el comportamiento esperado)
        ↓
2. La IA implementa para hacerlo pasar
        ↓
3. Tests corren → verde
        ↓
4. Refactor (IA o vos) sin romper tests
        ↓
5. Si la IA propone cambiar tests → RECHAZAR (los tests son la fuente de verdad)
```

---

## Setup Vitest / Jest

```json
// package.json
{
  "scripts": {
    "test": "vitest",
    "test:watch": "vitest --watch",
    "test:coverage": "vitest --coverage",
    "test:integration": "vitest --config vitest.integration.config.ts"
  }
}
```

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    environment: "node",
    globals: true,
    coverage: {
      provider: "v8",
      reporter: ["text", "html", "lcov"],
      thresholds: {
        statements: 80,
        branches: 75,
        functions: 80,
        lines: 80,
      },
      include: ["src/modules/*/domain/**", "src/modules/*/application/**"],
      exclude: ["**/*.dto.ts", "**/index.ts", "**/*.module.ts"],
    },
  },
});
```

> Apuntá coverage alto en `domain/` y `application/`. En `infrastructure/` (Prisma, HTTP) coverage es menos crítico y más costoso.

---

## Tipos de test

| Tipo        | Ubicación                    | Velocidad           | Qué prueba                             |
| ----------- | ---------------------------- | ------------------- | -------------------------------------- |
| Unit        | `*.spec.ts` junto al archivo | Milisegundos        | Lógica pura (entities, VOs, services)  |
| Use case    | `*.use-case.spec.ts`         | Decenas de ms       | Casos de uso con mocks de repos        |
| Integration | `test/integration/*.spec.ts` | Segundos            | Caso de uso + Prisma real (DB de test) |
| E2E         | `test/e2e/*.e2e-spec.ts`     | Decenas de segundos | HTTP completo + DB + Redis             |

Regla pragmática: 70% unit, 20% integration, 10% E2E.

---

## Patrón 1: Test de entidad de dominio

```typescript
// domain/entities/journal-entry.spec.ts
import { describe, it, expect } from "vitest";
import { JournalEntry } from "./journal-entry.entity";
import { Money } from "../value-objects/money.vo";
import { BalanceViolationError } from "../errors/balance-violation.error";

describe("JournalEntry", () => {
  const tenantId = "tenant-1";

  describe("creation", () => {
    it("creates a balanced entry", () => {
      const entry = JournalEntry.create({
        tenantId,
        entryDate: new Date("2026-01-15"),
        description: "Sale",
        lines: [
          { accountId: "cash", amount: Money.of("1180", "DOP") },
          { accountId: "sales", amount: Money.of("-1000", "DOP") },
          { accountId: "itbis", amount: Money.of("-180", "DOP") },
        ],
      });
      expect(entry.lines).toHaveLength(3);
    });

    it("rejects unbalanced entries", () => {
      expect(() =>
        JournalEntry.create({
          tenantId,
          entryDate: new Date(),
          description: "Bad",
          lines: [
            { accountId: "cash", amount: Money.of("100", "DOP") },
            { accountId: "sales", amount: Money.of("-99", "DOP") },
          ],
        }),
      ).toThrow(BalanceViolationError);
    });

    it.each([
      {
        case: "1 cent overpayment",
        lines: [
          ["cash", "101"],
          ["sales", "-100"],
        ],
      },
      {
        case: "1 cent underpayment",
        lines: [
          ["cash", "99"],
          ["sales", "-100"],
        ],
      },
      {
        case: "huge mismatch",
        lines: [
          ["cash", "10000"],
          ["sales", "-1"],
        ],
      },
    ])("rejects $case", ({ lines }) => {
      expect(() =>
        JournalEntry.create({
          tenantId,
          entryDate: new Date(),
          description: "X",
          lines: lines.map(([id, amt]) => ({
            accountId: id,
            amount: Money.of(amt, "DOP"),
          })),
        }),
      ).toThrow(BalanceViolationError);
    });

    it("rejects entries with less than 2 lines", () => {
      expect(() =>
        JournalEntry.create({
          tenantId,
          entryDate: new Date(),
          description: "X",
          lines: [{ accountId: "cash", amount: Money.of("100", "DOP") }],
        }),
      ).toThrow();
    });

    it("rejects mixed currencies", () => {
      expect(() =>
        JournalEntry.create({
          tenantId,
          entryDate: new Date(),
          description: "X",
          lines: [
            { accountId: "cash-dop", amount: Money.of("100", "DOP") },
            { accountId: "cash-usd", amount: Money.of("-100", "USD") },
          ],
        }),
      ).toThrow();
    });
  });
});
```

---

## Patrón 2: Test de Value Object

```typescript
// domain/value-objects/money.spec.ts
describe("Money", () => {
  describe("arithmetic", () => {
    it("adds correctly without float errors", () => {
      const a = Money.of("0.1", "DOP");
      const b = Money.of("0.2", "DOP");
      expect(a.add(b).toDecimal().toString()).toBe("0.3");
    });

    it("accumulates 1000 additions of 0.10 to exactly 100", () => {
      let acc = Money.zero("DOP");
      for (let i = 0; i < 1000; i++) acc = acc.add(Money.of("0.10", "DOP"));
      expect(acc.toDecimal().toString()).toBe("100");
    });

    it("throws on currency mismatch", () => {
      expect(() => Money.of("100", "DOP").add(Money.of("100", "USD"))).toThrow(
        /Currency mismatch/,
      );
    });
  });

  describe("banker rounding", () => {
    it.each([
      ["1.225", "1.22"],
      ["1.235", "1.24"],
      ["1.245", "1.24"],
      ["1.255", "1.26"],
    ])("rounds %s to %s", (input, expected) => {
      expect(new Decimal(input).toDecimalPlaces(2).toString()).toBe(expected);
    });
  });
});
```

---

## Patrón 3: Test de Use Case con mocks

```typescript
// application/use-cases/post-journal-entry.use-case.spec.ts
import { describe, it, expect, beforeEach, vi } from "vitest";

describe("PostJournalEntryUseCase", () => {
  let useCase: PostJournalEntryUseCase;
  let journalRepo: {
    findByIdempotencyKey: ReturnType<typeof vi.fn>;
    save: ReturnType<typeof vi.fn>;
  };
  let eventPublisher: { publish: ReturnType<typeof vi.fn> };

  beforeEach(() => {
    journalRepo = { findByIdempotencyKey: vi.fn(), save: vi.fn() };
    eventPublisher = { publish: vi.fn() };
    useCase = new PostJournalEntryUseCase(
      journalRepo as any,
      eventPublisher as any,
    );
  });

  it("posts a new entry when idempotency key is fresh", async () => {
    journalRepo.findByIdempotencyKey.mockResolvedValue(null);
    await useCase.execute(validCommand);
    expect(journalRepo.save).toHaveBeenCalledOnce();
    expect(eventPublisher.publish).toHaveBeenCalledWith(
      "JournalEntryPosted",
      expect.any(Object),
    );
  });

  it("is idempotent: returns existing entry on duplicate key", async () => {
    const existing = { id: "existing-id" };
    journalRepo.findByIdempotencyKey.mockResolvedValue(existing);
    const result = await useCase.execute(validCommand);
    expect(journalRepo.save).not.toHaveBeenCalled();
    expect(result.id).toBe("existing-id");
  });

  it("rejects when current period is closed", async () => {
    journalRepo.findByIdempotencyKey.mockResolvedValue(null);
    journalRepo.save.mockRejectedValue(
      new Error("Cannot post entries to closed period"),
    );
    await expect(useCase.execute(validCommand)).rejects.toThrow(
      /closed period/,
    );
  });
});
```

---

## Patrón 4: Test de integración con DB real

```typescript
// test/integration/setup.ts
import { execSync } from "node:child_process";
import { PrismaClient } from "@prisma/client";

let prisma: PrismaClient;

beforeAll(async () => {
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
  execSync("pnpm prisma migrate deploy", { stdio: "inherit" });
  prisma = new PrismaClient();
});

afterEach(async () => {
  // Truncate todo entre tests
  const tablenames = await prisma.$queryRaw<{ tablename: string }[]>`
    SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename != '_prisma_migrations'
  `;
  for (const { tablename } of tablenames) {
    await prisma.$executeRawUnsafe(
      `TRUNCATE TABLE "${tablename}" RESTART IDENTITY CASCADE`,
    );
  }
});

afterAll(async () => {
  await prisma.$disconnect();
});

export { prisma };
```

```typescript
// test/integration/journal-immutability.spec.ts
describe("Journal immutability (PostgreSQL triggers)", () => {
  it("blocks UPDATE on JournalEntry", async () => {
    const entry = await prisma.journalEntry.create({ data: validEntry });
    await expect(
      prisma.$executeRaw`UPDATE "JournalEntry" SET description = 'hack' WHERE id = ${entry.id}`,
    ).rejects.toThrow(/immutable/);
  });

  it("blocks DELETE on JournalLine", async () => {
    const entry = await prisma.journalEntry.create({ data: validEntry });
    await expect(
      prisma.$executeRaw`DELETE FROM "JournalLine" WHERE "entryId" = ${entry.id}`,
    ).rejects.toThrow();
  });
});
```

---

## Patrón 5: Property-based testing para precisión

```typescript
import fc from "fast-check";

describe("Money property-based", () => {
  it("addition is commutative", () => {
    fc.assert(
      fc.property(
        fc.bigInt({ min: -1_000_000n, max: 1_000_000n }),
        fc.bigInt({ min: -1_000_000n, max: 1_000_000n }),
        (a, b) => {
          const m1 = Money.of(a.toString() + ".00", "DOP");
          const m2 = Money.of(b.toString() + ".00", "DOP");
          expect(m1.add(m2).equals(m2.add(m1))).toBe(true);
        },
      ),
    );
  });

  it("subtraction cancels addition", () => {
    fc.assert(
      fc.property(
        fc.float({ min: -10000, max: 10000, noNaN: true }),
        fc.float({ min: -10000, max: 10000, noNaN: true }),
        (a, b) => {
          const m1 = Money.of(a.toFixed(2), "DOP");
          const m2 = Money.of(b.toFixed(2), "DOP");
          expect(m1.add(m2).subtract(m2).equals(m1)).toBe(true);
        },
      ),
    );
  });
});
```

---

## Prompt para que la IA escriba código contra tests

```
Aquí tienes los tests para `PostJournalEntryUseCase`:

[pegar tests]

Implementá el caso de uso para que pasen TODOS los tests. Reglas:

1. NO modifiques los tests.
2. NO uses `any`, `ts-ignore`, ni casteos inseguros.
3. Inyectá dependencias por interfaces, no clases concretas.
4. Usá `Decimal` para dinero, nunca `number`.
5. Validá idempotencia leyendo `journalRepo.findByIdempotencyKey` antes de `save`.
6. Emití el evento `JournalEntryPosted` solo si se persistió un asiento nuevo.

Devolveme SOLO el código de la implementación. Sin explicaciones.
```

---

## Cuando los tests pasan pero el código está mal

A veces la IA "engaña" al test: hace un short-circuit, usa un mock como si fuera real, retorna un valor hardcodeado.

Defensas:

1. **Tests con múltiples assertions** (no solo "no tira error").
2. **Property-based testing** para casos no anticipados.
3. **Integration tests** sobre el use case con Prisma real.
4. **Mutation testing** con Stryker para validar la calidad del test mismo.

```bash
pnpm add -D @stryker-mutator/core @stryker-mutator/vitest-runner
npx stryker run
```

Stryker introduce bugs deliberados en tu código. Si los tests siguen pasando, los tests son débiles.
