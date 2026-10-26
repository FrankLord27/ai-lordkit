# NestJS — Providers y Dependency Injection

**Fuente:** https://docs.nestjs.com/providers

## Concepto

Los providers son el concepto central de Nest. Servicios, repositorios, factories, helpers — todos pueden ser providers. La idea clave es que pueden ser **inyectados** como dependencias. El IoC container de Nest gestiona todas las relaciones.

## Crear un Service

```typescript
import { Injectable } from "@nestjs/common";
import { Cat } from "./interfaces/cat.interface";

@Injectable()
export class CatsService {
  private readonly cats: Cat[] = [];

  create(cat: Cat) {
    this.cats.push(cat);
  }

  findAll(): Cat[] {
    return this.cats;
  }
}
```

## Inyección en Controller

```typescript
@Controller("cats")
export class CatsController {
  constructor(private catsService: CatsService) {}

  @Post()
  async create(@Body() createCatDto: CreateCatDto) {
    this.catsService.create(createCatDto);
  }
}
```

## Registrar provider en módulo

```typescript
@Module({
  controllers: [CatsController],
  providers: [CatsService], // ← registrar aquí
})
export class AppModule {}
```

## Tipos de providers

### 1. Class provider (más común)

```typescript
providers: [CatsService];
// equivale a:
providers: [{ provide: CatsService, useClass: CatsService }];
```

### 2. Value provider

```typescript
const mockCatsService = { findAll: () => [] };
providers: [{ provide: CatsService, useValue: mockCatsService }];
```

### 3. Factory provider

```typescript
providers: [
  {
    provide: "CONNECTION",
    useFactory: (config: ConfigService) => {
      return new DatabaseConnection(config.get("DB_URL"));
    },
    inject: [ConfigService],
  },
];
```

### 4. Alias provider (useExisting)

```typescript
providers: [
  CatsService,
  { provide: "ALIAS_SERVICE", useExisting: CatsService },
];
```

## Tokens de inyección

```typescript
// Por clase (default)
constructor(private catsService: CatsService) {}

// Por string token
constructor(@Inject('HTTP_OPTIONS') private options: HttpOptions) {}

// Por Symbol token
const CONFIG_TOKEN = Symbol('CONFIG');
constructor(@Inject(CONFIG_TOKEN) private config: Config) {}
```

## Provider opcional

```typescript
@Injectable()
export class HttpService<T> {
  constructor(
    @Optional()
    @Inject("HTTP_OPTIONS")
    private httpClient: T,
  ) {}
}
```

## Inyección en propiedades

```typescript
// Usar solo si la clase extiende otra (para evitar super() tedioso)
@Injectable()
export class HttpService<T> {
  @Inject("HTTP_OPTIONS")
  private readonly httpClient: T;
}
```

> ✅ Preferir siempre **constructor injection** — es más explícito y testeable.

## Scopes de providers

```typescript
import { Injectable, Scope } from "@nestjs/common";

@Injectable({ scope: Scope.DEFAULT }) // Singleton (default) — una instancia por app
export class CatsService {}

@Injectable({ scope: Scope.REQUEST }) // Nueva instancia por cada request
export class RequestScopedService {}

@Injectable({ scope: Scope.TRANSIENT }) // Nueva instancia por cada inyección
export class TransientService {}
```

> ⚠️ REQUEST scope tiene coste de performance. Usar solo si necesitas datos específicos del request en el service.

## Async providers

```typescript
providers: [
  {
    provide: "ASYNC_CONNECTION",
    useFactory: async () => {
      const connection = await createConnection(options);
      return connection;
    },
  },
];
```

## Exportar providers

```typescript
@Module({
  providers: [CatsService],
  exports: [CatsService], // otros módulos pueden inyectar CatsService
})
export class CatsModule {}
```

## Obtener providers fuera del ciclo DI

```typescript
// En main.ts o bootstrap
const app = await NestFactory.create(AppModule);
const catsService = app.get(CatsService);
```

## Generador CLI

```bash
nest g service cats       # genera cats.service.ts + spec
nest g module cats        # genera cats.module.ts
```
