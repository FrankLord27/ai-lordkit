# Backend — NestJS 11 + Prisma + Redis + JWT

> ⚠️ **Prisma 7:** los ejemplos con `new PrismaClient()` / `extends PrismaClient` asumen el setup v7 con **driver adapter** (`@prisma/adapter-pg`) y `prisma.config.ts` — sin adapter NO compilan. Setup completo en `prisma7-docs`.

---

## Arquitectura de módulos

Cada dominio de negocio es un módulo autónomo. Un módulo no importa a otro directamente. Si dos módulos necesitan comunicarse, se expone el servicio y se importa el módulo, no el servicio directamente.

### Estructura de un módulo

```
modules/[dominio]/
├── [dominio].module.ts       ← Registra controllers, providers, imports
├── [dominio].controller.ts   ← HTTP: recibe, delega, retorna
├── [dominio].service.ts      ← Lógica de negocio + orquestación
├── repositories/
│   └── [entidad].repository.ts  ← Solo Prisma. Sin lógica.
└── dto/
    ├── create-[entidad].dto.ts
    ├── update-[entidad].dto.ts
    └── search-[entidad].dto.ts
```

### Responsabilidades por capa

**Controller — solo HTTP:**

```typescript
// ✅ Correcto — delega todo al service
@Post('search')
async search(@Body() dto: SearchItemsDto) {
  return this.itemsService.search(dto);
}

// ❌ Incorrecto — lógica de negocio en el controller
@Post('search')
async search(@Body() dto: SearchItemsDto) {
  const cacheKey = `search:${JSON.stringify(dto)}`;
  const cached = await this.redis.get(cacheKey);
  if (cached) return JSON.parse(cached);
  // ... esto va en el Service
}
```

**Service — orquesta lógica y cache:**

```typescript
@Injectable()
export class ItemsService {
  constructor(
    private readonly itemRepository: ItemRepository,
    private readonly redisService: RedisService,
  ) {}

  async search(dto: SearchItemsDto) {
    const cacheKey = `search:items:${JSON.stringify(dto)}`;

    const cached = await this.redisService.get(cacheKey);
    if (cached) return JSON.parse(cached);

    const results = await this.itemRepository.findAvailable(dto);
    await this.redisService.set(cacheKey, JSON.stringify(results), 300);

    return results;
  }
}
```

**Repository — solo Prisma:**

```typescript
@Injectable()
export class ItemRepository {
  constructor(private readonly prisma: PrismaService) {}

  // Métodos claros y enfocados — sin lógica de negocio
  async findAvailable(filters: SearchItemsDto) {
    return this.prisma.item.findMany({
      where: {
        status: "ACTIVE",
        price: filters.maxPrice ? { lte: filters.maxPrice } : undefined,
      },
      include: { images: { orderBy: { order: "asc" } } },
    });
  }

  async findById(id: string) {
    return this.prisma.item.findUnique({
      where: { id },
      include: { category: true, images: true },
    });
  }

  // Para operaciones críticas: transacción atómica
  async createWithStock(data: CreateItemData) {
    return this.prisma.$transaction(async (tx) => {
      const item = await tx.item.create({ data });
      await tx.inventory.create({
        data: { itemId: item.id, quantity: data.stock },
      });
      return item;
    });
  }
}
```

---

## main.ts — configuración global completa

Este archivo va igual en todo proyecto desde el día 1:

```typescript
import { NestFactory } from "@nestjs/core";
import { ValidationPipe, Logger } from "@nestjs/common";
import { SwaggerModule, DocumentBuilder } from "@nestjs/swagger";
import helmet from "helmet";
import { AppModule } from "./app.module";
import { HttpExceptionFilter } from "./common/filters/http-exception.filter";
import { TransformInterceptor } from "./common/interceptors/transform.interceptor";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const logger = new Logger("Bootstrap");

  // Seguridad HTTP — siempre primero
  app.use(helmet());
  app.enableCors({
    origin: process.env.FRONTEND_URL,
    credentials: true,
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE"],
  });

  // Prefijo global
  app.setGlobalPrefix("api/v1");

  // Validación global — whitelist elimina campos extra, forbid lanza error si llegan
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true, // Convierte strings a números, etc.
      transformOptions: { enableImplicitConversion: true },
    }),
  );

  // Errores normalizados y respuesta envuelta en { data }
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(new TransformInterceptor());

  // Swagger
  const config = new DocumentBuilder()
    .setTitle("API")
    .setDescription("Descripción de la API")
    .setVersion("1.0")
    .addBearerAuth()
    .build();
  SwaggerModule.setup("docs", app, SwaggerModule.createDocument(app, config));

  const port = process.env.PORT ?? 3001;
  await app.listen(port);
  logger.log(`API corriendo en http://localhost:${port}/api/v1`);
  logger.log(`Swagger en http://localhost:${port}/docs`);
}

bootstrap();
```

---

## ExceptionFilter — errores normalizados

Todos los errores retornan la misma estructura. El frontend siempre sabe qué esperar.

```typescript
// common/filters/http-exception.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
} from "@nestjs/common";
import { Request, Response } from "express";

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request>();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const message =
      exception instanceof HttpException
        ? exception.message
        : "Error interno del servidor";

    this.logger.error(`${req.method} ${req.url} → ${status}: ${message}`);

    res.status(status).json({
      statusCode: status,
      message,
      error: HttpStatus[status],
      timestamp: new Date().toISOString(),
      path: req.url,
    });
  }
}
```

## TransformInterceptor — respuesta envuelta en { data }

```typescript
// common/interceptors/transform.interceptor.ts
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from "@nestjs/common";
import { Observable } from "rxjs";
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

---

## DTOs con class-validator

```typescript
// dto/search-items.dto.ts
import {
  IsString,
  IsOptional,
  IsNumber,
  IsEnum,
  Min,
  Max,
} from "class-validator";
import { Type } from "class-transformer";
import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";

export class SearchItemsDto {
  @ApiProperty()
  @IsString()
  locationId: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  maxPrice?: number;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEnum(["category_a", "category_b"])
  category?: string;
}

// Paginación reutilizable — importar en cualquier módulo que liste
export class PaginationDto {
  @IsOptional()
  @IsNumber()
  @Min(1)
  @Type(() => Number)
  page?: number = 1;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(100)
  @Type(() => Number)
  limit?: number = 20;
}
```

---

## Prisma — patrones y buenas prácticas

### Schema — reglas fijas

```prisma
model Item {
  id          String      @id @default(uuid())    // ← Siempre UUID
  name        String
  price       Decimal     @db.Decimal(10, 2)       // ← Decimal para dinero, nunca Float
  status      ItemStatus  @default(ACTIVE)
  categoryId  String
  createdAt   DateTime    @default(now())           // ← Siempre timestamps
  updatedAt   DateTime    @updatedAt

  category    Category    @relation(fields: [categoryId], references: [id])
  images      ItemImage[]

  @@index([categoryId, status])   // ← Índice en columnas WHERE frecuentes
  @@index([createdAt])
}

enum ItemStatus {
  ACTIVE
  INACTIVE
  ARCHIVED
}
```

### PrismaService

```typescript
// prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

### Mapper — nunca exponer entidades de Prisma directamente

```typescript
// mappers/item.mapper.ts
import { Item, ItemImage } from "@prisma/client";

type ItemWithImages = Item & { images: ItemImage[] };

export class ItemMapper {
  static toDto(item: ItemWithImages) {
    return {
      id: item.id,
      name: item.name,
      price: Number(item.price), // Decimal → number para JSON
      status: item.status,
      images: item.images.map((img) => ({ url: img.url, order: img.order })),
      createdAt: item.createdAt.toISOString(),
      // ❌ Nunca incluir: internalNotes, costPrice, campos sensibles
    };
  }
}
```

### Paginación estándar en repository

```typescript
async findAll({ page = 1, limit = 20 }: PaginationDto) {
  const skip = (page - 1) * limit;
  const [data, total] = await Promise.all([
    this.prisma.item.findMany({ skip, take: limit, orderBy: { createdAt: 'desc' } }),
    this.prisma.item.count(),
  ]);
  return {
    data: data.map(ItemMapper.toDto),
    total,
    page,
    limit,
    hasNextPage: skip + limit < total,
  };
}
```

---

## Redis — cache patterns

### RedisService

```typescript
// redis/redis.service.ts
import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  Logger,
} from "@nestjs/common";
import Redis from "ioredis";

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private client: Redis;
  private readonly logger = new Logger(RedisService.name);

  onModuleInit() {
    this.client = new Redis({
      host: process.env.REDIS_HOST ?? "localhost",
      port: Number(process.env.REDIS_PORT ?? 6379),
    });
    this.client.on("error", (err) => this.logger.error("Redis error:", err));
  }

  async onModuleDestroy() {
    await this.client.quit();
  }

  async get<T>(key: string): Promise<T | null> {
    const value = await this.client.get(key);
    return value ? JSON.parse(value) : null;
  }

  async set(key: string, value: unknown, ttlSeconds?: number): Promise<void> {
    const serialized = JSON.stringify(value);
    if (ttlSeconds) {
      await this.client.setex(key, ttlSeconds, serialized);
    } else {
      await this.client.set(key, serialized);
    }
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }

  async delByPattern(pattern: string): Promise<void> {
    const keys = await this.client.keys(pattern);
    if (keys.length) await this.client.del(...keys);
  }
}
```

### TTLs recomendados

| Tipo de dato                                | TTL               |
| ------------------------------------------- | ----------------- |
| Búsquedas de catálogo                       | 5 minutos (300s)  |
| Datos de un item específico                 | 10 minutos (600s) |
| Perfil de usuario                           | 1 minuto (60s)    |
| Listas de referencia (ciudades, categorías) | 1 hora (3600s)    |
| Datos en tiempo real                        | No cachear        |

### Invalidación de cache al mutar

```typescript
// En el service, al crear/actualizar/eliminar un item:
async createItem(dto: CreateItemDto) {
  const item = await this.itemRepository.create(dto);
  // Invalida todo el cache de búsquedas de items
  await this.redis.delByPattern('search:items:*');
  return ItemMapper.toDto(item);
}
```

---

## JWT + Passport — Auth completa

### Flujo de tokens

```
POST /api/v1/auth/login
  → Valida credenciales
  → Genera Access Token (15 min) — retorna en JSON
  → Genera Refresh Token (7 días) — guarda en cookie httpOnly
  → Guarda Refresh Token en Redis (para invalidación en logout)

Requests autenticados:
  → Header: Authorization: Bearer <access_token>
  → Guard JwtAuthGuard verifica y decodifica

Access Token expirado:
  → POST /api/v1/auth/refresh
  → Lee cookie httpOnly con refresh token
  → Verifica contra Redis
  → Retorna nuevo Access Token

POST /api/v1/auth/logout:
  → Elimina Refresh Token de Redis
  → Limpia cookie
```

### Guard reutilizable

```typescript
// common/guards/jwt-auth.guard.ts
import { Injectable } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";

@Injectable()
export class JwtAuthGuard extends AuthGuard("jwt") {}
```

### Decorator @CurrentUser

```typescript
// common/decorators/current-user.decorator.ts
import { createParamDecorator, ExecutionContext } from "@nestjs/common";

export interface UserPayload {
  sub: string;
  email: string;
  role: string;
}

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): UserPayload => {
    const request = ctx.switchToHttp().getRequest();
    return request.user;
  },
);
```

### Uso en controller

```typescript
@Get('profile')
@UseGuards(JwtAuthGuard)
@ApiBearerAuth()
getProfile(@CurrentUser() user: UserPayload) {
  return this.usersService.findById(user.sub);
}
```

---

## Configuración de variables de entorno con Zod

```typescript
// config/configuration.ts
import { z } from "zod";

const EnvSchema = z.object({
  NODE_ENV: z
    .enum(["development", "production", "test"])
    .default("development"),
  PORT: z.string().default("3001"),
  DATABASE_URL: z.string().min(1, "DATABASE_URL es requerido"),
  REDIS_HOST: z.string().default("localhost"),
  REDIS_PORT: z.string().default("6379"),
  JWT_SECRET: z.string().min(32, "JWT_SECRET debe tener mínimo 32 caracteres"),
  JWT_EXPIRES_IN: z.string().default("15m"),
  REFRESH_TOKEN_EXPIRES_IN: z.string().default("7d"),
  FRONTEND_URL: z.string().url("FRONTEND_URL debe ser una URL válida"),
});

const parsed = EnvSchema.safeParse(process.env);

// Si falta una variable, la app no inicia — falla rápido y claro
if (!parsed.success) {
  console.error("❌ Variables de entorno inválidas:");
  console.error(parsed.error.format());
  process.exit(1);
}

export const configuration = () => ({
  port: parseInt(parsed.data.PORT, 10),
  database: { url: parsed.data.DATABASE_URL },
  redis: {
    host: parsed.data.REDIS_HOST,
    port: parseInt(parsed.data.REDIS_PORT, 10),
  },
  jwt: {
    secret: parsed.data.JWT_SECRET,
    expiresIn: parsed.data.JWT_EXPIRES_IN,
    refreshExpiresIn: parsed.data.REFRESH_TOKEN_EXPIRES_IN,
  },
  frontendUrl: parsed.data.FRONTEND_URL,
  isProduction: parsed.data.NODE_ENV === "production",
});
```

---

## Buenas prácticas Backend

- **Helmet + CORS en main.ts desde el día 1** — no es seguridad de "fase 2", es el piso mínimo.
- **ValidationPipe con `whitelist: true`** — elimina silenciosamente campos no declarados.
- **Nunca `any` en TypeScript** — si Prisma no infiere el tipo, usa los tipos generados por `@prisma/client`.
- **Nunca exponer entidades de Prisma directamente** — siempre pasar por Mapper.
- **Decimal para dinero** — nunca Float. `@db.Decimal(10, 2)` en Prisma.
- **UUID como primary key** — nunca IDs numéricos autoincrementales.
- **Índices en columnas WHERE** — definirlos en el schema desde la primera migration.
- **Transacciones para operaciones compuestas** — si dos operaciones deben ser atómicas, usar `prisma.$transaction`.
- **Logger de NestJS** — usar `new Logger(ClassName.name)` en cada service. Nunca `console.log` en producción.
- **Módulos autónomos** — si un módulo necesita algo de otro, importa el módulo y usa lo que expone, no el servicio directamente.
