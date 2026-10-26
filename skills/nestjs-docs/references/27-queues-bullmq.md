# NestJS — Queues con BullMQ

Procesar tareas en segundo plano: emails, reportes, procesamiento de imágenes, sincronización.

---

## Instalación

```bash
pnpm add @nestjs/bullmq bullmq
```

Requiere Redis corriendo.

---

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
        attempts: 3, // Reintentar 3 veces
        backoff: { type: "exponential", delay: 1000 },
        removeOnComplete: 100, // Mantener últimos 100 completados
        removeOnFail: 500, // Mantener últimos 500 fallidos
      },
    }),
  ],
})
export class AppModule {}
```

---

## Definir una queue

```typescript
// modules/emails/emails.module.ts
import { BullModule } from "@nestjs/bullmq";

@Module({
  imports: [
    BullModule.registerQueue({
      name: "emails", // Nombre de la queue
    }),
  ],
  providers: [EmailsService, EmailsProcessor],
  exports: [EmailsService],
})
export class EmailsModule {}
```

---

## Agregar jobs a la queue (Producer)

```typescript
// modules/emails/emails.service.ts
import { Injectable } from "@nestjs/common";
import { InjectQueue } from "@nestjs/bullmq";
import { Queue } from "bullmq";

interface SendEmailJob {
  to: string;
  subject: string;
  template: string;
  data: Record<string, unknown>;
}

@Injectable()
export class EmailsService {
  constructor(@InjectQueue("emails") private emailQueue: Queue) {}

  // Agregar job simple
  async sendWelcomeEmail(userId: string, email: string) {
    await this.emailQueue.add("welcome", {
      to: email,
      subject: "Bienvenido!",
      template: "welcome",
      data: { userId },
    });
  }

  // Job con opciones
  async sendPasswordReset(email: string, token: string) {
    await this.emailQueue.add(
      "password-reset",
      { to: email, token },
      {
        priority: 1, // Alta prioridad (menor = más urgente)
        attempts: 5, // Override default
        delay: 0, // Ejecutar inmediatamente
      },
    );
  }

  // Job programado (delayed)
  async sendReminder(email: string, eventDate: Date) {
    const delay = eventDate.getTime() - Date.now() - 24 * 60 * 60 * 1000; // 1 día antes

    await this.emailQueue.add(
      "reminder",
      { to: email, eventDate },
      { delay: Math.max(0, delay) },
    );
  }

  // Job recurrente (cron)
  async scheduleDigest(userId: string) {
    await this.emailQueue.add(
      "daily-digest",
      { userId },
      {
        repeat: {
          pattern: "0 9 * * *", // Cada día a las 9am
        },
        jobId: `digest-${userId}`, // ID único para este repeat
      },
    );
  }

  // Bulk add
  async sendBulkNotification(emails: string[], message: string) {
    const jobs = emails.map((email) => ({
      name: "notification",
      data: { to: email, message },
      opts: { priority: 10 }, // Baja prioridad
    }));

    await this.emailQueue.addBulk(jobs);
  }
}
```

---

## Procesar jobs (Consumer/Processor)

```typescript
// modules/emails/emails.processor.ts
import { Processor, WorkerHost, OnWorkerEvent } from "@nestjs/bullmq";
import { Logger } from "@nestjs/common";
import { Job } from "bullmq";

@Processor("emails")
export class EmailsProcessor extends WorkerHost {
  private readonly logger = new Logger(EmailsProcessor.name);

  async process(job: Job) {
    this.logger.log(`Processing job ${job.id} of type ${job.name}`);

    switch (job.name) {
      case "welcome":
        return this.sendWelcomeEmail(job.data);
      case "password-reset":
        return this.sendPasswordReset(job.data);
      case "reminder":
        return this.sendReminder(job.data);
      case "daily-digest":
        return this.sendDigest(job.data);
      default:
        this.logger.warn(`Unknown job type: ${job.name}`);
    }
  }

  private async sendWelcomeEmail(data: { to: string; userId: string }) {
    // Lógica de envío de email
    this.logger.log(`Sending welcome email to ${data.to}`);

    // Simular envío
    await new Promise((resolve) => setTimeout(resolve, 1000));

    return { sent: true, to: data.to };
  }

  private async sendPasswordReset(data: { to: string; token: string }) {
    this.logger.log(`Sending password reset to ${data.to}`);
    await new Promise((resolve) => setTimeout(resolve, 500));
    return { sent: true };
  }

  private async sendReminder(data: { to: string; eventDate: Date }) {
    this.logger.log(`Sending reminder to ${data.to}`);
    return { sent: true };
  }

  private async sendDigest(data: { userId: string }) {
    this.logger.log(`Generating digest for user ${data.userId}`);
    return { sent: true };
  }

  // Event handlers
  @OnWorkerEvent("completed")
  onCompleted(job: Job) {
    this.logger.log(
      `Job ${job.id} completed with result: ${JSON.stringify(job.returnvalue)}`,
    );
  }

  @OnWorkerEvent("failed")
  onFailed(job: Job, error: Error) {
    this.logger.error(`Job ${job.id} failed: ${error.message}`);
    // Aquí podrías enviar alerta a Slack/Sentry
  }

  @OnWorkerEvent("progress")
  onProgress(job: Job, progress: number) {
    this.logger.log(`Job ${job.id} progress: ${progress}%`);
  }
}
```

---

## Reportar progreso

```typescript
@Processor('reports')
export class ReportsProcessor extends WorkerHost {
  async process(job: Job) {
    const items = await this.getItems();
    const total = items.length;

    for (let i = 0; i < total; i++) {
      await this.processItem(items[i]);

      // Actualizar progreso (0-100)
      await job.updateProgress(Math.round((i + 1) / total * 100));
    }

    return { processed: total };
  }
}

// En el controller, puedes consultar el progreso:
@Get('reports/:jobId/progress')
async getProgress(@Param('jobId') jobId: string) {
  const job = await this.reportsQueue.getJob(jobId);
  return { progress: job?.progress ?? 0 };
}
```

---

## Flows (jobs con dependencias)

```typescript
import { FlowProducer } from "bullmq";

@Injectable()
export class OrderService {
  private flowProducer: FlowProducer;

  constructor() {
    this.flowProducer = new FlowProducer({
      connection: { host: "localhost", port: 6379 },
    });
  }

  async processOrder(orderId: string) {
    // Job padre espera a que completen los hijos
    await this.flowProducer.add({
      name: "complete-order",
      queueName: "orders",
      data: { orderId },
      children: [
        {
          name: "charge-payment",
          queueName: "payments",
          data: { orderId },
        },
        {
          name: "reserve-inventory",
          queueName: "inventory",
          data: { orderId },
        },
        {
          name: "send-confirmation",
          queueName: "emails",
          data: { orderId },
        },
      ],
    });
  }
}
```

---

## Rate limiting

```typescript
// Limitar a 10 jobs por segundo
@Processor('emails', {
  limiter: {
    max: 10,
    duration: 1000,
  },
})
export class EmailsProcessor extends WorkerHost {}

// O por queue:
BullModule.registerQueue({
  name: 'emails',
  limiter: {
    max: 100,
    duration: 60000,  // 100 por minuto
  },
}),
```

---

## Concurrencia

```typescript
// Procesar múltiples jobs simultáneamente
@Processor("images", {
  concurrency: 5, // 5 jobs en paralelo
})
export class ImagesProcessor extends WorkerHost {}
```

---

## Gestión de queues (admin)

```typescript
// admin/queues.controller.ts
@Controller("admin/queues")
@UseGuards(AdminGuard)
export class QueuesController {
  constructor(@InjectQueue("emails") private emailQueue: Queue) {}

  @Get("emails/stats")
  async getStats() {
    const [waiting, active, completed, failed] = await Promise.all([
      this.emailQueue.getWaitingCount(),
      this.emailQueue.getActiveCount(),
      this.emailQueue.getCompletedCount(),
      this.emailQueue.getFailedCount(),
    ]);

    return { waiting, active, completed, failed };
  }

  @Get("emails/jobs")
  async getJobs(@Query("status") status: "waiting" | "active" | "failed") {
    return this.emailQueue.getJobs([status], 0, 50);
  }

  @Post("emails/retry/:jobId")
  async retryJob(@Param("jobId") jobId: string) {
    const job = await this.emailQueue.getJob(jobId);
    if (job) await job.retry();
    return { retried: true };
  }

  @Delete("emails/job/:jobId")
  async removeJob(@Param("jobId") jobId: string) {
    const job = await this.emailQueue.getJob(jobId);
    if (job) await job.remove();
    return { removed: true };
  }

  @Post("emails/pause")
  async pause() {
    await this.emailQueue.pause();
    return { paused: true };
  }

  @Post("emails/resume")
  async resume() {
    await this.emailQueue.resume();
    return { resumed: true };
  }

  @Delete("emails/clean")
  async clean() {
    await this.emailQueue.clean(24 * 60 * 60 * 1000, 1000, "completed");
    await this.emailQueue.clean(7 * 24 * 60 * 60 * 1000, 1000, "failed");
    return { cleaned: true };
  }
}
```

---

## Bull Board (UI)

```bash
pnpm add @bull-board/express @bull-board/api
```

```typescript
// main.ts
import { createBullBoard } from "@bull-board/api";
import { BullMQAdapter } from "@bull-board/api/bullMQAdapter";
import { ExpressAdapter } from "@bull-board/express";
import { Queue } from "bullmq";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Obtener las queues
  const emailQueue = app.get<Queue>(getQueueToken("emails"));
  const reportsQueue = app.get<Queue>(getQueueToken("reports"));

  // Configurar Bull Board
  const serverAdapter = new ExpressAdapter();
  serverAdapter.setBasePath("/admin/queues");

  createBullBoard({
    queues: [new BullMQAdapter(emailQueue), new BullMQAdapter(reportsQueue)],
    serverAdapter,
  });

  app.use("/admin/queues", serverAdapter.getRouter());

  await app.listen(3000);
}
// UI disponible en http://localhost:3000/admin/queues
```

---

## Casos de uso comunes

| Tarea               | Queue         | Prioridad      |
| ------------------- | ------------- | -------------- |
| Envío de emails     | emails        | Normal         |
| Password reset      | emails        | Alta (1)       |
| Generar PDF         | reports       | Baja (10)      |
| Resize imágenes     | images        | Normal         |
| Sync con Stripe     | payments      | Alta           |
| Notificaciones push | notifications | Normal         |
| Cleanup de datos    | maintenance   | Muy baja (100) |

---

## Checklist

- [ ] Redis configurado y accesible
- [ ] Queues separadas por dominio (emails, reports, etc.)
- [ ] Reintentos configurados con backoff exponencial
- [ ] Logging de jobs completados/fallidos
- [ ] Alertas para jobs fallidos (Sentry, Slack)
- [ ] Bull Board para monitoreo visual
- [ ] Rate limiting para APIs externas (emails, SMS)
- [ ] Limpieza periódica de jobs completados
