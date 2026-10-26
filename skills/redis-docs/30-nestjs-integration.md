# Redis — Integración Completa con NestJS

## Arquitectura

```
┌────────────────────────────────────────────┐
│                NestJS App                  │
├────────────────────────────────────────────┤
│  CacheModule │ BullModule │ RedisModule   │
│  (API Cache) │  (Queues)  │ (Sessions,    │
│              │            │  Locks, etc)  │
└──────────────┴────────────┴───────────────┘
                     │
              ┌──────┴──────┐
              │    Redis    │
              └─────────────┘
```

## 1. RedisModule Base

```typescript
// common/redis/redis.module.ts
import { Global, Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";

export const REDIS_CLIENT = "REDIS_CLIENT";

@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      useFactory: (config: ConfigService) => {
        const redis = new Redis({
          host: config.get("REDIS_HOST", "localhost"),
          port: config.get("REDIS_PORT", 6379),
          password: config.get("REDIS_PASSWORD"),
        });
        redis.on("error", (err) => console.error("Redis error:", err));
        return redis;
      },
      inject: [ConfigService],
    },
  ],
  exports: [REDIS_CLIENT],
})
export class RedisModule {}
```

## 2. CacheModule

```bash
pnpm add @nestjs/cache-manager cache-manager cache-manager-ioredis-yet
```

```typescript
// app.module.ts
import { CacheModule } from "@nestjs/cache-manager";
import { redisStore } from "cache-manager-ioredis-yet";

@Module({
  imports: [
    CacheModule.registerAsync({
      isGlobal: true,
      useFactory: async (config: ConfigService) => ({
        store: await redisStore({
          host: config.get("REDIS_HOST"),
          port: config.get("REDIS_PORT"),
          password: config.get("REDIS_PASSWORD"),
          ttl: 300 * 1000,
        }),
      }),
      inject: [ConfigService],
    }),
  ],
})
export class AppModule {}
```

### Uso con Interceptor

```typescript
@Controller("products")
@UseInterceptors(CacheInterceptor)
export class ProductsController {
  @Get()
  @CacheTTL(600 * 1000)
  @CacheKey("products:all")
  findAll() {
    return this.productsService.findAll();
  }
}
```

### Uso manual

```typescript
@Injectable()
export class ProductsService {
  constructor(@Inject(CACHE_MANAGER) private cache: Cache) {}

  async findAll(): Promise<Product[]> {
    const cached = await this.cache.get<Product[]>("products:all");
    if (cached) return cached;

    const products = await this.prisma.product.findMany();
    await this.cache.set("products:all", products, 300 * 1000);
    return products;
  }
}
```

## 3. SessionService

```typescript
@Injectable()
export class SessionService {
  constructor(@Inject(REDIS_CLIENT) private redis: Redis) {}

  async create(
    sessionId: string,
    data: UserSession,
    ttl = 86400,
  ): Promise<void> {
    await this.redis.hset(
      `session:${sessionId}`,
      data as Record<string, string>,
    );
    await this.redis.expire(`session:${sessionId}`, ttl);
  }

  async get(sessionId: string): Promise<UserSession | null> {
    const data = await this.redis.hgetall(`session:${sessionId}`);
    return Object.keys(data).length > 0
      ? (data as unknown as UserSession)
      : null;
  }

  async refresh(sessionId: string, ttl = 86400): Promise<void> {
    await this.redis.expire(`session:${sessionId}`, ttl);
  }

  async destroy(sessionId: string): Promise<void> {
    await this.redis.del(`session:${sessionId}`);
  }
}
```

## 4. LockService

```typescript
@Injectable()
export class LockService {
  constructor(@Inject(REDIS_CLIENT) private redis: Redis) {}

  async acquire(
    resource: string,
    ttl = 30,
  ): Promise<{ acquired: boolean; token: string }> {
    const token = crypto.randomUUID();
    const result = await this.redis.set(
      `lock:${resource}`,
      token,
      "EX",
      ttl,
      "NX",
    );
    return { acquired: result === "OK", token };
  }

  async release(resource: string, token: string): Promise<boolean> {
    const script = `if redis.call('GET',KEYS[1])==ARGV[1] then return redis.call('DEL',KEYS[1]) end return 0`;
    return (await this.redis.eval(script, 1, `lock:${resource}`, token)) === 1;
  }

  async withLock<T>(
    resource: string,
    fn: () => Promise<T>,
    opts = { ttl: 30, retries: 3 },
  ): Promise<T> {
    for (let i = 0; i < opts.retries; i++) {
      const { acquired, token } = await this.acquire(resource, opts.ttl);
      if (acquired) {
        try {
          return await fn();
        } finally {
          await this.release(resource, token);
        }
      }
      await new Promise((r) => setTimeout(r, 100 * Math.pow(2, i)));
    }
    throw new Error(`Failed to acquire lock on ${resource}`);
  }
}
```

## 5. Rate Limiting

```bash
pnpm add @nestjs/throttler
```

```typescript
import { ThrottlerModule, ThrottlerGuard } from "@nestjs/throttler";
import { ThrottlerStorageRedisService } from "@nestjs/throttler";

@Module({
  imports: [
    ThrottlerModule.forRootAsync({
      useFactory: (config: ConfigService) => ({
        throttlers: [
          { name: "short", ttl: 1000, limit: 3 },
          { name: "medium", ttl: 10000, limit: 20 },
          { name: "long", ttl: 60000, limit: 100 },
        ],
        storage: new ThrottlerStorageRedisService(
          new Redis({
            host: config.get("REDIS_HOST"),
            port: config.get("REDIS_PORT"),
          }),
        ),
      }),
      inject: [ConfigService],
    }),
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
```

```typescript
// Personalizar por endpoint
@Post('login')
@Throttle({ short: { limit: 5, ttl: 60000 } }) // 5 intentos/min
login(@Body() dto: LoginDto) { }

@Get('me')
@SkipThrottle() // Sin límite
getProfile() { }
```

## 6. EventBusService (Pub/Sub)

```typescript
@Injectable()
export class EventBusService implements OnModuleInit, OnModuleDestroy {
  private subscriber: Redis;
  private handlers = new Map<string, ((data: any) => void)[]>();

  constructor(@Inject(REDIS_CLIENT) private publisher: Redis) {
    this.subscriber = this.publisher.duplicate();
  }

  onModuleInit() {
    this.subscriber.on("message", (channel, message) => {
      (this.handlers.get(channel) ?? []).forEach((h) => h(JSON.parse(message)));
    });
  }

  async publish(channel: string, data: any): Promise<number> {
    return this.publisher.publish(channel, JSON.stringify(data));
  }

  subscribe(channel: string, handler: (data: any) => void): () => void {
    const handlers = this.handlers.get(channel) ?? [];
    if (!handlers.length) this.subscriber.subscribe(channel);
    this.handlers.set(channel, [...handlers, handler]);
    return () => {
      const current =
        this.handlers.get(channel)?.filter((h) => h !== handler) ?? [];
      if (!current.length) {
        this.subscriber.unsubscribe(channel);
        this.handlers.delete(channel);
      } else this.handlers.set(channel, current);
    };
  }

  async onModuleDestroy() {
    await this.subscriber.quit();
  }
}
```

## 7. Módulo Integrado

```typescript
// common/common.module.ts
@Global()
@Module({
  imports: [RedisModule],
  providers: [SessionService, LockService, EventBusService],
  exports: [RedisModule, SessionService, LockService, EventBusService],
})
export class CommonModule {}
```

## Health Check

```typescript
@Injectable()
export class RedisHealthIndicator extends HealthIndicator {
  constructor(@Inject(REDIS_CLIENT) private redis: Redis) {
    super();
  }

  async isHealthy(key: string): Promise<HealthIndicatorResult> {
    try {
      const start = Date.now();
      await this.redis.ping();
      return this.getStatus(key, true, { latency: `${Date.now() - start}ms` });
    } catch (error) {
      throw new HealthCheckError("Redis failed", this.getStatus(key, false));
    }
  }
}
```
