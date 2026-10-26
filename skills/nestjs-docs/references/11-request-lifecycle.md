# NestJS — Ciclo de vida completo de un Request

**Fuente:** https://docs.nestjs.com/faq/request-lifecycle | https://docs.nestjs.com/fundamentals/lifecycle-events

## Orden de ejecución de la request pipeline

```
Incoming Request
│
├─ 1. Middleware (global → module-level → route-level)
│     └── next() para continuar
│
├─ 2. Guards (global → controller → method)
│     └── canActivate() → true/false
│
├─ 3. Interceptors PRE (global → controller → method)
│     └── código antes de next.handle()
│
├─ 4. Pipes (global → controller → method → parameter-level)
│     └── transform() → valor transformado/validado
│
├─ 5. Route Handler (método del controller)
│     └── lógica de negocio
│
├─ 6. Interceptors POST (method → controller → global)
│     └── código en .pipe() después de next.handle()
│
└─ Response sent to client
     (Si hay excepción en cualquier punto → Exception Filters)
```

## Lifecycle Events de la aplicación

```typescript
import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  OnApplicationBootstrap,
  OnApplicationShutdown,
  BeforeApplicationShutdown,
} from "@nestjs/common";

@Injectable()
export class DatabaseService implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    // Se ejecuta cuando el módulo se inicializa
    await this.$connect();
    console.log("DB connected");
  }

  async onModuleDestroy() {
    // Se ejecuta cuando el módulo se destruye
    await this.$disconnect();
  }
}

@Injectable()
export class AppService
  implements OnApplicationBootstrap, OnApplicationShutdown
{
  async onApplicationBootstrap() {
    // Se ejecuta después de que TODOS los módulos se inicializaron
    console.log("App bootstrapped");
  }

  async onApplicationShutdown(signal?: string) {
    // Se ejecuta al recibir señal de shutdown (SIGTERM, etc.)
    console.log(`Shutting down on signal: ${signal}`);
  }

  async beforeApplicationShutdown(signal?: string) {
    // Se ejecuta ANTES de onApplicationShutdown
    // útil para: cerrar conexiones activas, drenar cola, etc.
    await this.drainQueue();
  }
}
```

## Orden de lifecycle hooks (bootstrap)

```
1. onModuleInit()              — por módulo, depth-first
2. onApplicationBootstrap()   — por módulo, depth-first
```

## Orden de lifecycle hooks (shutdown)

```
1. beforeApplicationShutdown(signal)  — por módulo
2. onModuleDestroy()                  — por módulo
3. onApplicationShutdown(signal)      — por módulo
```

## Habilitar shutdown hooks

```typescript
// main.ts — OBLIGATORIO para recibir SIGTERM/SIGINT
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableShutdownHooks(); // ← necesario
  await app.listen(3000);
}
```

## Scope propagation

Cuando un REQUEST-scoped provider es inyectado en otro provider, ese otro provider también se vuelve REQUEST-scoped automáticamente (burbujeo hacia arriba en el árbol de dependencias).

```
REQUEST SCOPE:
CatsController (REQUEST)
  └── CatsService (DEFAULT → forzado REQUEST por inyección)
        └── CatsRepository (DEFAULT → forzado REQUEST)
```

> ✅ El scope REQUEST sube en cadena, lo que puede afectar el rendimiento. Evaluar si realmente necesitas per-request state.

## Global prefix

```typescript
// main.ts
app.setGlobalPrefix("api");
// Todas las rutas: /api/cats, /api/users, etc.

// Excluir rutas específicas:
app.setGlobalPrefix("api", {
  exclude: [{ path: "health", method: RequestMethod.GET }],
});
```

## Ordenar middleware global manualmente

```typescript
// main.ts
const app = await NestFactory.create(AppModule);
app.use(helmet()); // 1. seguridad headers
app.use(cors()); // 2. CORS
app.use(compression()); // 3. compresión
app.use(requestLogger); // 4. logging
```

## Datos del request entre componentes (via request object)

```typescript
// Guard → adjunta datos al request
const request = context.switchToHttp().getRequest();
request['user'] = decodedToken;  // disponible en controller y otros guards/interceptors

// Controller → lee datos del request
@Get()
findAll(@Req() req: Request) {
  const user = req['user'];
}

// Custom decorator para leerlos limpiamente
export const CurrentUser = createParamDecorator(
  (_, ctx: ExecutionContext) => ctx.switchToHttp().getRequest().user
);
```
