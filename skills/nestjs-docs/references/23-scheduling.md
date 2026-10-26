# Task Scheduling — @nestjs/schedule

## ¿Para qué sirve?

Ejecutar tareas automáticamente en intervalos o momentos específicos:

- Limpiar tokens expirados cada hora
- Enviar reportes diarios a las 8am
- Sincronizar datos con API externa cada 5 minutos
- Procesar cola de emails pendientes

---

## Instalación

```bash
pnpm add @nestjs/schedule
```

---

## Configuración

```typescript
// app.module.ts
import { Module } from "@nestjs/common";
import { ScheduleModule } from "@nestjs/schedule";

@Module({
  imports: [ScheduleModule.forRoot()],
})
export class AppModule {}
```

---

## Cron Jobs

### Sintaxis Cron

```
┌────────────── segundo (0-59, opcional)
│ ┌──────────── minuto (0-59)
│ │ ┌────────── hora (0-23)
│ │ │ ┌──────── día del mes (1-31)
│ │ │ │ ┌────── mes (1-12)
│ │ │ │ │ ┌──── día de la semana (0-6, domingo=0)
│ │ │ │ │ │
* * * * * *
```

### Ejemplos comunes

| Expresión     | Cuándo ejecuta               |
| ------------- | ---------------------------- |
| `0 * * * *`   | Cada hora, minuto 0          |
| `*/5 * * * *` | Cada 5 minutos               |
| `0 8 * * *`   | Diario a las 8:00am          |
| `0 0 * * 0`   | Domingos a medianoche        |
| `0 9 * * 1-5` | Lunes a viernes a las 9:00am |
| `0 0 1 * *`   | Primer día de cada mes       |
| `0 */2 * * *` | Cada 2 horas                 |

### Constantes predefinidas

```typescript
import { CronExpression } from "@nestjs/schedule";

CronExpression.EVERY_MINUTE; // * * * * *
CronExpression.EVERY_5_MINUTES; // */5 * * * *
CronExpression.EVERY_HOUR; // 0 * * * *
CronExpression.EVERY_DAY_AT_MIDNIGHT; // 0 0 * * *
CronExpression.EVERY_WEEK; // 0 0 * * 0
CronExpression.EVERY_1ST_DAY_OF_MONTH_AT_MIDNIGHT; // 0 0 1 * *
```

---

## Implementación

### Servicio con Cron Jobs

```typescript
// tasks/tasks.service.ts
import { Injectable, Logger } from "@nestjs/common";
import { Cron, CronExpression, Interval, Timeout } from "@nestjs/schedule";
import { PrismaService } from "../prisma/prisma.service";

@Injectable()
export class TasksService {
  private readonly logger = new Logger(TasksService.name);

  constructor(private readonly prisma: PrismaService) {}

  // Cada hora: limpiar refresh tokens expirados
  @Cron(CronExpression.EVERY_HOUR)
  async cleanExpiredTokens() {
    this.logger.log("Limpiando refresh tokens expirados...");

    const result = await this.prisma.refreshToken.deleteMany({
      where: {
        expiresAt: { lt: new Date() },
      },
    });

    this.logger.log(`Eliminados ${result.count} tokens expirados`);
  }

  // Diario a las 2am: limpiar soft-deleted records viejos
  @Cron("0 2 * * *")
  async cleanDeletedRecords() {
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    this.logger.log("Limpiando registros eliminados hace más de 30 días...");

    // Prisma transaction para múltiples tablas
    await this.prisma.$transaction([
      this.prisma.ticket.deleteMany({
        where: { deletedAt: { lt: thirtyDaysAgo } },
      }),
      this.prisma.comment.deleteMany({
        where: { deletedAt: { lt: thirtyDaysAgo } },
      }),
    ]);
  }

  // Lunes a las 9am: enviar reporte semanal
  @Cron("0 9 * * 1", {
    name: "weekly-report",
    timeZone: "America/Santo_Domingo", // Zona horaria específica
  })
  async sendWeeklyReport() {
    this.logger.log("Generando reporte semanal...");
    // Lógica de reporte
  }

  // Cada 5 minutos: sincronizar con API externa
  @Cron(CronExpression.EVERY_5_MINUTES)
  async syncExternalData() {
    this.logger.log("Sincronizando datos externos...");
    // Lógica de sincronización
  }
}
```

### Intervalos (alternativa más simple)

```typescript
// Cada 30 segundos
@Interval(30000)
async checkPendingJobs() {
  // Ejecuta cada 30 segundos desde que la app inicia
}

// Con nombre para poder cancelar
@Interval('process-queue', 10000)
async processQueue() {
  // Cada 10 segundos
}
```

### Timeout (ejecutar una vez después de delay)

```typescript
// 5 segundos después de iniciar la app
@Timeout(5000)
async onceAfterStartup() {
  this.logger.log('App iniciada, ejecutando tarea inicial...');
}

// Con nombre
@Timeout('initial-sync', 10000)
async initialSync() {
  // 10 segundos después del inicio
}
```

---

## Control dinámico de jobs

```typescript
// tasks/tasks.service.ts
import { Injectable } from "@nestjs/common";
import { SchedulerRegistry, CronJob } from "@nestjs/schedule";

@Injectable()
export class TasksService {
  constructor(private readonly schedulerRegistry: SchedulerRegistry) {}

  // Pausar un job
  pauseJob(name: string) {
    const job = this.schedulerRegistry.getCronJob(name);
    job.stop();
    this.logger.log(`Job "${name}" pausado`);
  }

  // Reanudar un job
  resumeJob(name: string) {
    const job = this.schedulerRegistry.getCronJob(name);
    job.start();
    this.logger.log(`Job "${name}" reanudado`);
  }

  // Crear job dinámicamente
  createDynamicJob(name: string, cronExpression: string, callback: () => void) {
    const job = new CronJob(cronExpression, callback);
    this.schedulerRegistry.addCronJob(name, job);
    job.start();
  }

  // Eliminar job
  deleteJob(name: string) {
    this.schedulerRegistry.deleteCronJob(name);
    this.logger.log(`Job "${name}" eliminado`);
  }

  // Listar todos los jobs
  listJobs() {
    const jobs = this.schedulerRegistry.getCronJobs();
    jobs.forEach((value, key) => {
      const next = value.nextDate();
      this.logger.log(`Job: ${key} → Próxima ejecución: ${next}`);
    });
  }
}
```

---

## Prevenir ejecución simultánea

Si un job tarda más que su intervalo, puede ejecutarse múltiples veces en paralelo.

```typescript
@Injectable()
export class TasksService {
  private isRunning = false;

  @Cron(CronExpression.EVERY_MINUTE)
  async processHeavyTask() {
    if (this.isRunning) {
      this.logger.warn("Tarea anterior aún en ejecución, saltando...");
      return;
    }

    this.isRunning = true;
    try {
      // Tarea que puede tardar más de 1 minuto
      await this.heavyProcessing();
    } finally {
      this.isRunning = false;
    }
  }
}
```

### Con lock distribuido (múltiples instancias)

```typescript
import { Inject } from "@nestjs/common";
import { CACHE_MANAGER } from "@nestjs/cache-manager";
import { Cache } from "cache-manager";

@Injectable()
export class TasksService {
  constructor(@Inject(CACHE_MANAGER) private cache: Cache) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async syncData() {
    const lockKey = "lock:sync-data";
    const lockValue = `${process.pid}-${Date.now()}`;

    // Intentar adquirir lock (expira en 5 minutos)
    const acquired = await this.acquireLock(lockKey, lockValue, 5 * 60 * 1000);
    if (!acquired) {
      this.logger.log("Otra instancia está ejecutando esta tarea");
      return;
    }

    try {
      await this.doSyncData();
    } finally {
      await this.releaseLock(lockKey, lockValue);
    }
  }

  private async acquireLock(
    key: string,
    value: string,
    ttl: number,
  ): Promise<boolean> {
    const existing = await this.cache.get(key);
    if (existing) return false;

    await this.cache.set(key, value, ttl);
    return true;
  }

  private async releaseLock(key: string, value: string): Promise<void> {
    const current = await this.cache.get(key);
    if (current === value) {
      await this.cache.del(key);
    }
  }
}
```

---

## Jobs por tenant (multi-tenant)

```typescript
@Injectable()
export class TenantTasksService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly schedulerRegistry: SchedulerRegistry,
  ) {}

  // Al iniciar: crear jobs para cada tenant activo
  async onModuleInit() {
    const tenants = await this.prisma.tenant.findMany({
      where: { isActive: true },
    });

    for (const tenant of tenants) {
      this.createTenantJob(tenant);
    }
  }

  createTenantJob(tenant: Tenant) {
    const jobName = `report-${tenant.id}`;

    // Usar el cron configurado por el tenant
    const job = new CronJob(tenant.reportCron ?? "0 8 * * *", () => {
      this.generateReport(tenant.id);
    });

    this.schedulerRegistry.addCronJob(jobName, job);
    job.start();
  }

  async generateReport(tenantId: string) {
    this.logger.log(`Generando reporte para tenant ${tenantId}`);
    // Lógica de reporte
  }
}
```

---

## Deshabilitar en tests

```typescript
// app.module.ts
@Module({
  imports: [ScheduleModule.forRoot()],
})
export class AppModule {}

// test/setup.ts
beforeAll(() => {
  // Deshabilitar scheduler en tests
  jest.mock("@nestjs/schedule", () => ({
    ...jest.requireActual("@nestjs/schedule"),
    Cron: () => () => {},
    Interval: () => () => {},
    Timeout: () => () => {},
  }));
});
```

---

## Logging y monitoreo

```typescript
@Injectable()
export class TasksService {
  private readonly logger = new Logger(TasksService.name);

  @Cron(CronExpression.EVERY_HOUR)
  async cleanExpiredTokens() {
    const startTime = Date.now();

    try {
      this.logger.log("Iniciando limpieza de tokens...");

      const result = await this.prisma.refreshToken.deleteMany({
        where: { expiresAt: { lt: new Date() } },
      });

      const duration = Date.now() - startTime;
      this.logger.log(
        `Limpieza completada: ${result.count} tokens en ${duration}ms`,
      );

      // Métricas para Prometheus (opcional)
      // this.metrics.taskDuration.observe({ task: 'cleanTokens' }, duration);
      // this.metrics.tokensDeleted.inc(result.count);
    } catch (error) {
      this.logger.error("Error en limpieza de tokens", error.stack);
      // Reportar a Sentry
      // Sentry.captureException(error);
    }
  }
}
```

---

## Checklist de implementación

- [ ] Instalar `@nestjs/schedule`
- [ ] Agregar `ScheduleModule.forRoot()` a imports
- [ ] Crear `TasksService` con los jobs necesarios
- [ ] Definir zona horaria si es relevante
- [ ] Implementar prevención de ejecución simultánea
- [ ] Agregar lock distribuido si hay múltiples instancias
- [ ] Logging con tiempos de ejecución
- [ ] Deshabilitar en ambiente de test
- [ ] Monitorear jobs en producción
