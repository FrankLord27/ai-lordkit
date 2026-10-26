# Health Checks — @nestjs/terminus

> ⚠️ **Prisma 7:** los ejemplos con `new PrismaClient()` / `extends PrismaClient` asumen el setup v7 con **driver adapter** (`@prisma/adapter-pg`) y `prisma.config.ts` — sin adapter NO compilan. Setup completo en `prisma7-docs`.

## ¿Para qué sirven?

Los health checks permiten que sistemas externos (load balancers, Kubernetes, Docker, monitoreo) verifiquen si tu aplicación está funcionando correctamente.

**Casos de uso:**

- **Load balancer**: Solo envía tráfico a instancias saludables
- **Kubernetes**: Reinicia pods que fallan el health check
- **CI/CD**: Verifica que el deploy fue exitoso antes de cambiar tráfico
- **Monitoreo**: Alerta cuando una dependencia falla

---

## Instalación

```bash
pnpm add @nestjs/terminus
```

---

## Configuración básica

```typescript
// health/health.module.ts
import { Module } from "@nestjs/common";
import { TerminusModule } from "@nestjs/terminus";
import { HealthController } from "./health.controller";
import { PrismaHealthIndicator } from "./indicators/prisma.health";
import { RedisHealthIndicator } from "./indicators/redis.health";

@Module({
  imports: [TerminusModule],
  controllers: [HealthController],
  providers: [PrismaHealthIndicator, RedisHealthIndicator],
})
export class HealthModule {}
```

```typescript
// health/health.controller.ts
import { Controller, Get } from "@nestjs/common";
import {
  HealthCheck,
  HealthCheckService,
  MemoryHealthIndicator,
  DiskHealthIndicator,
} from "@nestjs/terminus";
import { PrismaHealthIndicator } from "./indicators/prisma.health";
import { RedisHealthIndicator } from "./indicators/redis.health";

@Controller("health")
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly memory: MemoryHealthIndicator,
    private readonly disk: DiskHealthIndicator,
    private readonly prisma: PrismaHealthIndicator,
    private readonly redis: RedisHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      // Base de datos
      () => this.prisma.isHealthy("database"),

      // Redis
      () => this.redis.isHealthy("redis"),

      // Memoria: alerta si RSS > 500MB
      () => this.memory.checkRSS("memory_rss", 500 * 1024 * 1024),

      // Disco: alerta si > 90% usado
      () =>
        this.disk.checkStorage("disk", {
          path: "/",
          thresholdPercent: 0.9,
        }),
    ]);
  }

  // Endpoint simple para load balancers (no verifica dependencias)
  @Get("live")
  live() {
    return { status: "ok" };
  }

  // Endpoint completo para Kubernetes readiness probe
  @Get("ready")
  @HealthCheck()
  ready() {
    return this.health.check([
      () => this.prisma.isHealthy("database"),
      () => this.redis.isHealthy("redis"),
    ]);
  }
}
```

---

## Indicadores personalizados

### Prisma Health Indicator

```typescript
// health/indicators/prisma.health.ts
import { Injectable } from "@nestjs/common";
import {
  HealthIndicator,
  HealthIndicatorResult,
  HealthCheckError,
} from "@nestjs/terminus";
import { PrismaService } from "../../prisma/prisma.service";

@Injectable()
export class PrismaHealthIndicator extends HealthIndicator {
  constructor(private readonly prisma: PrismaService) {
    super();
  }

  async isHealthy(key: string): Promise<HealthIndicatorResult> {
    try {
      // Query simple para verificar conexión
      await this.prisma.$queryRaw`SELECT 1`;
      return this.getStatus(key, true);
    } catch (error) {
      throw new HealthCheckError(
        "Prisma health check failed",
        this.getStatus(key, false, { message: error.message }),
      );
    }
  }
}
```

### Redis Health Indicator

```typescript
// health/indicators/redis.health.ts
import { Injectable, Inject } from "@nestjs/common";
import {
  HealthIndicator,
  HealthIndicatorResult,
  HealthCheckError,
} from "@nestjs/terminus";
import { CACHE_MANAGER } from "@nestjs/cache-manager";
import { Cache } from "cache-manager";

@Injectable()
export class RedisHealthIndicator extends HealthIndicator {
  constructor(@Inject(CACHE_MANAGER) private readonly cache: Cache) {
    super();
  }

  async isHealthy(key: string): Promise<HealthIndicatorResult> {
    try {
      // Escribir y leer para verificar que Redis funciona
      const testKey = "health:ping";
      const testValue = Date.now().toString();

      await this.cache.set(testKey, testValue, 10000);
      const result = await this.cache.get(testKey);

      if (result !== testValue) {
        throw new Error("Redis read/write mismatch");
      }

      return this.getStatus(key, true);
    } catch (error) {
      throw new HealthCheckError(
        "Redis health check failed",
        this.getStatus(key, false, { message: error.message }),
      );
    }
  }
}
```

### Servicio Externo (API de terceros)

```typescript
// health/indicators/external-api.health.ts
import { Injectable } from "@nestjs/common";
import { HttpService } from "@nestjs/axios";
import {
  HealthIndicator,
  HealthIndicatorResult,
  HealthCheckError,
} from "@nestjs/terminus";
import { firstValueFrom, timeout, catchError } from "rxjs";

@Injectable()
export class ExternalApiHealthIndicator extends HealthIndicator {
  constructor(private readonly http: HttpService) {
    super();
  }

  async isHealthy(key: string, url: string): Promise<HealthIndicatorResult> {
    try {
      const response = await firstValueFrom(
        this.http.get(url).pipe(
          timeout(5000), // Timeout de 5 segundos
          catchError((err) => {
            throw new Error(`Request failed: ${err.message}`);
          }),
        ),
      );

      const isHealthy = response.status >= 200 && response.status < 300;

      if (isHealthy) {
        return this.getStatus(key, true, {
          statusCode: response.status,
          responseTime: response.headers["x-response-time"],
        });
      }

      throw new Error(`Unhealthy status: ${response.status}`);
    } catch (error) {
      throw new HealthCheckError(
        `${key} health check failed`,
        this.getStatus(key, false, { message: error.message }),
      );
    }
  }
}
```

---

## Respuesta del endpoint

### Cuando todo está bien (HTTP 200):

```json
{
  "status": "ok",
  "info": {
    "database": { "status": "up" },
    "redis": { "status": "up" },
    "memory_rss": { "status": "up" },
    "disk": { "status": "up" }
  },
  "error": {},
  "details": {
    "database": { "status": "up" },
    "redis": { "status": "up" },
    "memory_rss": { "status": "up" },
    "disk": { "status": "up" }
  }
}
```

### Cuando algo falla (HTTP 503):

```json
{
  "status": "error",
  "info": {
    "memory_rss": { "status": "up" },
    "disk": { "status": "up" }
  },
  "error": {
    "database": {
      "status": "down",
      "message": "Connection refused"
    },
    "redis": {
      "status": "down",
      "message": "ECONNREFUSED"
    }
  },
  "details": {
    "database": { "status": "down", "message": "Connection refused" },
    "redis": { "status": "down", "message": "ECONNREFUSED" },
    "memory_rss": { "status": "up" },
    "disk": { "status": "up" }
  }
}
```

---

## Configuración en Kubernetes

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: api
          image: myapp/api:latest
          ports:
            - containerPort: 3001
          # Liveness: ¿está vivo el proceso?
          livenessProbe:
            httpGet:
              path: /health/live
              port: 3001
            initialDelaySeconds: 10
            periodSeconds: 15
            failureThreshold: 3
          # Readiness: ¿puede recibir tráfico?
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 3001
            initialDelaySeconds: 5
            periodSeconds: 10
            failureThreshold: 3
```

**Diferencia importante:**

- **Liveness**: Si falla, Kubernetes reinicia el pod
- **Readiness**: Si falla, Kubernetes deja de enviar tráfico pero NO reinicia

---

## Configuración en Docker Compose

```yaml
# docker-compose.yml
services:
  api:
    image: myapp/api:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  postgres:
    image: postgres:16
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
```

---

## Excluir del auth (importante)

Los endpoints de health deben ser públicos:

```typescript
// auth/guards/jwt-auth.guard.ts
@Injectable()
export class JwtAuthGuard extends AuthGuard("jwt") {
  constructor(private reflector: Reflector) {
    super();
  }

  canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>("isPublic", [
      context.getHandler(),
      context.getClass(),
    ]);

    if (isPublic) return true;

    return super.canActivate(context);
  }
}

// health/health.controller.ts
import { Public } from "../auth/decorators/public.decorator";

@Controller("health")
@Public() // Todos los endpoints de este controller son públicos
export class HealthController {
  // ...
}
```

---

## Graceful Shutdown

Cuando tu app recibe SIGTERM (shutdown), debe:

1. Dejar de aceptar nuevas conexiones
2. Terminar requests en progreso
3. Cerrar conexiones a DB/Redis
4. Salir limpiamente

```typescript
// main.ts
import { NestFactory } from "@nestjs/core";
import { AppModule } from "./app.module";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Habilitar shutdown hooks
  app.enableShutdownHooks();

  await app.listen(3001);
}
bootstrap();
```

```typescript
// prisma/prisma.service.ts
import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient } from "../generated/prisma/client.js";

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleDestroy {
  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

---

## Monitoreo del health endpoint

```typescript
// Agregar métricas de tiempo de respuesta
@Get()
@HealthCheck()
async check() {
  const start = Date.now();

  const result = await this.health.check([
    () => this.prisma.isHealthy('database'),
    () => this.redis.isHealthy('redis'),
  ]);

  // Log para monitoreo
  const duration = Date.now() - start;
  if (duration > 1000) {
    this.logger.warn(`Health check slow: ${duration}ms`);
  }

  return result;
}
```

---

## Checklist de implementación

- [ ] Instalar `@nestjs/terminus`
- [ ] Crear `HealthModule` con controller y providers
- [ ] Implementar `PrismaHealthIndicator`
- [ ] Implementar `RedisHealthIndicator`
- [ ] Agregar checks de memoria y disco
- [ ] Marcar endpoints como `@Public()`
- [ ] Configurar `livenessProbe` y `readinessProbe` en K8s/Docker
- [ ] Habilitar `app.enableShutdownHooks()`
- [ ] Implementar `onModuleDestroy` en PrismaService
- [ ] Agregar health checks de APIs externas si las hay
