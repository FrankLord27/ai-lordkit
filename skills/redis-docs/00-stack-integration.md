# Stack Integration Guide — NestJS + Prisma 7 + Redis

> **Archivo puente** que conecta las 3 skills del stack.
> Coloca este archivo en `/mnt/skills/user/fullstack/` o en cada skill individual.

---

## Arquitectura del Stack

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              REQUEST                                     │
└─────────────────────────────────────────┬───────────────────────────────┘
                                          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         NestJS (Framework)                               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                  │
│  │ Controller  │───▶│   Service   │───▶│   Guard     │                  │
│  │ (HTTP/REST) │    │  (Lógica)   │    │ (Auth/RBAC) │                  │
│  └─────────────┘    └──────┬──────┘    └─────────────┘                  │
│                            │                                             │
│         ┌──────────────────┼──────────────────┐                         │
│         ▼                  ▼                  ▼                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                  │
│  │ CacheService│    │ Repository  │    │ QueueService│                  │
│  │   (Redis)   │    │  (Prisma)   │    │  (BullMQ)   │                  │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                  │
└─────────┼──────────────────┼──────────────────┼─────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│      Redis      │  │   PostgreSQL    │  │      Redis      │
│   (Cache/       │  │   (via Prisma)  │  │    (Queues)     │
│    Sessions)    │  │                 │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

---

## Referencia Cruzada de Skills

### Cuándo usar cada skill

| Necesito...                                | Skill        | Archivos clave                                  |
| ------------------------------------------ | ------------ | ----------------------------------------------- |
| Estructura de módulos, controllers, guards | **NestJS**   | `01-project-structure.md`, `02-modules.md`      |
| Validación de DTOs, pipes                  | **NestJS**   | `validation.md`, `pipes.md`                     |
| Queries a PostgreSQL                       | **Prisma 7** | `03-queries.md`, `04-relations.md`              |
| Transacciones de DB                        | **Prisma 7** | `05-transactions.md`                            |
| Soft delete, audit log                     | **Prisma 7** | `soft-delete.md`, `audit-logging.md`            |
| Cache de API responses                     | **Redis**    | `20-cache-patterns.md`, `10-strings.md`         |
| Sesiones de usuario                        | **Redis**    | `11-hashes.md`, `30-nestjs-integration.md`      |
| Rate limiting                              | **Redis**    | `14-sorted-sets.md`, `30-nestjs-integration.md` |
| Colas de trabajo async                     | **Redis**    | `23-queues-bullmq.md`                           |
| Eventos real-time                          | **Redis**    | `15-streams.md`, `16-pubsub.md`                 |

### Archivos de integración (los más importantes)

| Archivo                        | Skill    | Conecta         |
| ------------------------------ | -------- | --------------- |
| `30-nestjs-integration.md`     | Redis    | Redis ↔ NestJS  |
| `nestjs-prisma-integration.md` | Prisma 7 | Prisma ↔ NestJS |
| `23-queues-bullmq.md`          | Redis    | BullMQ ↔ NestJS |

---

## Flujo Completo: Request → Cache → DB → Response

Este es el patrón más común del stack:

```typescript
// ========================================
// 1. CONTROLLER (NestJS)
// ========================================
// Ver: nestjs-skill/controllers.md

@Controller("products")
export class ProductsController {
  constructor(private productsService: ProductsService) {}

  @Get(":id")
  @UseGuards(JwtAuthGuard)
  async findOne(@Param("id") id: string): Promise<ProductDto> {
    return this.productsService.findOne(id);
  }

  @Put(":id")
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles("admin", "editor")
  async update(
    @Param("id") id: string,
    @Body() dto: UpdateProductDto,
  ): Promise<ProductDto> {
    return this.productsService.update(id, dto);
  }
}

// ========================================
// 2. SERVICE (NestJS + Cache + DB)
// ========================================
// Ver: nestjs-skill/services.md
// Ver: redis-skill/20-cache-patterns.md
// Ver: prisma7-skill/03-queries.md

@Injectable()
export class ProductsService {
  constructor(
    private productsRepository: ProductsRepository,
    private cacheService: CacheService,
  ) {}

  async findOne(id: string): Promise<Product> {
    const cacheKey = `product:${id}`;

    // 1. Buscar en cache (Redis)
    const cached = await this.cacheService.get<Product>(cacheKey);
    if (cached) return cached;

    // 2. Cache miss → buscar en DB (Prisma)
    const product = await this.productsRepository.findById(id);
    if (!product) throw new NotFoundException();

    // 3. Guardar en cache
    await this.cacheService.set(cacheKey, product, 300);

    return product;
  }

  async update(id: string, dto: UpdateProductDto): Promise<Product> {
    // 1. Actualizar en DB (Prisma)
    const product = await this.productsRepository.update(id, dto);

    // 2. Invalidar cache (Redis)
    await this.cacheService.invalidate(`product:${id}`);
    await this.cacheService.invalidateTag("products");

    // 3. Emitir evento para otros procesos (opcional)
    await this.eventBus.publish("products", "product.updated", {
      productId: id,
    });

    return product;
  }
}

// ========================================
// 3. REPOSITORY (Prisma 7)
// ========================================
// Ver: prisma7-skill/03-queries.md
// Ver: prisma7-skill/soft-delete.md

@Injectable()
export class ProductsRepository {
  constructor(private prisma: PrismaService) {}

  async findById(id: string): Promise<Product | null> {
    return this.prisma.product.findUnique({
      where: { id, deletedAt: null }, // Soft delete filter
      include: { category: true },
    });
  }

  async update(id: string, data: UpdateProductDto): Promise<Product> {
    return this.prisma.product.update({
      where: { id },
      data: {
        ...data,
        updatedAt: new Date(),
      },
    });
  }

  async findMany(filters: ProductFilters): Promise<Product[]> {
    return this.prisma.product.findMany({
      where: {
        deletedAt: null,
        categoryId: filters.categoryId,
        price: filters.minPrice ? { gte: filters.minPrice } : undefined,
      },
      orderBy: { createdAt: "desc" },
      take: filters.limit ?? 20,
      skip: filters.offset ?? 0,
    });
  }
}

// ========================================
// 4. CACHE SERVICE (Redis)
// ========================================
// Ver: redis-skill/30-nestjs-integration.md
// Ver: redis-skill/20-cache-patterns.md

@Injectable()
export class CacheService {
  constructor(@Inject(CACHE_MANAGER) private cache: Cache) {}

  async get<T>(key: string): Promise<T | null> {
    return this.cache.get<T>(key) ?? null;
  }

  async set<T>(key: string, value: T, ttlSeconds: number): Promise<void> {
    await this.cache.set(key, value, ttlSeconds * 1000);
  }

  async invalidate(key: string): Promise<void> {
    await this.cache.del(key);
  }

  async invalidateTag(tag: string): Promise<void> {
    // Implementación en redis-skill/20-cache-patterns.md
  }
}
```

---

## Flujo: Operación Async con Cola

```typescript
// ========================================
// CONTROLLER - Encolar trabajo
// ========================================

@Post('orders')
async createOrder(@Body() dto: CreateOrderDto): Promise<{ orderId: string }> {
  // 1. Crear orden en DB (Prisma)
  const order = await this.ordersService.create(dto);

  // 2. Encolar procesamiento async (BullMQ/Redis)
  await this.ordersService.queueProcessing(order.id);

  return { orderId: order.id };
}

// ========================================
// SERVICE - Crear + Encolar
// ========================================
// Ver: prisma7-skill/05-transactions.md
// Ver: redis-skill/23-queues-bullmq.md

@Injectable()
export class OrdersService {
  constructor(
    private prisma: PrismaService,
    @InjectQueue('orders') private ordersQueue: Queue,
  ) {}

  async create(dto: CreateOrderDto): Promise<Order> {
    // Transacción Prisma para crear orden + items
    return this.prisma.$transaction(async (tx) => {
      const order = await tx.order.create({
        data: {
          userId: dto.userId,
          status: 'pending',
          total: dto.total,
        },
      });

      await tx.orderItem.createMany({
        data: dto.items.map(item => ({
          orderId: order.id,
          productId: item.productId,
          quantity: item.quantity,
          price: item.price,
        })),
      });

      return order;
    });
  }

  async queueProcessing(orderId: string): Promise<void> {
    await this.ordersQueue.add('process', { orderId }, {
      attempts: 3,
      backoff: { type: 'exponential', delay: 1000 },
    });
  }
}

// ========================================
// PROCESSOR - Trabajo async
// ========================================
// Ver: redis-skill/23-queues-bullmq.md

@Processor('orders')
export class OrdersProcessor extends WorkerHost {
  constructor(
    private prisma: PrismaService,
    private paymentService: PaymentService,
    private emailService: EmailService,
  ) {
    super();
  }

  async process(job: Job<{ orderId: string }>): Promise<void> {
    const { orderId } = job.data;

    // 1. Obtener orden de DB
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { user: true, items: true },
    });

    await job.updateProgress(25);

    // 2. Procesar pago
    await this.paymentService.charge(order);

    await job.updateProgress(50);

    // 3. Actualizar estado en DB
    await this.prisma.order.update({
      where: { id: orderId },
      data: { status: 'paid', paidAt: new Date() },
    });

    await job.updateProgress(75);

    // 4. Enviar confirmación (otra cola)
    await this.emailService.queueConfirmation(order);

    await job.updateProgress(100);
  }
}
```

---

## Flujo: Sesiones + Auth

```typescript
// ========================================
// AUTH SERVICE
// ========================================
// Ver: redis-skill/11-hashes.md (sesiones)
// Ver: prisma7-skill/03-queries.md (usuario)

@Injectable()
export class AuthService {
  constructor(
    private prisma: PrismaService,
    private sessionService: SessionService,
    private jwtService: JwtService,
  ) {}

  async login(email: string, password: string): Promise<LoginResponse> {
    // 1. Buscar usuario en DB (Prisma)
    const user = await this.prisma.user.findUnique({
      where: { email, deletedAt: null },
      include: { tenant: true },
    });

    if (!user || !(await bcrypt.compare(password, user.password))) {
      throw new UnauthorizedException();
    }

    // 2. Crear sesión en Redis
    const sessionId = crypto.randomUUID();
    await this.sessionService.create(sessionId, {
      userId: user.id,
      email: user.email,
      role: user.role,
      tenantId: user.tenantId,
      permissions: user.permissions,
    });

    // 3. Generar JWT con sessionId
    const token = this.jwtService.sign({ sessionId });

    return { token, user: this.mapToDto(user) };
  }

  async logout(sessionId: string): Promise<void> {
    await this.sessionService.destroy(sessionId);
  }
}

// ========================================
// SESSION SERVICE (Redis Hash)
// ========================================
// Ver: redis-skill/11-hashes.md

@Injectable()
export class SessionService {
  private readonly TTL = 24 * 60 * 60; // 24 horas

  constructor(@Inject(REDIS_CLIENT) private redis: Redis) {}

  async create(sessionId: string, data: SessionData): Promise<void> {
    const key = `session:${sessionId}`;
    await this.redis.hset(key, {
      userId: data.userId,
      email: data.email,
      role: data.role,
      tenantId: data.tenantId,
      permissions: JSON.stringify(data.permissions),
    });
    await this.redis.expire(key, this.TTL);
  }

  async get(sessionId: string): Promise<SessionData | null> {
    const data = await this.redis.hgetall(`session:${sessionId}`);
    if (!data.userId) return null;
    return {
      ...data,
      permissions: JSON.parse(data.permissions || "[]"),
    } as SessionData;
  }

  async refresh(sessionId: string): Promise<void> {
    await this.redis.expire(`session:${sessionId}`, this.TTL);
  }

  async destroy(sessionId: string): Promise<void> {
    await this.redis.del(`session:${sessionId}`);
  }
}

// ========================================
// SESSION GUARD
// ========================================
// Ver: nestjs-skill/guards.md

@Injectable()
export class SessionGuard implements CanActivate {
  constructor(
    private jwtService: JwtService,
    private sessionService: SessionService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const token = this.extractToken(request);

    if (!token) throw new UnauthorizedException();

    const { sessionId } = this.jwtService.verify(token);
    const session = await this.sessionService.get(sessionId);

    if (!session) throw new UnauthorizedException("Session expired");

    // Renovar TTL en cada request
    await this.sessionService.refresh(sessionId);

    // Adjuntar al request
    request.user = session;
    request.sessionId = sessionId;

    return true;
  }
}
```

---

## Invalidación de Cache al Actualizar DB

**El patrón más importante del stack:**

```typescript
// Ver: redis-skill/20-cache-patterns.md
// Ver: prisma7-skill/03-queries.md

@Injectable()
export class ProductsService {
  async update(id: string, dto: UpdateProductDto): Promise<Product> {
    // 1. ACTUALIZAR DB (Prisma)
    const product = await this.prisma.product.update({
      where: { id },
      data: dto,
    });

    // 2. INVALIDAR CACHES (Redis)
    await Promise.all([
      this.cache.del(`product:${id}`), // Cache individual
      this.cache.del(`product:${id}:details`), // Cache relacionado
      this.invalidateTag("products"), // Tag-based invalidation
      this.invalidateTag(`category:${product.categoryId}`),
    ]);

    // 3. NOTIFICAR OTROS SERVICIOS (opcional, Pub/Sub)
    await this.redis.publish(
      "cache:invalidate",
      JSON.stringify({
        entity: "product",
        id,
      }),
    );

    return product;
  }
}
```

---

## Módulo Común Integrado

```typescript
// common/common.module.ts
// Este módulo conecta Redis + Prisma con NestJS

@Global()
@Module({
  imports: [
    // Cache con Redis
    CacheModule.registerAsync({
      useFactory: (config: ConfigService) => ({
        store: redisStore,
        host: config.get("REDIS_HOST"),
        port: config.get("REDIS_PORT"),
        ttl: 300,
      }),
      inject: [ConfigService],
    }),

    // Colas con BullMQ
    BullModule.forRootAsync({
      useFactory: (config: ConfigService) => ({
        connection: {
          host: config.get("REDIS_HOST"),
          port: config.get("REDIS_PORT"),
        },
      }),
      inject: [ConfigService],
    }),
  ],
  providers: [
    // Prisma
    PrismaService,

    // Redis directo
    {
      provide: REDIS_CLIENT,
      useFactory: (config: ConfigService) =>
        new Redis({
          host: config.get("REDIS_HOST"),
          port: config.get("REDIS_PORT"),
        }),
      inject: [ConfigService],
    },

    // Servicios comunes
    CacheService,
    SessionService,
    LockService,
  ],
  exports: [
    PrismaService,
    REDIS_CLIENT,
    CacheService,
    SessionService,
    LockService,
    CacheModule,
  ],
})
export class CommonModule {}
```

---

## Checklist de Integración

### Setup inicial

- [ ] PrismaService configurado como provider global
- [ ] RedisModule con conexión ioredis
- [ ] CacheModule con redis store
- [ ] BullModule configurado para colas

### Por cada feature

- [ ] Controller con validación (class-validator)
- [ ] Service con lógica de negocio
- [ ] Repository con queries Prisma
- [ ] Cache en lecturas frecuentes
- [ ] Invalidación de cache en escrituras
- [ ] Colas para operaciones async pesadas

### Patrones a seguir

- [ ] Soft delete en Prisma (deletedAt)
- [ ] TTL con jitter en cache
- [ ] Sesiones en Redis Hash
- [ ] Rate limiting con Sorted Sets o ThrottlerModule
- [ ] Locks distribuidos para operaciones críticas

---

## Quick Reference: Qué skill consultar

| Tarea                 | Skill Principal | Archivo                |
| --------------------- | --------------- | ---------------------- |
| Crear módulo NestJS   | NestJS          | `02-modules.md`        |
| Query con relaciones  | Prisma 7        | `04-relations.md`      |
| Transacción DB        | Prisma 7        | `05-transactions.md`   |
| Cachear response      | Redis           | `20-cache-patterns.md` |
| Crear cola de trabajo | Redis           | `23-queues-bullmq.md`  |
| Sesiones de usuario   | Redis           | `11-hashes.md`         |
| Rate limiting         | Redis           | `14-sorted-sets.md`    |
| Eventos real-time     | Redis           | `15-streams.md`        |
| Soft delete           | Prisma 7        | `soft-delete.md`       |
| Health checks         | Redis           | `42-monitoring.md`     |
