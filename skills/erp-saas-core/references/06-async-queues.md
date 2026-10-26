# 06 — Colas Asíncronas (BullMQ + Redis)

## Regla de oro síncrono vs asíncrono

| Síncrono (responde al HTTP)        | Asíncrono (BullMQ)          |
| ---------------------------------- | --------------------------- |
| Validar stock + decremento atómico | Generar asientos contables  |
| Cobrar tarjeta (autorización real) | Enviar e-CF a DGII          |
| Asignar NCF                        | Enviar email / SMS / push   |
| Crear factura básica + payments    | Sincronizar con ERP externo |
| Persistir venta con items          | Reportería pesada           |
| Responder ticket al cajero         | Generación de PDFs          |

Si tarda > 200ms y no es crítico para el cajero, va a cola.

---

## Setup en NestJS

```bash
pnpm add @nestjs/bullmq bullmq ioredis
```

```typescript
// app.module.ts
import { BullModule } from "@nestjs/bullmq";

@Module({
  imports: [
    BullModule.forRoot({
      connection: {
        host: process.env.REDIS_HOST,
        port: parseInt(process.env.REDIS_PORT),
        password: process.env.REDIS_PASSWORD,
      },
      defaultJobOptions: {
        attempts: 5,
        backoff: { type: "exponential", delay: 1000 },
        removeOnComplete: { count: 1000, age: 86400 },
        removeOnFail: { count: 5000, age: 604800 },
      },
    }),
  ],
})
export class AppModule {}
```

---

## Colas estándar para un ERP

```typescript
export const QUEUE_NAMES = {
  ACCOUNTING: "accounting", // generación de asientos
  FISCAL_DGII: "fiscal-dgii", // envío de e-CF
  NOTIFICATIONS: "notifications", // email, SMS, push
  EXPORTS: "exports", // PDFs, Excel, reportes
  SYNC: "sync", // integraciones externas
  AUDIT: "audit", // logs pesados
} as const;
```

Cola dedicada por dominio = aislamiento de fallos. Si DGII está caída, la cola fiscal se acumula pero contabilidad sigue procesando.

---

## Productor (desde el use case)

```typescript
// application/use-cases/complete-sale.use-case.ts
@Injectable()
export class CompleteSaleUseCase {
  constructor(
    @InjectQueue(QUEUE_NAMES.ACCOUNTING)
    private readonly accountingQueue: Queue,
    @InjectQueue(QUEUE_NAMES.FISCAL_DGII) private readonly fiscalQueue: Queue,
    private readonly prisma: PrismaService,
  ) {}

  async execute(cmd: CompleteSaleCommand) {
    const sale = await this.prisma.$transaction(async (tx) => {
      const sale = await this.persistSale(tx, cmd);
      // Outbox pattern: el evento se guarda en la misma transacción
      await tx.outboxEvent.createMany({
        data: [
          {
            tenantId: cmd.tenantId,
            eventName: "SaleCompleted",
            payload: { saleId: sale.id },
          },
          ...(cmd.ncfType
            ? [
                {
                  tenantId: cmd.tenantId,
                  eventName: "eCFNeeded",
                  payload: { saleId: sale.id },
                },
              ]
            : []),
        ],
      });
      return sale;
    });
    return sale;
  }
}
```

> **No publiques directo al queue desde dentro del `$transaction`.** Si la transacción rollback, el job ya fue enviado. Usá Outbox.

---

## Worker / Processor

```typescript
// infrastructure/queue/accounting.processor.ts
import { Processor, WorkerHost } from "@nestjs/bullmq";
import { Job } from "bullmq";

@Processor(QUEUE_NAMES.ACCOUNTING, { concurrency: 5 })
export class AccountingProcessor extends WorkerHost {
  private readonly logger = new Logger(AccountingProcessor.name);

  constructor(
    private readonly postJournalEntry: PostJournalEntryUseCase,
    private readonly prisma: PrismaService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    switch (job.name) {
      case "SaleCompleted":
        return this.handleSaleCompleted(job);
      case "PurchaseReceived":
        return this.handlePurchaseReceived(job);
      default:
        this.logger.warn(`Unknown job: ${job.name}`);
    }
  }

  private async handleSaleCompleted(
    job: Job<{ saleId: string; tenantId: string }>,
  ) {
    const { saleId, tenantId } = job.data;

    // Idempotencia: el use case usa idempotencyKey = saleId
    await this.postJournalEntry.execute({
      tenantId,
      idempotencyKey: `sale-${saleId}`,
      sourceModule: "POS",
      sourceEntityId: saleId,
      // construye las líneas de partida doble desde la venta
    });
  }
}
```

---

## Retry strategy + DLQ

```typescript
{
  attempts: 5,
  backoff: { type: 'exponential', delay: 2000 },
  // intentos: 2s, 4s, 8s, 16s, 32s
}
```

Para jobs que fallan tras N intentos: pasar a una "Dead Letter Queue" manual + alertar:

```typescript
async process(job: Job) {
  try {
    return await this.handle(job);
  } catch (err) {
    if (job.attemptsMade >= job.opts.attempts) {
      await this.prisma.failedJob.create({
        data: {
          tenantId: job.data.tenantId,
          queueName: job.queueName,
          jobName: job.name,
          payload: job.data,
          error: err.message,
          stack: err.stack,
        },
      });
      await this.notifyOps(`Job ${job.name} failed after ${job.attemptsMade} attempts`);
    }
    throw err;
  }
}
```

---

## Job options útiles

```typescript
await queue.add("SaleCompleted", payload, {
  jobId: `sale-${saleId}`, // idempotencia a nivel cola
  attempts: 5,
  backoff: { type: "exponential", delay: 1000 },
  delay: 0, // ejecutar inmediato
  priority: 1, // 1 = más alta
  removeOnComplete: true,
});

// Job recurrente (cron-like)
await queue.add(
  "NightlyReport",
  {},
  {
    repeat: { pattern: "0 2 * * *" }, // 2 AM diario
    jobId: "nightly-report", // único, no duplica
  },
);
```

---

## Concurrencia por cola

```typescript
@Processor(QUEUE_NAMES.FISCAL_DGII, { concurrency: 2 })  // DGII no quiere flood
@Processor(QUEUE_NAMES.NOTIFICATIONS, { concurrency: 20 })  // emails sí
```

Concurrencia alta = más throughput pero más carga a la DB. Empezá bajo (3-5), monitoreá, escalá.

---

## Monitoreo: Bull Board

```bash
pnpm add @bull-board/express @bull-board/api
```

```typescript
// main.ts
import { createBullBoard } from "@bull-board/api";
import { BullMQAdapter } from "@bull-board/api/bullMQAdapter";
import { ExpressAdapter } from "@bull-board/express";

const serverAdapter = new ExpressAdapter();
serverAdapter.setBasePath("/admin/queues");

createBullBoard({
  queues: [
    new BullMQAdapter(accountingQueue),
    new BullMQAdapter(fiscalQueue),
    new BullMQAdapter(notificationsQueue),
  ],
  serverAdapter,
});

app.use("/admin/queues", adminGuard, serverAdapter.getRouter());
```

UI en `localhost:3000/admin/queues` con visibilidad de jobs activos, completados, fallidos, retries.

---

## Patrón: Job dependency chain

A veces el orden importa: primero genera el asiento, después el e-CF, después la notificación.

```typescript
import { FlowProducer } from "bullmq";

const flow = new FlowProducer({ connection });

await flow.add({
  name: "NotifyCustomer",
  queueName: QUEUE_NAMES.NOTIFICATIONS,
  data: { saleId, customerEmail },
  children: [
    {
      name: "SendECF",
      queueName: QUEUE_NAMES.FISCAL_DGII,
      data: { saleId },
      children: [
        {
          name: "PostJournalEntry",
          queueName: QUEUE_NAMES.ACCOUNTING,
          data: { saleId },
        },
      ],
    },
  ],
});

// Ejecución: PostJournalEntry → SendECF → NotifyCustomer
```

---

## Tests para processors

```typescript
describe("AccountingProcessor", () => {
  let processor: AccountingProcessor;
  let postJournalEntry: jest.Mocked<PostJournalEntryUseCase>;

  beforeEach(() => {
    postJournalEntry = { execute: jest.fn() } as any;
    processor = new AccountingProcessor(postJournalEntry, prismaMock);
  });

  it("posts a journal entry for SaleCompleted", async () => {
    const job = {
      name: "SaleCompleted",
      data: { saleId: "s1", tenantId: "t1" },
    } as any;
    await processor.process(job);
    expect(postJournalEntry.execute).toHaveBeenCalledWith(
      expect.objectContaining({
        tenantId: "t1",
        idempotencyKey: "sale-s1",
        sourceEntityId: "s1",
      }),
    );
  });
});
```
