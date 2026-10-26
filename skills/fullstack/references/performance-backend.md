# Performance en NestJS — Backend

---

## Compresión de respuestas HTTP

```typescript
// pnpm add compression @types/compression
import compression from "compression";

// main.ts — antes de cualquier middleware
app.use(
  compression({
    // Comprimir respuestas > 1KB
    threshold: 1024,
    // Nivel de compresión: 1 (rápido) - 9 (máximo). 6 es el balance ideal.
    level: 6,
    // Solo comprimir estos tipos de contenido
    filter: (req, res) => {
      const contentType = (res.getHeader("Content-Type") as string) ?? "";
      return /json|text|javascript|css/.test(contentType);
    },
  }),
);

// Impacto típico: respuestas JSON se reducen 60-80% en tamaño
// Una respuesta de 100KB → ~20KB después de gzip
```

---

## Serialización — retornar solo lo necesario

```typescript
// Interceptor de serialización con class-transformer
// Permite usar @Exclude() y @Expose() en los DTOs de respuesta

import { ClassSerializerInterceptor } from "@nestjs/common";

// main.ts
app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));
```

```typescript
// dto/item-response.dto.ts
import { Exclude, Expose, Transform } from "class-transformer";

export class ItemResponseDto {
  @Expose()
  id: string;

  @Expose()
  name: string;

  @Expose()
  @Transform(({ value }) => Number(value)) // Decimal → number para JSON
  price: number;

  @Exclude() // Nunca aparece en la respuesta
  internalCost: number;

  @Exclude()
  deletedAt: Date;

  @Expose()
  @Transform(({ value }) => value?.toISOString())
  createdAt: Date;
}
```

---

## Profiling de endpoints lentos

```typescript
// Interceptor de performance — loguea endpoints que tardan más del umbral
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  Logger,
} from "@nestjs/common";
import { Observable } from "rxjs";
import { tap } from "rxjs/operators";

const SLOW_REQUEST_THRESHOLD_MS = 500; // Alertar si tarda más de 500ms

@Injectable()
export class PerformanceInterceptor implements NestInterceptor {
  private readonly logger = new Logger("Performance");

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req = context.switchToHttp().getRequest();
    const start = Date.now();

    return next.handle().pipe(
      tap(() => {
        const duration = Date.now() - start;

        if (duration > SLOW_REQUEST_THRESHOLD_MS) {
          this.logger.warn(
            `Slow request: ${req.method} ${req.url} → ${duration}ms`,
          );
        }
      }),
    );
  }
}

// Registrar globalmente
app.useGlobalInterceptors(new PerformanceInterceptor());
```

---

## Lazy loading de módulos — reducir tiempo de arranque

```typescript
// En apps con muchos módulos, usar lazy loading para módulos pesados
// que no se necesitan en cada request

// ❌ Sin lazy loading — todos los módulos cargan al arrancar
@Module({
  imports: [
    ReportsModule, // Módulo pesado, solo usado en /reports
    AdminModule, // Solo usado por admins
    AnalyticsModule, // Solo para dashboard
  ],
})
// ✅ Con lazy loading — solo carga cuando se necesita
@Module({})
export class AppModule {
  constructor(private lazyModuleLoader: LazyModuleLoader) {}
}

@Controller("reports")
export class ReportsController {
  constructor(private lazyModuleLoader: LazyModuleLoader) {}

  @Get()
  async getReport() {
    // El módulo solo carga cuando se accede a este endpoint
    const { ReportsModule } = await import("./reports/reports.module");
    const moduleRef = await this.lazyModuleLoader.load(() => ReportsModule);
    const service = moduleRef.get(ReportsService);
    return service.generate();
  }
}
```

---

## Streaming de respuestas grandes

```typescript
// Para respuestas grandes (exports, archivos, reportes)
// Streaming evita cargar todo en memoria antes de enviar

import { Response } from 'express';
import { Readable } from 'stream';

@Get('export/bookings')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)
async exportBookings(@Res() res: Response) {
  res.setHeader('Content-Type', 'text/csv');
  res.setHeader('Content-Disposition', 'attachment; filename=bookings.csv');

  // Header del CSV
  res.write('id,userId,carId,pickupDate,returnDate,totalPrice,status\n');

  // Cursor de Prisma — procesa en chunks sin cargar todo en memoria
  const cursor = await this.prisma.booking.findMany({
    take: 1000,
    orderBy: { createdAt: 'asc' },
  });

  let lastId: string | undefined;

  while (true) {
    const batch = await this.prisma.booking.findMany({
      take: 100,
      cursor: lastId ? { id: lastId } : undefined,
      skip: lastId ? 1 : 0,
      orderBy: { id: 'asc' },
    });

    if (batch.length === 0) break;

    for (const booking of batch) {
      res.write(
        `${booking.id},${booking.userId},${booking.carId},` +
        `${booking.pickupDate.toISOString()},${booking.returnDate.toISOString()},` +
        `${booking.totalPrice},${booking.status}\n`,
      );
    }

    lastId = batch[batch.length - 1].id;
  }

  res.end();
}
```

---

## Operaciones en paralelo — Promise.all

```typescript
// ❌ Secuencial — espera cada operación antes de empezar la siguiente
// Si cada una tarda 100ms → total 300ms
const user = await this.usersService.findById(userId);
const bookings = await this.bookingsService.findByUserId(userId);
const preferences = await this.preferencesService.findByUserId(userId);

// ✅ Paralelo — todas empiezan al mismo tiempo
// Si cada una tarda 100ms → total ~100ms
const [user, bookings, preferences] = await Promise.all([
  this.usersService.findById(userId),
  this.bookingsService.findByUserId(userId),
  this.preferencesService.findByUserId(userId),
]);

// ⚠️ Usar Promise.all solo cuando las operaciones son independientes
// Si B depende del resultado de A, deben ser secuenciales
```

---

## Response Caching a nivel de HTTP — Cache-Control headers

```typescript
// Interceptor para agregar headers de cache HTTP
// Permite que el browser y CDN cacheen las respuestas

import { SetMetadata } from '@nestjs/common';

// Decorador para marcar endpoints cacheables
export const CacheControl = (maxAge: number) =>
  SetMetadata('cache-control', maxAge);

@Injectable()
export class CacheControlInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const maxAge = this.reflector.get<number>('cache-control', context.getHandler());

    return next.handle().pipe(
      tap(() => {
        const res = context.switchToHttp().getResponse();
        if (maxAge) {
          res.setHeader('Cache-Control', `public, max-age=${maxAge}, stale-while-revalidate=${maxAge * 2}`);
        } else {
          // Por defecto: no cachear en el browser (datos dinámicos)
          res.setHeader('Cache-Control', 'no-store');
        }
      }),
    );
  }
}

// Uso en controller
@Get('locations')
@CacheControl(3600) // Browser y CDN cachean por 1 hora
async getLocations() {
  return this.locationsService.findAll();
}

@Get('profile')
@UseGuards(JwtAuthGuard)
// Sin @CacheControl → no-store por defecto (datos privados)
async getProfile(@CurrentUser() user: UserPayload) {
  return this.usersService.findById(user.sub);
}
```

---

## Detectar memory leaks

```typescript
// Monitorear uso de memoria periódicamente
// Un leak se ve como memoria que crece y nunca baja

@Injectable()
export class MemoryMonitorService implements OnModuleInit {
  private readonly logger = new Logger("MemoryMonitor");
  private readonly THRESHOLD_MB = 512; // Alertar si supera 512MB

  onModuleInit() {
    setInterval(() => {
      const { heapUsed, heapTotal, rss } = process.memoryUsage();
      const heapUsedMb = Math.round(heapUsed / 1024 / 1024);
      const rssMb = Math.round(rss / 1024 / 1024);

      this.logger.debug(`Memory: heap ${heapUsedMb}MB, rss ${rssMb}MB`);

      if (rssMb > this.THRESHOLD_MB) {
        this.logger.warn(`Alto uso de memoria: ${rssMb}MB`);
        // Enviar alerta a Sentry o Slack
      }
    }, 30_000); // Cada 30 segundos
  }
}

// Causas comunes de memory leaks en NestJS:
// 1. Event listeners que no se eliminan (usar onModuleDestroy para limpiar)
// 2. Intervalos que no se limpian (guardar referencia y clearInterval en destroy)
// 3. Cache en memoria que crece sin límite (usar Redis en lugar de Map)
// 4. Conexiones que no se cierran (prisma.$disconnect en onModuleDestroy)
```
