# NestJS — Fundamentos: DI Avanzado y Lifecycle

**Fuente:** https://docs.nestjs.com/fundamentals/custom-providers | async-providers | injection-scopes | circular-dependency

## Custom Providers

### useClass — cambiar implementación

```typescript
@Module({
  providers: [
    {
      provide: ConfigService,
      useClass: process.env.NODE_ENV === 'development'
        ? DevelopmentConfigService
        : ProductionConfigService,
    },
  ],
})
```

### useValue — mocks y constantes

```typescript
const mockCatsService = {
  findAll: () => [],
  create: jest.fn(),
};

@Module({
  providers: [{ provide: CatsService, useValue: mockCatsService }],
})
```

### Non-class tokens

```typescript
@Module({
  providers: [
    { provide: 'API_KEY', useValue: process.env.API_KEY },
    { provide: 'CONFIG', useValue: { port: 3000, env: 'prod' } },
  ],
})

// Inyección:
constructor(@Inject('API_KEY') private apiKey: string) {}
```

### useFactory — providers dinámicos

```typescript
@Module({
  providers: [
    {
      provide: 'ASYNC_DB',
      useFactory: async (configService: ConfigService) => {
        const url = configService.get('DATABASE_URL');
        return await createConnection(url);
      },
      inject: [ConfigService],  // ← dependencias del factory
    },
  ],
})
```

### useExisting — alias

```typescript
@Module({
  providers: [
    CatsService,
    { provide: 'CATS_SERVICE', useExisting: CatsService },
  ],
})
// CatsService y 'CATS_SERVICE' apuntan a la misma instancia
```

## Injection Scopes

```typescript
@Injectable({ scope: Scope.DEFAULT })   // Singleton — recomendado
@Injectable({ scope: Scope.REQUEST })   // Nueva instancia por request
@Injectable({ scope: Scope.TRANSIENT }) // Nueva instancia por inyección

// Para controllers también:
@Controller({ path: 'cats', scope: Scope.REQUEST })
```

### Acceder al request en REQUEST scope

```typescript
import { REQUEST } from "@nestjs/core";

@Injectable({ scope: Scope.REQUEST })
export class CatsService {
  constructor(@Inject(REQUEST) private request: Request) {}
}
```

## Circular Dependencies — forwardRef

```typescript
// cats.service.ts
@Injectable()
export class CatsService {
  constructor(
    @Inject(forwardRef(() => CommonService))
    private commonService: CommonService,
  ) {}
}

// common.service.ts
@Injectable()
export class CommonService {
  constructor(
    @Inject(forwardRef(() => CatsService))
    private catsService: CatsService,
  ) {}
}

// En módulos también:
@Module({
  imports: [forwardRef(() => CatsModule)],
})
```

> ⚠️ La dependencia circular es un code smell. Intentar refactorizar moviendo la lógica a un tercer servicio.

## Module Reference (obtener providers dinámicamente)

```typescript
import { ModuleRef } from "@nestjs/core";

@Injectable()
export class CatsService {
  constructor(private moduleRef: ModuleRef) {}

  async doSomething() {
    const service = this.moduleRef.get(TransientService, { strict: false });
    // strict: false busca en todo el contexto, no solo el módulo actual

    // Para providers REQUEST o TRANSIENT:
    const contextId = ContextIdFactory.create();
    const transient = await this.moduleRef.resolve(TransientService, contextId);
  }
}
```

## Lazy-loading modules

```typescript
import { LazyModuleLoader } from "@nestjs/core";

@Injectable()
export class CatsService {
  constructor(private lazyModuleLoader: LazyModuleLoader) {}

  async loadLazyModule() {
    const { LazyModule } = await import("./lazy/lazy.module");
    const moduleRef = await this.lazyModuleLoader.load(() => LazyModule);
    const { LazyService } = await import("./lazy/lazy.service");
    const lazyService = moduleRef.get(LazyService);
  }
}
```

## Discovery Service (NestJS 11+)

```typescript
import { DiscoveryService } from "@nestjs/core";

@Injectable()
export class PluginExplorer {
  constructor(
    private readonly discovery: DiscoveryService,
    private readonly reflector: Reflector,
  ) {}

  onModuleInit() {
    const providers = this.discovery.getProviders();
    const controllers = this.discovery.getControllers();

    providers
      .filter((wrapper) => wrapper.isDependencyTreeStatic())
      .forEach((wrapper) => {
        const meta = this.reflector.get("PLUGIN", wrapper.metatype);
        if (meta) console.log("Plugin found:", meta);
      });
  }
}
```

## Execution Context — getType()

```typescript
canActivate(context: ExecutionContext): boolean {
  const type = context.getType<'http' | 'rpc' | 'ws'>();

  if (type === 'http') {
    const req = context.switchToHttp().getRequest();
  } else if (type === 'rpc') {
    const data = context.switchToRpc().getData();
  } else if (type === 'ws') {
    const client = context.switchToWs().getClient();
  }
}
```
