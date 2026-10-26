# 01 — Clean Architecture + DDD

## Regla suprema: dirección de las dependencias

```
Presentation  ──→  Application  ──→  Domain
     │                  │              ↑
     └──→ Infrastructure ──────────────┘
```

- **Domain** no importa NADA externo. Cero NestJS, cero Prisma, cero librerías HTTP.
- **Application** importa solo del Domain (entidades + interfaces de repos).
- **Infrastructure** implementa las interfaces del Domain (Prisma, Redis, MinIO, etc).
- **Presentation** (controllers NestJS, páginas Next.js) orquesta Application.

Si la IA escribe `import { PrismaService } from ...` dentro de `domain/`, **rechazá el código**.

---

## Anatomía de un Bounded Context

```
modules/accounting/
├── domain/
│   ├── entities/
│   │   ├── journal-entry.entity.ts        ← Lógica de negocio pura
│   │   └── account.entity.ts
│   ├── value-objects/
│   │   ├── money.vo.ts                     ← Inmutable, autovalidante
│   │   └── account-code.vo.ts
│   ├── errors/
│   │   ├── balance-violation.error.ts     ← Excepciones de dominio
│   │   └── account-not-found.error.ts
│   ├── repositories/
│   │   └── journal.repository.ts          ← INTERFAZ, no implementación
│   ├── events/
│   │   └── journal-entry-posted.event.ts
│   └── services/                          ← Domain Services (opcional)
│       └── double-entry-validator.ts
├── application/
│   ├── use-cases/
│   │   ├── post-journal-entry.use-case.ts
│   │   └── close-fiscal-period.use-case.ts
│   ├── dtos/                              ← DTOs internos, no HTTP
│   │   └── post-journal-entry.command.ts
│   └── ports/                             ← Interfaces de servicios externos
│       └── event-publisher.port.ts
├── infrastructure/
│   ├── prisma/
│   │   └── journal.prisma-repository.ts   ← Implementa la interface del domain
│   ├── queue/
│   │   └── accounting.processor.ts
│   └── adapters/
│       └── bullmq-event-publisher.adapter.ts
└── presentation/
    ├── controllers/
    │   └── journal.controller.ts
    ├── dtos/                              ← DTOs HTTP con class-validator
    │   └── post-journal-entry.dto.ts
    └── accounting.module.ts               ← NestJS module wiring
```

---

## Ejemplo: Value Object `Money`

```typescript
// domain/value-objects/money.vo.ts
import Decimal from "decimal.js";

Decimal.set({ rounding: Decimal.ROUND_HALF_EVEN });

export class Money {
  private readonly _amount: Decimal;

  private constructor(
    amount: Decimal | string | number,
    public readonly currency: string,
  ) {
    this._amount = new Decimal(amount);
    if (!this._amount.isFinite()) {
      throw new Error("Money amount must be finite");
    }
    if (!/^[A-Z]{3}$/.test(currency)) {
      throw new Error(`Invalid currency code: ${currency}`);
    }
  }

  static of(amount: Decimal | string | number, currency: string): Money {
    return new Money(amount, currency);
  }

  static zero(currency: string): Money {
    return new Money(0, currency);
  }

  add(other: Money): Money {
    this.assertSameCurrency(other);
    return new Money(this._amount.plus(other._amount), this.currency);
  }

  subtract(other: Money): Money {
    this.assertSameCurrency(other);
    return new Money(this._amount.minus(other._amount), this.currency);
  }

  multiply(factor: Decimal | string | number): Money {
    return new Money(this._amount.times(new Decimal(factor)), this.currency);
  }

  isZero(): boolean {
    return this._amount.isZero();
  }

  isNegative(): boolean {
    return this._amount.isNegative();
  }

  equals(other: Money): boolean {
    return (
      this.currency === other.currency && this._amount.equals(other._amount)
    );
  }

  toDecimal(): Decimal {
    return this._amount;
  }

  toString(): string {
    return `${this._amount.toFixed(2)} ${this.currency}`;
  }

  private assertSameCurrency(other: Money): void {
    if (this.currency !== other.currency) {
      throw new Error(
        `Currency mismatch: ${this.currency} vs ${other.currency}`,
      );
    }
  }
}
```

**Cero dependencias de framework.** Esto vive en `domain/` y puede testearse sin NestJS, sin Prisma, sin DB.

---

## Ejemplo: Interface de Repositorio en Domain

```typescript
// domain/repositories/journal.repository.ts
import { JournalEntry } from "../entities/journal-entry.entity";

export interface IJournalRepository {
  findById(tenantId: string, id: string): Promise<JournalEntry | null>;
  save(entry: JournalEntry): Promise<void>;
  findByPeriod(tenantId: string, from: Date, to: Date): Promise<JournalEntry[]>;
}

export const JOURNAL_REPOSITORY = Symbol("IJournalRepository");
```

## Ejemplo: Implementación Prisma en Infrastructure

```typescript
// infrastructure/prisma/journal.prisma-repository.ts
import { Injectable } from "@nestjs/common";
import { PrismaService } from "@/shared/infrastructure/prisma/prisma.service";
import { IJournalRepository } from "../../domain/repositories/journal.repository";
import { JournalEntry } from "../../domain/entities/journal-entry.entity";
import { JournalMapper } from "./journal.mapper";

@Injectable()
export class JournalPrismaRepository implements IJournalRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findById(tenantId: string, id: string): Promise<JournalEntry | null> {
    const record = await this.prisma.journalEntry.findFirst({
      where: { id, tenantId, deletedAt: null },
      include: { lines: true },
    });
    return record ? JournalMapper.toDomain(record) : null;
  }

  async save(entry: JournalEntry): Promise<void> {
    const data = JournalMapper.toPersistence(entry);
    await this.prisma.journalEntry.create({ data });
  }

  // ...
}
```

## Wiring en NestJS Module

```typescript
// accounting.module.ts
import { Module } from "@nestjs/common";
import { JOURNAL_REPOSITORY } from "./domain/repositories/journal.repository";
import { JournalPrismaRepository } from "./infrastructure/prisma/journal.prisma-repository";
import { PostJournalEntryUseCase } from "./application/use-cases/post-journal-entry.use-case";
import { JournalController } from "./presentation/controllers/journal.controller";

@Module({
  controllers: [JournalController],
  providers: [
    PostJournalEntryUseCase,
    {
      provide: JOURNAL_REPOSITORY,
      useClass: JournalPrismaRepository,
    },
  ],
})
export class AccountingModule {}
```

---

## Reglas de import (validables con `architecture-guard`)

```js
// .dependency-cruiser.js (extracto)
{
  name: 'no-domain-importing-infra',
  severity: 'error',
  from: { path: '^src/modules/[^/]+/domain' },
  to:   { path: '^(src/modules/[^/]+/(infrastructure|presentation)|@nestjs|@prisma)' },
},
{
  name: 'no-application-importing-presentation',
  severity: 'error',
  from: { path: '^src/modules/[^/]+/application' },
  to:   { path: '^src/modules/[^/]+/presentation' },
},
```

---

## Resumen mental

| Capa           | Pregunta clave                                     | Si responde sí, va aquí        |
| -------------- | -------------------------------------------------- | ------------------------------ |
| Domain         | ¿Sigue siendo cierto si cambio Postgres por Mongo? | Entidades, VOs, reglas puras   |
| Application    | ¿Orquesta un caso de uso del negocio?              | Use cases, comandos            |
| Infrastructure | ¿Habla con el mundo exterior?                      | Prisma, Redis, MinIO, APIs     |
| Presentation   | ¿Recibe HTTP o renderiza?                          | Controllers, DTOs HTTP, vistas |
