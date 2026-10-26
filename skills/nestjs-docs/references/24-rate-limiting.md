# Rate Limiting — @nestjs/throttler

## ¿Para qué sirve?

Limitar la cantidad de requests que un cliente puede hacer en un período de tiempo:

- Prevenir ataques de fuerza bruta en login
- Proteger APIs públicas de abuso
- Evitar que un usuario consuma todos los recursos
- Cumplir con límites de APIs de terceros

---

## Instalación

```bash
pnpm add @nestjs/throttler
```

---

## Configuración básica

```typescript
// app.module.ts
import { Module } from "@nestjs/common";
import { ThrottlerModule, ThrottlerGuard } from "@nestjs/throttler";
import { APP_GUARD } from "@nestjs/core";

@Module({
  imports: [
    ThrottlerModule.forRoot([
      {
        name: "short",
        ttl: 1000, // 1 segundo
        limit: 3, // máximo 3 requests
      },
      {
        name: "medium",
        ttl: 10000, // 10 segundos
        limit: 20, // máximo 20 requests
      },
      {
        name: "long",
        ttl: 60000, // 1 minuto
        limit: 100, // máximo 100 requests
      },
    ]),
  ],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard, // Aplica globalmente
    },
  ],
})
export class AppModule {}
```

---

## Configuración con Redis (para múltiples instancias)

```bash
pnpm add @nestjs/throttler-storage-redis ioredis
```

```typescript
// app.module.ts
import { ThrottlerModule } from "@nestjs/throttler";
import { ThrottlerStorageRedisService } from "@nestjs/throttler-storage-redis";
import Redis from "ioredis";

@Module({
  imports: [
    ThrottlerModule.forRootAsync({
      useFactory: () => ({
        throttlers: [
          { name: "short", ttl: 1000, limit: 3 },
          { name: "medium", ttl: 10000, limit: 20 },
          { name: "long", ttl: 60000, limit: 100 },
        ],
        storage: new ThrottlerStorageRedisService(
          new Redis({
            host: process.env.REDIS_HOST ?? "localhost",
            port: parseInt(process.env.REDIS_PORT ?? "6379"),
            password: process.env.REDIS_PASSWORD,
          }),
        ),
      }),
    }),
  ],
})
export class AppModule {}
```

---

## Decoradores

### Sobrescribir límites por endpoint

```typescript
import { Throttle, SkipThrottle } from "@nestjs/throttler";

@Controller("auth")
export class AuthController {
  // Login: más restrictivo (5 intentos por minuto)
  @Post("login")
  @Throttle({ short: { limit: 5, ttl: 60000 } })
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  // Refresh token: menos restrictivo
  @Post("refresh")
  @Throttle({ short: { limit: 10, ttl: 60000 } })
  refresh(@Body() dto: RefreshDto) {
    return this.authService.refresh(dto);
  }

  // Health check: sin límite
  @Get("health")
  @SkipThrottle()
  health() {
    return { status: "ok" };
  }
}
```

### Saltar throttling para todo un controller

```typescript
@Controller("internal")
@SkipThrottle() // Sin rate limiting para endpoints internos
export class InternalController {
  // ...
}

// O solo saltar throttlers específicos
@Controller("api")
@SkipThrottle({ short: true }) // Solo salta 'short', aplica 'medium' y 'long'
export class ApiController {
  // ...
}
```

---

## Identificación de cliente personalizada

Por defecto, se identifica por IP. Puedes cambiarlo:

```typescript
// common/guards/throttler-behind-proxy.guard.ts
import { ThrottlerGuard } from "@nestjs/throttler";
import { Injectable, ExecutionContext } from "@nestjs/common";

@Injectable()
export class ThrottlerBehindProxyGuard extends ThrottlerGuard {
  // Identificar por IP real detrás de proxy/load balancer
  protected async getTracker(req: Record<string, any>): Promise<string> {
    return req.ips.length ? req.ips[0] : req.ip;
  }
}

// O identificar por usuario autenticado
@Injectable()
export class ThrottlerByUserGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    // Si está autenticado, usar userId; si no, usar IP
    return req.user?.sub ?? req.ip;
  }
}
```

```typescript
// app.module.ts
@Module({
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerBehindProxyGuard,
    },
  ],
})
export class AppModule {}
```

---

## Límites diferentes por rol

```typescript
// common/guards/role-throttler.guard.ts
import { ThrottlerGuard, ThrottlerException } from "@nestjs/throttler";
import { Injectable, ExecutionContext } from "@nestjs/common";

@Injectable()
export class RoleThrottlerGuard extends ThrottlerGuard {
  protected async handleRequest(
    context: ExecutionContext,
    limit: number,
    ttl: number,
  ): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const user = request.user;

    // Admins: sin límite
    if (user?.role === "ADMIN") {
      return true;
    }

    // Premium: límite más alto
    if (user?.plan === "PREMIUM") {
      limit = limit * 5; // 5x más requests
    }

    return super.handleRequest(context, limit, ttl);
  }
}
```

---

## Rate limiting por tenant (multi-tenant)

```typescript
// common/guards/tenant-throttler.guard.ts
import { ThrottlerGuard } from "@nestjs/throttler";
import { Injectable, ExecutionContext } from "@nestjs/common";

@Injectable()
export class TenantThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, any>): Promise<string> {
    // Combinar tenantId + IP para limitar por tenant
    const tenantId = req.tenantId ?? "unknown";
    const ip = req.ip;
    return `${tenantId}:${ip}`;
  }

  protected async handleRequest(
    context: ExecutionContext,
    limit: number,
    ttl: number,
  ): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const tenant = request.tenant;

    // Aplicar límite según el plan del tenant
    if (tenant?.plan === "ENTERPRISE") {
      limit = limit * 10;
    } else if (tenant?.plan === "PRO") {
      limit = limit * 3;
    }

    return super.handleRequest(context, limit, ttl);
  }
}
```

---

## Headers de respuesta

Cuando el throttler está activo, agrega estos headers:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1699012345
```

Cuando se excede el límite:

```
HTTP 429 Too Many Requests
Retry-After: 60
```

### Personalizar respuesta de error

```typescript
// common/filters/throttler-exception.filter.ts
import { ExceptionFilter, Catch, ArgumentsHost } from "@nestjs/common";
import { ThrottlerException } from "@nestjs/throttler";
import { Response } from "express";

@Catch(ThrottlerException)
export class ThrottlerExceptionFilter implements ExceptionFilter {
  catch(exception: ThrottlerException, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();

    response.status(429).json({
      statusCode: 429,
      error: "TOO_MANY_REQUESTS",
      message:
        "Has excedido el límite de requests. Intenta de nuevo más tarde.",
      retryAfter: response.getHeader("Retry-After"),
    });
  }
}
```

---

## Límites recomendados por tipo de endpoint

| Endpoint           | Límite | TTL    | Razón                 |
| ------------------ | ------ | ------ | --------------------- |
| Login              | 5      | 1 min  | Prevenir fuerza bruta |
| Registro           | 3      | 5 min  | Prevenir spam         |
| Forgot password    | 3      | 15 min | Prevenir abuso        |
| API pública        | 60     | 1 min  | Uso normal            |
| API autenticada    | 100    | 1 min  | Usuarios legítimos    |
| Uploads            | 10     | 1 min  | Recursos costosos     |
| Webhooks entrantes | 100    | 1 min  | Servicios externos    |

---

## Testing

```typescript
describe("Rate Limiting", () => {
  it("should block after limit exceeded", async () => {
    // Hacer 5 requests (límite de login)
    for (let i = 0; i < 5; i++) {
      await request(app.getHttpServer())
        .post("/auth/login")
        .send({ email: "test@test.com", password: "wrong" })
        .expect(401);
    }

    // El 6to request debe ser bloqueado
    const response = await request(app.getHttpServer())
      .post("/auth/login")
      .send({ email: "test@test.com", password: "wrong" })
      .expect(429);

    expect(response.body.error).toBe("TOO_MANY_REQUESTS");
  });
});
```

---

## Checklist de implementación

- [ ] Instalar `@nestjs/throttler`
- [ ] Configurar múltiples throttlers (short, medium, long)
- [ ] Agregar `ThrottlerGuard` como APP_GUARD
- [ ] Usar Redis storage si hay múltiples instancias
- [ ] Personalizar `getTracker` si estás detrás de proxy
- [ ] Límites más estrictos en login/registro
- [ ] `@SkipThrottle()` en health checks y webhooks internos
- [ ] Personalizar respuesta 429
- [ ] Documentar límites en API docs
