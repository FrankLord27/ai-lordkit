# Redis — Colas con BullMQ

Sistema de colas robusto para NestJS basado en Redis.

## Instalación

```bash
pnpm add @nestjs/bullmq bullmq
```

## Configuración

```typescript
// app.module.ts
import { BullModule } from "@nestjs/bullmq";

@Module({
  imports: [
    BullModule.forRoot({
      connection: {
        host: process.env.REDIS_HOST ?? "localhost",
        port: parseInt(process.env.REDIS_PORT ?? "6379"),
        password: process.env.REDIS_PASSWORD,
      },
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: "exponential", delay: 1000 },
        removeOnComplete: 100,
        removeOnFail: 500,
      },
    }),
    BullModule.registerQueue({ name: "emails" }, { name: "reports" }),
  ],
})
export class AppModule {}
```

## Producer (enviar jobs)

```typescript
import { InjectQueue } from "@nestjs/bullmq";
import { Queue } from "bullmq";

@Injectable()
export class EmailsService {
  constructor(@InjectQueue("emails") private queue: Queue) {}

  async sendEmail(data: { to: string; template: string }): Promise<string> {
    const job = await this.queue.add("send", data);
    return job.id!;
  }

  async sendEmailLater(data: any, delay: number): Promise<string> {
    const job = await this.queue.add("send", data, { delay });
    return job.id!;
  }

  async sendBulk(emails: any[]): Promise<string[]> {
    const jobs = await this.queue.addBulk(
      emails.map((data) => ({ name: "send", data })),
    );
    return jobs.map((j) => j.id!);
  }
}
```

## Consumer (procesar jobs)

```typescript
import { Processor, WorkerHost, OnWorkerEvent } from "@nestjs/bullmq";
import { Job } from "bullmq";

@Processor("emails")
export class EmailsProcessor extends WorkerHost {
  async process(job: Job<{ to: string; template: string }>): Promise<any> {
    console.log(`Processing job ${job.id}`);

    await job.updateProgress(10);
    const html = await this.renderTemplate(job.data.template);

    await job.updateProgress(50);
    await this.sendEmail(job.data.to, html);

    await job.updateProgress(100);
    return { sent: true, to: job.data.to };
  }

  @OnWorkerEvent("completed")
  onCompleted(job: Job) {
    console.log(`Job ${job.id} completed`);
  }

  @OnWorkerEvent("failed")
  onFailed(job: Job, error: Error) {
    console.error(`Job ${job.id} failed:`, error.message);
  }
}
```

## Rate Limiting

```typescript
@Processor('api-calls', {
  limiter: { max: 10, duration: 1000 }, // 10 jobs/segundo
})
export class ApiProcessor extends WorkerHost {
  async process(job: Job) { /* ... */ }
}

// Por grupo (tenant)
@Processor('api-calls', {
  limiter: { max: 10, duration: 1000, groupKey: 'tenantId' },
})
```

## Flows (jobs con dependencias)

```typescript
import { FlowProducer } from "bullmq";

@Injectable()
export class ReportService {
  private flowProducer: FlowProducer;

  constructor(@InjectQueue("reports") queue: Queue) {
    this.flowProducer = new FlowProducer({ connection: queue.opts.connection });
  }

  async generateReport(reportId: string): Promise<void> {
    await this.flowProducer.add({
      name: "compile",
      queueName: "reports",
      data: { reportId },
      children: [
        { name: "fetch-sales", queueName: "reports", data: { reportId } },
        { name: "fetch-users", queueName: "reports", data: { reportId } },
      ],
    });
    // compile se ejecuta después de que los hijos terminen
  }
}
```

## Jobs Recurrentes (Cron)

```typescript
@Injectable()
export class ScheduledJobs implements OnModuleInit {
  constructor(@InjectQueue("maintenance") private queue: Queue) {}

  async onModuleInit() {
    // Cada hora
    await this.queue.add("cleanup", {}, { repeat: { pattern: "0 * * * *" } });

    // Cada día a las 3am
    await this.queue.add(
      "report",
      {},
      {
        repeat: { pattern: "0 3 * * *", tz: "America/Santo_Domingo" },
      },
    );

    // Cada 5 minutos
    await this.queue.add("health", {}, { repeat: { every: 5 * 60 * 1000 } });
  }
}
```

## Bull Board (UI de monitoreo)

```bash
pnpm add @bull-board/express @bull-board/api
```

```typescript
import { createBullBoard } from "@bull-board/api";
import { BullMQAdapter } from "@bull-board/api/bullMQAdapter";
import { ExpressAdapter } from "@bull-board/express";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  const emailQueue = app.get<Queue>(getQueueToken("emails"));
  const serverAdapter = new ExpressAdapter();
  serverAdapter.setBasePath("/admin/queues");

  createBullBoard({
    queues: [new BullMQAdapter(emailQueue)],
    serverAdapter,
  });

  app.use("/admin/queues", serverAdapter.getRouter());
  await app.listen(3000);
}
```

## Mejores Prácticas

```typescript
// ✅ Jobs idempotentes
async process(job: Job) {
  const existing = await prisma.payment.findUnique({ where: { id: job.data.paymentId } });
  if (existing?.status === 'completed') return { status: 'already-processed' };
  // procesar...
}

// ✅ Jobs pequeños
const userIds = await prisma.user.findMany({ select: { id: true } });
await queue.addBulk(userIds.map(u => ({ name: 'process', data: { userId: u.id } })));

// ❌ Evitar jobs grandes
await queue.add('process', { users: await prisma.user.findMany() }); // MAL
```
