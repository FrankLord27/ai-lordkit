# NestJS — Modules

**Fuente:** https://docs.nestjs.com/modules

## Concepto

Un módulo es una clase decorada con `@Module()`. Nest usa su metadata para organizar la estructura de la aplicación. Toda app tiene al menos un **root module** (AppModule).

## Anatomía de @Module()

```typescript
@Module({
  imports: [],      // módulos que exportan providers necesarios aquí
  controllers: [],  // controllers que se instancian en este módulo
  providers: [],    // providers que se instancian en este módulo
  exports: [],      // subset de providers accesibles para módulos que importen éste
})
```

## Feature Module

Agrupar funcionalidades relacionadas:

```typescript
// cats/cats.module.ts
import { Module } from "@nestjs/common";
import { CatsController } from "./cats.controller";
import { CatsService } from "./cats.service";

@Module({
  controllers: [CatsController],
  providers: [CatsService],
  exports: [CatsService], // exponer para otros módulos
})
export class CatsModule {}
```

```typescript
// app.module.ts
@Module({
  imports: [CatsModule],
})
export class AppModule {}
```

## Shared Modules

Los módulos son **singletons** por defecto. La misma instancia de un provider se comparte entre todos los módulos que importen ese módulo.

```typescript
@Module({
  providers: [CatsService],
  exports: [CatsService], // ← clave para compartir
})
export class CatsModule {}
```

> ✅ Exportar providers evita múltiples instancias del mismo servicio y asegura estado consistente.

## Re-exportar módulos

```typescript
@Module({
  imports: [CommonModule],
  exports: [CommonModule], // cualquier módulo que importe CoreModule también tiene CommonModule
})
export class CoreModule {}
```

## Global Modules

```typescript
import { Global, Module } from "@nestjs/common";

@Global()
@Module({
  providers: [DatabaseService],
  exports: [DatabaseService],
})
export class DatabaseModule {}
```

> 📝 Registrar global modules solo UNA VEZ en el root. No sobreabuses `@Global()` — reduce la claridad de dependencias.

## Dynamic Modules

Para módulos configurables en runtime:

```typescript
@Module({
  providers: [Connection],
  exports: [Connection],
})
export class DatabaseModule {
  static forRoot(entities = [], options?): DynamicModule {
    const providers = createDatabaseProviders(options, entities);
    return {
      module: DatabaseModule,
      providers: providers,
      exports: providers,
    };
  }

  // Para módulos hijos:
  static forFeature(entities = []): DynamicModule {
    const providers = createRepositoryProviders(entities);
    return {
      module: DatabaseModule,
      providers,
      exports: providers,
    };
  }
}

// Uso:
@Module({
  imports: [DatabaseModule.forRoot([User, Cat])],
})
export class AppModule {}
```

## Inyección en el módulo mismo

```typescript
@Module({
  controllers: [CatsController],
  providers: [CatsService],
})
export class CatsModule {
  constructor(private catsService: CatsService) {}
  // útil para configurar el módulo al inicializarse
}
```

## Estructura recomendada de directorios

```
src/
├── app.module.ts
├── main.ts
├── cats/
│   ├── cats.module.ts
│   ├── cats.controller.ts
│   ├── cats.service.ts
│   ├── dto/
│   │   └── create-cat.dto.ts
│   └── interfaces/
│       └── cat.interface.ts
└── dogs/
    └── dogs.module.ts
```

## CLI

```bash
nest g module cats          # genera cats.module.ts
nest g resource cats        # genera módulo completo (module + controller + service + dto)
```

## Patrón ConfigurableModuleBuilder

Para dynamic modules más limpios (NestJS 9+):

```typescript
import { ConfigurableModuleBuilder } from "@nestjs/common";

export interface DatabaseModuleOptions {
  url: string;
  port: number;
}

export const { ConfigurableModuleClass, MODULE_OPTIONS_TOKEN } =
  new ConfigurableModuleBuilder<DatabaseModuleOptions>().build();

@Module({})
export class DatabaseModule extends ConfigurableModuleClass {}

// Uso:
DatabaseModule.forRoot({ url: "localhost", port: 5432 });
DatabaseModule.forRootAsync({ useFactory: () => ({ url: "...", port: 5432 }) });
```
