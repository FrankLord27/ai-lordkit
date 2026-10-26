# NestJS — API Versioning

Mantener múltiples versiones de tu API simultáneamente para no romper clientes existentes.

---

## Habilitar versioning

```typescript
// main.ts
import { VersioningType } from "@nestjs/common";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableVersioning({
    type: VersioningType.URI, // /v1/users, /v2/users
    defaultVersion: "1", // Versión por defecto
  });

  await app.listen(3000);
}
```

---

## Tipos de versioning

### 1. URI Versioning (recomendado)

```typescript
app.enableVersioning({
  type: VersioningType.URI,
  prefix: "v", // /v1/users, /v2/users
});
```

### 2. Header Versioning

```typescript
app.enableVersioning({
  type: VersioningType.HEADER,
  header: "X-API-Version", // Header: X-API-Version: 1
});
```

### 3. Media Type Versioning

```typescript
app.enableVersioning({
  type: VersioningType.MEDIA_TYPE,
  key: "v=", // Accept: application/json;v=1
});
```

### 4. Custom Versioning

```typescript
app.enableVersioning({
  type: VersioningType.CUSTOM,
  extractor: (request) => {
    // Extraer versión de donde quieras
    return request.headers["x-custom-version"] ?? "1";
  },
});
```

---

## Aplicar versiones a controllers

### Versión en todo el controller

```typescript
@Controller("users")
@Version("1")
export class UsersV1Controller {
  @Get()
  findAll() {
    return { version: 1, users: [] };
  }
}

@Controller("users")
@Version("2")
export class UsersV2Controller {
  @Get()
  findAll() {
    // V2: respuesta con estructura diferente
    return {
      version: 2,
      data: { users: [], pagination: {} },
    };
  }
}
```

### Versión por endpoint

```typescript
@Controller("users")
export class UsersController {
  @Get()
  @Version("1")
  findAllV1() {
    return { users: [] };
  }

  @Get()
  @Version("2")
  findAllV2() {
    return { data: { users: [] }, meta: {} };
  }

  @Get(":id")
  @Version(["1", "2"]) // Mismo endpoint para ambas versiones
  findOne(@Param("id") id: string) {
    return this.usersService.findOne(id);
  }
}
```

### Versión neutral (todas las versiones)

```typescript
@Controller("health")
@Version(VERSION_NEUTRAL) // Disponible en todas las versiones
export class HealthController {
  @Get()
  check() {
    return { status: "ok" };
  }
}
```

---

## Estructura de proyecto recomendada

```
src/
├── modules/
│   └── users/
│       ├── v1/
│       │   ├── users-v1.controller.ts
│       │   ├── users-v1.service.ts
│       │   └── dto/
│       │       └── create-user-v1.dto.ts
│       ├── v2/
│       │   ├── users-v2.controller.ts
│       │   ├── users-v2.service.ts
│       │   └── dto/
│       │       └── create-user-v2.dto.ts
│       ├── users.module.ts
│       └── shared/
│           └── users.repository.ts  ← Lógica compartida
```

### Módulo con múltiples versiones

```typescript
// users.module.ts
@Module({
  controllers: [UsersV1Controller, UsersV2Controller],
  providers: [
    UsersV1Service,
    UsersV2Service,
    UsersRepository, // Compartido entre versiones
  ],
})
export class UsersModule {}
```

---

## Deprecación de versiones

```typescript
@Controller("users")
@Version("1")
export class UsersV1Controller {
  @Get()
  @Header("Deprecation", "true")
  @Header("Sunset", "Sat, 01 Jan 2025 00:00:00 GMT")
  @Header("Link", '</v2/users>; rel="successor-version"')
  findAll() {
    return this.usersService.findAll();
  }
}
```

### Interceptor de deprecación

```typescript
// common/interceptors/deprecation.interceptor.ts
@Injectable()
export class DeprecationInterceptor implements NestInterceptor {
  constructor(
    private readonly sunsetDate: string,
    private readonly successorVersion: string,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler) {
    const response = context.switchToHttp().getResponse();

    response.setHeader("Deprecation", "true");
    response.setHeader("Sunset", this.sunsetDate);
    response.setHeader(
      "Link",
      `</v${this.successorVersion}>; rel="successor-version"`,
    );

    return next.handle();
  }
}

// Uso:
@Controller("users")
@Version("1")
@UseInterceptors(new DeprecationInterceptor("2025-01-01", "2"))
export class UsersV1Controller {}
```

---

## Swagger con versiones

```typescript
// main.ts
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableVersioning({ type: VersioningType.URI });

  // Documentación V1
  const configV1 = new DocumentBuilder()
    .setTitle("API V1")
    .setVersion("1.0")
    .build();
  const documentV1 = SwaggerModule.createDocument(app, configV1, {
    include: [UsersV1Module, ProductsV1Module],
  });
  SwaggerModule.setup("api/v1/docs", app, documentV1);

  // Documentación V2
  const configV2 = new DocumentBuilder()
    .setTitle("API V2")
    .setVersion("2.0")
    .build();
  const documentV2 = SwaggerModule.createDocument(app, configV2, {
    include: [UsersV2Module, ProductsV2Module],
  });
  SwaggerModule.setup("api/v2/docs", app, documentV2);

  await app.listen(3000);
}
```

---

## Migración gradual entre versiones

```typescript
// v2/users-v2.service.ts
@Injectable()
export class UsersV2Service {
  constructor(
    private readonly usersRepository: UsersRepository,
    private readonly v1Service: UsersV1Service, // Reusar lógica de v1
  ) {}

  async findAll() {
    // Reusar lógica de v1 y transformar respuesta
    const v1Data = await this.v1Service.findAll();

    return {
      data: v1Data,
      meta: {
        version: 2,
        timestamp: new Date().toISOString(),
      },
    };
  }
}
```

---

## Cuándo crear una nueva versión

### Sí crear nueva versión (breaking changes):

- Cambiar estructura de respuesta
- Remover campos obligatorios
- Cambiar tipos de datos
- Modificar comportamiento de endpoints

### No necesita nueva versión:

- Agregar campos opcionales a la respuesta
- Agregar nuevos endpoints
- Agregar parámetros opcionales
- Corrección de bugs

---

## Checklist

- [ ] Decidir tipo de versioning (URI recomendado)
- [ ] Configurar en `main.ts`
- [ ] Estructurar carpetas por versión
- [ ] Reusar lógica común via Repository/Services compartidos
- [ ] Documentar deprecaciones con headers
- [ ] Configurar Swagger por versión
- [ ] Definir política de sunset (cuánto tiempo mantener versiones viejas)
