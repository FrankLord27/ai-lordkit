# NestJS — Técnicas: Caching, Serialización, Versioning, Scheduling

**Fuente:** docs.nestjs.com/techniques

---

## Caching (@nestjs/cache-manager)

```bash
pnpm add @nestjs/cache-manager cache-manager
pnpm add cache-manager-redis-yet      # para Redis
```

```typescript
// app.module.ts
import { CacheModule } from '@nestjs/cache-manager';

@Module({
  imports: [
    CacheModule.registerAsync({
      isGlobal: true,
      useFactory: (config: ConfigService) => ({
        ttl: 60 * 1000,  // 60 segundos (en ms desde v5)
        max: 100,
      }),
      inject: [ConfigService],
    }),
  ],
})
```

### Redis Cache

```typescript
import { redisStore } from "cache-manager-redis-yet";

CacheModule.registerAsync({
  useFactory: async (config: ConfigService) => ({
    store: await redisStore({
      socket: {
        host: config.get("REDIS_HOST"),
        port: config.get("REDIS_PORT"),
      },
      ttl: 60 * 1000,
    }),
  }),
  inject: [ConfigService],
});
```

### Uso en servicio

```typescript
import { CACHE_MANAGER } from "@nestjs/cache-manager";
import { Cache } from "cache-manager";

@Injectable()
export class CatsService {
  constructor(@Inject(CACHE_MANAGER) private cacheManager: Cache) {}

  async findAll() {
    const cached = await this.cacheManager.get<Cat[]>("cats:all");
    if (cached) return cached;

    const cats = await this.db.cats.findMany();
    await this.cacheManager.set("cats:all", cats, 60 * 1000);
    return cats;
  }

  async invalidate() {
    await this.cacheManager.del("cats:all");
  }
}
```

### CacheInterceptor automático

```typescript
// En ruta: cachea la response por TTL configurado
@UseInterceptors(CacheInterceptor)
@CacheTTL(30000)      // override TTL para esta ruta (ms)
@CacheKey('all-cats') // clave personalizada
@Get()
findAll() {}
```

---

## Serialización (ClassSerializerInterceptor)

```typescript
// main.ts — global
app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));

// entity/user.entity.ts
import { Exclude, Expose, Transform, Type } from 'class-transformer';

export class UserEntity {
  id: string;
  name: string;

  @Exclude()           // nunca en la response
  password: string;

  @Exclude()
  refreshToken: string;

  @Expose({ name: 'fullName' })  // renombrar campo
  get displayName() {
    return `${this.name}`;
  }

  @Type(() => Date)
  @Transform(({ value }) => value.toISOString())
  createdAt: Date;
}

// controller — retornar instancia de entity (no objeto plano)
@Get(':id')
async findOne(@Param('id') id: string) {
  const user = await this.usersService.findOne(id);
  return new UserEntity(user);   // ← instanciar para que funcione @Exclude
}
```

---

## Versioning

```typescript
// main.ts
import { VersioningType } from '@nestjs/common';

app.enableVersioning({
  type: VersioningType.URI,       // /v1/cats, /v2/cats
  // type: VersioningType.HEADER, // Header: X-Api-Version: 1
  // type: VersioningType.MEDIA_TYPE, // Accept: application/json;v=1
  defaultVersion: '1',
});

// controller
@Controller({ version: '1', path: 'cats' })  // /v1/cats
export class CatsControllerV1 {}

@Controller({ version: '2', path: 'cats' })  // /v2/cats
export class CatsControllerV2 {}

// Por método
@Get()
@Version('2')
findAllV2() {}
```

---

## Task Scheduling (@nestjs/schedule)

```bash
pnpm add @nestjs/schedule
```

```typescript
// app.module.ts
import { ScheduleModule } from '@nestjs/schedule';
@Module({ imports: [ScheduleModule.forRoot()] })

// service
import { Injectable } from '@nestjs/common';
import { Cron, Interval, Timeout, CronExpression } from '@nestjs/schedule';

@Injectable()
export class TasksService {
  // Expresión cron
  @Cron('0 */2 * * * *')  // cada 2 minutos
  handleEvery2Minutes() {}

  // Usando constantes de CronExpression
  @Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
  handleDailyTask() {}

  @Cron(CronExpression.EVERY_HOUR)
  handleHourlyTask() {}

  // Intervalo fijo (ms)
  @Interval(10000)  // cada 10 segundos
  handleInterval() {}

  // Timeout (una vez)
  @Timeout(5000)    // 5 segundos después de bootstrap
  handleTimeout() {}
}

// Expresiones cron comunes:
// '* * * * * *'         → cada segundo
// '0 * * * * *'         → cada minuto (segundo 0)
// '0 0 * * * *'         → cada hora
// '0 0 0 * * *'         → cada día a medianoche
// '0 0 9 * * 1-5'       → cada día laboral a las 9am
// '0 0 0 1 * *'         → primer día de cada mes
```

---

## Queues (Bull)

```bash
pnpm add @nestjs/bull bull
pnpm add @types/bull -D
```

```typescript
// app.module.ts
import { BullModule } from "@nestjs/bull";

@Module({
  imports: [
    BullModule.forRoot({ connection: { host: "localhost", port: 6379 } }),
    BullModule.registerQueue({ name: "emails" }),
  ],
})
// producer
@Injectable()
export class EmailService {
  constructor(@InjectQueue("emails") private emailQueue: Queue) {}

  async sendWelcomeEmail(user: User) {
    await this.emailQueue.add(
      "welcome",
      { user },
      {
        attempts: 3,
        backoff: { type: "exponential", delay: 1000 },
      },
    );
  }
}

// consumer
@Processor("emails")
export class EmailProcessor {
  @Process("welcome")
  async handleWelcomeEmail(job: Job<{ user: User }>) {
    const { user } = job.data;
    // enviar email...
    console.log(`Sending welcome email to ${user.email}`);
  }
}
```

---

## Logging

```typescript
import { Logger } from "@nestjs/common";

@Injectable()
export class CatsService {
  private readonly logger = new Logger(CatsService.name);

  create(cat: Cat) {
    this.logger.log(`Creating cat: ${cat.name}`);
    this.logger.warn(`Warning: ${cat.name}`);
    this.logger.error(`Error creating cat`, error.stack);
    this.logger.debug(`Debug: ${JSON.stringify(cat)}`);
    this.logger.verbose(`Verbose: processing`);
  }
}

// Logger global en bootstrap
const app = await NestFactory.create(AppModule, {
  logger: ["log", "warn", "error"], // filtrar niveles
});
```
