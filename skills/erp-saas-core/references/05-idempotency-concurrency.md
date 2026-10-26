# 05 — Idempotencia + Concurrencia

## Por qué importa

Sin idempotencia: doble clic = doble cobro. Reintento de red = factura duplicada. Worker que reprocesa = asiento contable repetido.

Una operación idempotente produce el mismo efecto en el sistema si se ejecuta 1 vez o 100 veces con los mismos parámetros.

---

## Patrón estándar: Idempotency Key

### 1. Frontend genera UUID por intento

```typescript
// useCheckout.ts
import { v4 as uuidv4 } from "uuid";
import { useMutation } from "@tanstack/react-query";

export function useCheckout() {
  const idempotencyKeyRef = useRef(uuidv4());

  return useMutation({
    mutationFn: async (payload) => {
      return api.post("/sales/checkout", payload, {
        headers: { "X-Idempotency-Key": idempotencyKeyRef.current },
      });
    },
    // Si fallás y reintentás, TanStack Query reusa el mismo key
    retry: 3,
    onSuccess: () => {
      idempotencyKeyRef.current = uuidv4(); // nueva key para la próxima intención
    },
  });
}
```

**Regla:** el key se genera UNA vez por intención de pago. Si el usuario hace doble clic, los 2 requests llevan la misma key. Si reinicia el navegador y reabre, ahí sí nueva key.

### 2. Backend valida en 3 capas

```typescript
// presentation/middleware/idempotency.guard.ts
import {
  Injectable,
  CanActivate,
  ExecutionContext,
  BadRequestException,
} from "@nestjs/common";

@Injectable()
export class IdempotencyKeyGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    const key = req.headers["x-idempotency-key"];
    if (!key || typeof key !== "string" || key.length < 16) {
      throw new BadRequestException(
        "Missing or invalid X-Idempotency-Key header",
      );
    }
    req.idempotencyKey = key;
    return true;
  }
}
```

### 3. Caché Redis con respuesta congelada

```typescript
// application/services/idempotent-executor.service.ts
@Injectable()
export class IdempotentExecutor {
  constructor(@InjectRedis() private readonly redis: Redis) {}

  async execute<T>(
    key: string,
    tenantId: string,
    operation: string,
    handler: () => Promise<T>,
    ttlSeconds = 86400,
  ): Promise<T> {
    const cacheKey = `idem:${tenantId}:${operation}:${key}`;

    // 1. ¿Ya existe respuesta cacheada?
    const cached = await this.redis.get(cacheKey);
    if (cached) {
      const { status, payload } = JSON.parse(cached);
      if (status === "COMPLETED") return payload as T;
      if (status === "IN_PROGRESS") {
        throw new ConflictException(
          "Operation in progress with same idempotency key",
        );
      }
    }

    // 2. Marcar como IN_PROGRESS (lock distribuido)
    const acquired = await this.redis.set(
      cacheKey,
      JSON.stringify({ status: "IN_PROGRESS" }),
      "EX",
      60,
      "NX", // solo si no existe
    );
    if (!acquired) {
      throw new ConflictException("Duplicate request");
    }

    // 3. Ejecutar
    try {
      const result = await handler();
      await this.redis.set(
        cacheKey,
        JSON.stringify({ status: "COMPLETED", payload: result }),
        "EX",
        ttlSeconds,
      );
      return result;
    } catch (err) {
      // No cachear errores — permitir reintento
      await this.redis.del(cacheKey);
      throw err;
    }
  }
}
```

### 4. Última barrera: `@unique` en Prisma

```prisma
model Transaction {
  id              String   @id @default(uuid())
  tenantId        String
  idempotencyKey  String
  amount          Decimal
  status          String

  @@unique([tenantId, idempotencyKey])
}
```

Si Redis falla o se llena, la DB rechaza con error de constraint. Capturalo:

```typescript
try {
  return await prisma.transaction.create({ data: { ... } });
} catch (err) {
  if (err.code === 'P2002') {
    // Duplicate. Buscar y devolver la existente.
    return await prisma.transaction.findUnique({
      where: { tenantId_idempotencyKey: { tenantId, idempotencyKey } },
    });
  }
  throw err;
}
```

---

## Concurrencia: Row-Level Locking

### Caso: dos cajas venden el último producto al mismo tiempo

```typescript
// Mal — sin lock
const product = await tx.product.findUnique({ where: { id } });
if (product.stock < qty) throw new OutOfStockError();
await tx.product.update({
  where: { id },
  data: { stock: product.stock - qty },
});
// Race condition: ambas leen stock=1, ambas restan, queda en -1
```

```typescript
// Bien — update condicional atómico
const result = await tx.product
  .update({
    where: { id, stock: { gte: qty } }, // ★ condición en where
    data: { stock: { decrement: qty } },
  })
  .catch((err) => {
    if (err.code === "P2025") throw new OutOfStockError(); // record not found
    throw err;
  });
```

PostgreSQL serializa el `UPDATE` con `WHERE stock >= qty`. La segunda venta fallará porque la condición ya no se cumple.

### Caso: secuencia de NCF (no podemos tener dos facturas con el mismo número)

```typescript
async getNextNcfSequence(tenantId: string, type: 'B01' | 'B02') {
  return this.prisma.$transaction(async (tx) => {
    // FOR UPDATE bloquea la fila hasta commit
    const [row] = await tx.$queryRaw<Array<{ next_value: number }>>`
      UPDATE "NcfSequence"
      SET "currentValue" = "currentValue" + 1
      WHERE "tenantId" = ${tenantId} AND "type" = ${type}
      RETURNING "currentValue" AS next_value
    `;
    if (!row) throw new NcfSequenceExhaustedError(type);
    return formatNcf(type, row.next_value);
  }, { isolationLevel: 'Serializable' });
}
```

### Niveles de aislamiento PostgreSQL

| Nivel                     | Cuándo usarlo                                           |
| ------------------------- | ------------------------------------------------------- |
| `ReadCommitted` (default) | 95% de los casos                                        |
| `RepeatableRead`          | Cálculos sobre múltiples reads en una transacción       |
| `Serializable`            | Secuencias críticas (NCF), cierre de caja, conciliación |

Más restrictivo = más seguro pero más probable que falle por conflicto (hay que reintentar).

---

## Patrón "Outbox" para eventos confiables

Problema: si publicás un evento a BullMQ y la transacción de DB falla, tenés un evento sin sustento. Si la DB commitea y BullMQ falla, perdés el evento.

Solución: guardar el evento en una tabla "outbox" en la misma transacción DB. Un worker lee la outbox y publica a BullMQ.

```prisma
model OutboxEvent {
  id          String   @id @default(uuid())
  tenantId    String
  eventName   String
  payload     Json
  publishedAt DateTime?
  createdAt   DateTime @default(now())
  attempts    Int      @default(0)

  @@index([publishedAt, createdAt])
}
```

```typescript
// dentro de la transacción de la venta
await tx.outboxEvent.create({
  data: {
    tenantId,
    eventName: "SaleCompleted",
    payload: { saleId, total: total.toString() },
  },
});
```

Worker separado:

```typescript
@Injectable()
export class OutboxPublisher {
  @Cron("*/5 * * * * *") // cada 5 segundos
  async publish() {
    const events = await this.prisma.outboxEvent.findMany({
      where: { publishedAt: null },
      orderBy: { createdAt: "asc" },
      take: 100,
    });
    for (const event of events) {
      try {
        await this.queue.add(event.eventName, event.payload);
        await this.prisma.outboxEvent.update({
          where: { id: event.id },
          data: { publishedAt: new Date() },
        });
      } catch (err) {
        await this.prisma.outboxEvent.update({
          where: { id: event.id },
          data: { attempts: { increment: 1 } },
        });
      }
    }
  }
}
```

---

## Tests

```typescript
describe("Idempotency", () => {
  it("returns the same response for repeated requests with same key", async () => {
    const key = uuidv4();
    const r1 = await request(app)
      .post("/sales")
      .set("X-Idempotency-Key", key)
      .send(payload);
    const r2 = await request(app)
      .post("/sales")
      .set("X-Idempotency-Key", key)
      .send(payload);
    expect(r1.body).toEqual(r2.body);
    expect(await prisma.sale.count({ where: { idempotencyKey: key } })).toBe(1);
  });

  it("rejects concurrent requests with same key", async () => {
    const key = uuidv4();
    const [r1, r2] = await Promise.allSettled([
      request(app).post("/sales").set("X-Idempotency-Key", key).send(payload),
      request(app).post("/sales").set("X-Idempotency-Key", key).send(payload),
    ]);
    // Una debe ganar, la otra debe responder 409 Conflict
    const statuses = [r1, r2].map((r) => r.value?.status).sort();
    expect(statuses).toEqual([201, 409]);
  });
});

describe("Stock concurrency", () => {
  it("prevents overselling when 2 sales hit last unit", async () => {
    await prisma.product.update({ where: { id }, data: { stock: 1 } });

    const [a, b] = await Promise.allSettled([
      sellOne(productId),
      sellOne(productId),
    ]);

    const winners = [a, b].filter((r) => r.status === "fulfilled").length;
    expect(winners).toBe(1);
    expect((await prisma.product.findUnique({ where: { id } })).stock).toBe(0);
  });
});
```
