# NestJS — Interceptors

**Fuente:** https://docs.nestjs.com/interceptors

## Concepto

Un Interceptor implementa `NestInterceptor` y puede:

- Ejecutar lógica ANTES y DESPUÉS del handler
- Transformar el resultado de retorno
- Transformar excepciones
- Extender comportamiento de funciones
- Sobrescribir funciones (ej: caché)

Usa **Aspect Oriented Programming (AOP)** como paradigma.

## Interceptor básico

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
    console.log(`→ ${req.method} ${req.url}`);
    const now = Date.now();

    return next
      .handle() // ← llama al handler; sin esto el handler NO se ejecuta
      .pipe(tap(() => console.log(`← ${Date.now() - now}ms`)));
  }
}
```

## CallHandler

`next.handle()` devuelve un `Observable` de la response del handler. Todo lo que pongas ANTES de `return next.handle()` corre ANTES del handler. Todo lo que pongas en `.pipe(...)` corre DESPUÉS.

## Transformar response (Response Mapping)

```typescript
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
    return next.handle().pipe(
      map((data) => ({ data })), // envuelve en { data: ... }
    );
  }
}

// Resultado: { "data": { ...original response } }
```

## Transformar excepciones

```typescript
import { throwError } from "rxjs";
import { catchError } from "rxjs/operators";
import { BadGatewayException } from "@nestjs/common";

@Injectable()
export class ErrorsInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next
      .handle()
      .pipe(catchError((err) => throwError(() => new BadGatewayException())));
  }
}
```

## Cache interceptor (Stream Override)

```typescript
import { of } from "rxjs";

@Injectable()
export class CacheInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const isCached = true; // lógica de cache real aquí
    if (isCached) {
      return of([]); // retorna Observable sin llamar al handler
    }
    return next.handle();
  }
}
```

## Timeout interceptor

```typescript
import { timeout } from "rxjs/operators";
import { RequestTimeoutException } from "@nestjs/common";
import { TimeoutError, throwError } from "rxjs";
import { catchError } from "rxjs/operators";

@Injectable()
export class TimeoutInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    return next.handle().pipe(
      timeout(5000), // 5 segundos
      catchError((err) => {
        if (err instanceof TimeoutError) {
          return throwError(() => new RequestTimeoutException());
        }
        return throwError(() => err);
      }),
    );
  }
}
```

## Binding Interceptors

```typescript
// En método
@UseInterceptors(LoggingInterceptor)
@Get()
findAll() {}

// En controller
@UseInterceptors(LoggingInterceptor)
@Controller('cats')
export class CatsController {}

// Global (main.ts) — sin DI
app.useGlobalInterceptors(new LoggingInterceptor());

// Global con DI (app.module.ts) — RECOMENDADO
@Module({
  providers: [
    {
      provide: APP_INTERCEPTOR,
      useClass: LoggingInterceptor,
    },
  ],
})
export class AppModule {}
```

## Interceptor para envolver todas las responses

```typescript
@Injectable()
export class ResponseWrapperInterceptor<T> implements NestInterceptor<
  T,
  ApiResponse<T>
> {
  intercept(
    context: ExecutionContext,
    next: CallHandler,
  ): Observable<ApiResponse<T>> {
    return next.handle().pipe(
      map((data) => ({
        success: true,
        data,
        timestamp: new Date().toISOString(),
      })),
    );
  }
}
```

## RxJS operators más usados en interceptors

```typescript
tap(fn); // ejecutar side-effect sin modificar valor
map(fn); // transformar el valor emitido
catchError(fn); // manejar errores
timeout(ms); // lanzar error si no emite en tiempo
switchMap(fn); // cancelar Observable anterior, emitir nuevo
mergeMap(fn); // combinar Observables en paralelo
finalize(fn); // ejecutar al completar O al error
```
