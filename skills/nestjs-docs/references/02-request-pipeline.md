# NestJS — Request Pipeline: Guards, Pipes, Interceptors, Filters

## Orden de ejecución

```
Incoming Request
  ↓
Middleware          (app.use / forRoutes)
  ↓
Guards              (CanActivate — auth/authz)
  ↓
Interceptors (pre)  (antes del handler)
  ↓
Pipes               (validación/transformación de args)
  ↓
Route Handler       (controller method)
  ↓
Interceptors (post) (después del handler — transforma respuesta)
  ↓
Exception Filters   (si hay error en cualquier paso)
  ↓
Response
```

---

## Guards

Determinan si una request puede acceder a la ruta. **Retornan boolean**.
Se ejecutan después de Middleware, antes de Interceptors y Pipes.

### Guard de autenticación JWT

```typescript
// guards/jwt-auth.guard.ts
import { Injectable, ExecutionContext } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Reflector } from "@nestjs/core";
import { IS_PUBLIC_KEY } from "../decorators/public.decorator";

@Injectable()
export class JwtAuthGuard extends AuthGuard("jwt") {
  constructor(private reflector: Reflector) {
    super();
  }

  canActivate(context: ExecutionContext) {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    return super.canActivate(context);
  }
}
```

### Guard de roles (RBAC)

```typescript
// guards/roles.guard.ts
import { Injectable, CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '../decorators/roles.decorator';
import { Role } from '../enums/role.enum';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!requiredRoles) return true;

    const { user } = context.switchToHttp().getRequest();
    return requiredRoles.some((role) => user.roles?.includes(role));
  }
}

// Decorador complementario:
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);

// Uso en controller:
@Roles(Role.ADMIN)
@UseGuards(JwtAuthGuard, RolesGuard)
@Delete(':id')
remove(@Param('id') id: string) { ... }
```

### Niveles de aplicación de Guards

```typescript
// Método:      @UseGuards(AuthGuard)
// Controller:  @UseGuards(AuthGuard) en la clase
// Global (módulo — con DI):
@Module({ providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }] })
// Global (main.ts — sin DI):
app.useGlobalGuards(new AuthGuard());
```

---

## Pipes

Transforman y validan argumentos ANTES de que lleguen al handler.
**Dos usos principales: transformación y validación.**

### ValidationPipe (el más importante)

```typescript
// Configuración global recomendada en main.ts:
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true, // elimina props no decoradas del DTO
    forbidNonWhitelisted: true, // error si llegan props extra
    transform: true, // convierte tipos automáticamente (string → number)
    transformOptions: {
      enableImplicitConversion: true,
    },
  }),
);
```

### Pipes built-in

```typescript
@Get(':id')
findOne(@Param('id', ParseIntPipe) id: number) {}          // string → number

@Get(':uuid')
findOne(@Param('uuid', ParseUUIDPipe) id: string) {}       // valida UUID format

@Get()
findAll(@Query('active', ParseBoolPipe) active: boolean) {} // string → boolean

// ParseArrayPipe, ParseEnumPipe, ParseFloatPipe también disponibles
```

### Pipe personalizado

```typescript
import {
  PipeTransform,
  Injectable,
  ArgumentMetadata,
  BadRequestException,
} from "@nestjs/common";

@Injectable()
export class ParsePositiveIntPipe implements PipeTransform {
  transform(value: any, metadata: ArgumentMetadata): number {
    const val = parseInt(value, 10);
    if (isNaN(val) || val <= 0) {
      throw new BadRequestException(
        `${metadata.data} must be a positive integer`,
      );
    }
    return val;
  }
}

// Uso: @Param('id', ParsePositiveIntPipe) id: number
```

---

## Interceptors

Ejecutan lógica ANTES y DESPUÉS del route handler. Pueden transformar
tanto la request como la response. Usan RxJS Observables.

### Logging Interceptor

```typescript
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from "@nestjs/common";
import { Observable } from "rxjs";
import { tap } from "rxjs/operators";

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const req = context.switchToHttp().getRequest();
    const { method, url } = req;
    const start = Date.now();

    return next.handle().pipe(
      tap(() => {
        console.log(`${method} ${url} — ${Date.now() - start}ms`);
      }),
    );
  }
}
```

### Transform Response Interceptor

```typescript
// Envuelve toda respuesta en { data: ... }
import { map } from "rxjs/operators";

@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<
  T,
  { data: T }
> {
  intercept(
    context: ExecutionContext,
    next: CallHandler,
  ): Observable<{ data: T }> {
    return next.handle().pipe(map((data) => ({ data })));
  }
}
```

### Cache Interceptor

```typescript
@Injectable()
export class CacheInterceptor implements NestInterceptor {
  constructor(private cache: Map<string, any> = new Map()) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const req = context.switchToHttp().getRequest();
    const key = req.url;

    if (this.cache.has(key)) {
      return of(this.cache.get(key)); // retornar desde caché
    }

    return next.handle().pipe(tap((response) => this.cache.set(key, response)));
  }
}
```

### Timeout Interceptor

```typescript
import { timeout } from "rxjs/operators";
import { TimeoutError } from "rxjs";
import { RequestTimeoutException } from "@nestjs/common";

@Injectable()
export class TimeoutInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      timeout(5000),
      catchError((err) => {
        if (err instanceof TimeoutError) {
          throw new RequestTimeoutException();
        }
        return throwError(() => err);
      }),
    );
  }
}
```

### Niveles de aplicación de Interceptors

```typescript
// Método:      @UseInterceptors(LoggingInterceptor)
// Controller:  @UseInterceptors(LoggingInterceptor) en la clase
// Global (módulo):
@Module({ providers: [{ provide: APP_INTERCEPTOR, useClass: LoggingInterceptor }] })
// Global (main.ts):
app.useGlobalInterceptors(new LoggingInterceptor());
```

---

## Exception Filters

Capturan excepciones no manejadas y formatean la respuesta de error.

### Filter global para todas las excepciones

```typescript
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
} from "@nestjs/common";

@Catch() // Sin argumento = captura TODAS las excepciones
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();
    const request = ctx.getRequest();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const message =
      exception instanceof HttpException
        ? exception.getResponse()
        : "Internal server error";

    response.status(status).json({
      statusCode: status,
      timestamp: new Date().toISOString(),
      path: request.url,
      message,
    });
  }
}
```

### Filter para Prisma (errores de DB)

```typescript
import { PrismaClientKnownRequestError } from "@prisma/client/runtime/library";

@Catch(PrismaClientKnownRequestError)
export class PrismaExceptionFilter implements ExceptionFilter {
  catch(exception: PrismaClientKnownRequestError, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse();

    switch (exception.code) {
      case "P2002": // Unique constraint violation
        response.status(409).json({
          statusCode: 409,
          message: `Duplicate entry: ${exception.meta?.target}`,
        });
        break;
      case "P2025": // Record not found
        response.status(404).json({
          statusCode: 404,
          message: "Record not found",
        });
        break;
      default:
        response
          .status(500)
          .json({ statusCode: 500, message: "Database error" });
    }
  }
}
```

---

## ExecutionContext

Disponible en Guards, Interceptors y Filters. Proporciona contexto de ejecución.

```typescript
canActivate(context: ExecutionContext): boolean {
  // HTTP context
  const request = context.switchToHttp().getRequest<Request>();
  const response = context.switchToHttp().getResponse<Response>();

  // WebSocket context
  const client = context.switchToWs().getClient();
  const data = context.switchToWs().getData();

  // RPC context
  const rpcContext = context.switchToRpc().getContext();

  // Metadata (Reflector)
  const handler = context.getHandler();  // método del controller
  const cls = context.getClass();        // clase del controller
}
```
