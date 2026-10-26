# NestJS — Middleware

**Fuente:** https://docs.nestjs.com/middleware

## Concepto

El middleware es una función que se ejecuta **antes** del route handler, con acceso directo a los objetos `request` y `response`. Se ejecuta ANTES de guards, interceptors y pipes.

## Cuándo usar Middleware vs Guard vs Interceptor

|             | Acceso a req/res | Sabe qué handler se ejecuta | Puede modificar response |
| ----------- | ---------------- | --------------------------- | ------------------------ |
| Middleware  | ✅               | ❌                          | ✅ (parcial)             |
| Guard       | ✅ (via context) | ✅                          | ❌                       |
| Interceptor | ✅ (via context) | ✅                          | ✅                       |

**Usar Middleware para:** logging, CORS, autenticación basic, modificar headers, compression.

## Middleware como clase

```typescript
import { Injectable, NestMiddleware } from "@nestjs/common";
import { Request, Response, NextFunction } from "express";

@Injectable()
export class LoggerMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    console.log(`[${req.method}] ${req.url}`);
    next(); // IMPORTANTE: llamar next() para continuar
  }
}
```

## Middleware como función (funcional middleware)

```typescript
export function logger(req: Request, res: Response, next: NextFunction) {
  console.log(`Request...`);
  next();
}
```

> ✅ Preferir functional middleware cuando no necesita DI (más ligero).

## Aplicar middleware en módulo

```typescript
import { Module, NestModule, MiddlewareConsumer } from "@nestjs/common";

@Module({ imports: [CatsModule] })
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(LoggerMiddleware).forRoutes("cats"); // solo para /cats
  }
}
```

## Configuraciones avanzadas de forRoutes

```typescript
// Por método HTTP específico
consumer
  .apply(LoggerMiddleware)
  .forRoutes({ path: "cats", method: RequestMethod.GET });

// Por controller
consumer.apply(LoggerMiddleware).forRoutes(CatsController);

// Múltiples rutas
consumer.apply(LoggerMiddleware).forRoutes("cats", "dogs");

// Excluir rutas
consumer
  .apply(LoggerMiddleware)
  .exclude({ path: "cats", method: RequestMethod.GET }, "cats/(.*)")
  .forRoutes(CatsController);

// Todos los controllers
consumer.apply(LoggerMiddleware).forRoutes("*");
```

## Múltiples middleware (se ejecutan en orden)

```typescript
consumer
  .apply(CorsMiddleware, LoggerMiddleware, AuthMiddleware)
  .forRoutes(CatsController);
```

## Global middleware

```typescript
// main.ts
const app = await NestFactory.create(AppModule);
app.use(LoggerMiddleware); // instancia funcional
app.use(new LoggerMiddleware()); // clase instanciada manualmente
```

> ⚠️ Global middleware vía `app.use()` NO puede inyectar dependencias. Para DI, usa `MiddlewareConsumer` en módulos.

## Middleware con DI (acceso a providers)

```typescript
@Injectable()
export class AuthMiddleware implements NestMiddleware {
  constructor(private readonly usersService: UsersService) {}

  use(req: Request, res: Response, next: NextFunction) {
    const token = req.headers.authorization;
    if (token) {
      req["user"] = this.usersService.validateToken(token);
    }
    next();
  }
}
```

## Ejemplo real: Request ID middleware

```typescript
import { Injectable, NestMiddleware } from "@nestjs/common";
import { randomUUID } from "crypto";

@Injectable()
export class RequestIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const requestId = randomUUID();
    (req as any).id = requestId;
    (res as any).setHeader("X-Request-Id", requestId);
    next();
  }
}
```
