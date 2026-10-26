# NestJS — Base de Datos: Prisma y TypeORM

> ⚠️ **Prisma 7:** los ejemplos con `new PrismaClient()` / `extends PrismaClient` asumen el setup v7 con **driver adapter** (`@prisma/adapter-pg`) y `prisma.config.ts` — sin adapter NO compilan. Setup completo en `prisma7-docs`.

## OPCIÓN A: Prisma (recomendado)

```bash
pnpm add @prisma/client
pnpm add -D prisma
npx prisma init
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

### PrismaModule (global)

```typescript
// prisma/prisma.module.ts
import { Global, Module } from "@nestjs/common";
import { PrismaService } from "./prisma.service";

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

### Schema Prisma típico

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(cuid())
  email     String   @unique
  password  String
  name      String
  role      Role     @default(USER)
  cars      Car[]
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@map("users")
}

model Car {
  id          String   @id @default(cuid())
  title       String
  description String?
  pricePerDay Decimal  @db.Decimal(10, 2)
  available   Boolean  @default(true)
  ownerId     String
  owner       User     @relation(fields: [ownerId], references: [id], onDelete: Cascade)
  images      String[]
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt

  @@map("cars")
}

enum Role {
  USER
  ADMIN
  PROVIDER
}
```

### Comandos Prisma esenciales

```bash
npx prisma migrate dev --name init       # crear migración en desarrollo
npx prisma migrate deploy                # aplicar migraciones en producción
npx prisma generate                      # regenerar Prisma Client
npx prisma studio                        # GUI para explorar datos
npx prisma db seed                       # correr seed
npx prisma db push                       # push schema sin migración (prototipos)
npx prisma migrate reset                 # reset completo (cuidado: borra datos)
```

### Operaciones CRUD con Prisma

```typescript
@Injectable()
export class CarsService {
  constructor(private prisma: PrismaService) {}

  // CREATE
  async create(data: CreateCarDto, ownerId: string) {
    return this.prisma.car.create({
      data: { ...data, ownerId },
      include: { owner: { select: { id: true, name: true } } },
    });
  }

  // READ - paginado
  async findAll(dto: PaginationDto) {
    const { page = 1, limit = 20, search } = dto;
    const skip = (page - 1) * limit;

    const where = search
      ? { title: { contains: search, mode: "insensitive" as const } }
      : {};

    const [data, total] = await this.prisma.$transaction([
      this.prisma.car.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: "desc" },
        include: { owner: { select: { id: true, name: true } } },
      }),
      this.prisma.car.count({ where }),
    ]);

    return {
      data,
      meta: { total, page, limit, totalPages: Math.ceil(total / limit) },
    };
  }

  // READ - uno
  async findOne(id: string) {
    const car = await this.prisma.car.findUnique({
      where: { id },
      include: { owner: true },
    });
    if (!car) throw new NotFoundException(`Car #${id} not found`);
    return car;
  }

  // UPDATE
  async update(id: string, data: UpdateCarDto, userId: string) {
    const car = await this.findOne(id);
    if (car.ownerId !== userId) throw new ForbiddenException();

    return this.prisma.car.update({
      where: { id },
      data,
    });
  }

  // DELETE
  async remove(id: string, userId: string) {
    const car = await this.findOne(id);
    if (car.ownerId !== userId) throw new ForbiddenException();

    return this.prisma.car.delete({ where: { id } });
  }
}
```

### Transacciones Prisma

```typescript
// Transacción interactiva (cuando necesitas resultados intermedios)
const result = await this.prisma.$transaction(async (tx) => {
  const booking = await tx.booking.create({ data: bookingData });
  await tx.car.update({
    where: { id: carId },
    data: { available: false },
  });
  return booking;
});

// Transacción batch (queries independientes)
const [cars, total] = await this.prisma.$transaction([
  this.prisma.car.findMany(),
  this.prisma.car.count(),
]);
```

### Errores Prisma comunes

```typescript
import { PrismaClientKnownRequestError } from "@prisma/client/runtime/library";

try {
  await this.prisma.user.create({ data });
} catch (e) {
  if (e instanceof PrismaClientKnownRequestError) {
    if (e.code === "P2002") {
      throw new ConflictException("Email already exists");
    }
    if (e.code === "P2025") {
      throw new NotFoundException("Record not found");
    }
  }
  throw e;
}
```

### Códigos de error Prisma

| Código | Descripción                    |
| ------ | ------------------------------ |
| P2002  | Unique constraint violation    |
| P2003  | Foreign key constraint failed  |
| P2025  | Record not found               |
| P2014  | Relation violation             |
| P2000  | Value too long for column type |

---

## OPCIÓN B: TypeORM

```bash
pnpm add @nestjs/typeorm typeorm pg
```

### Setup en AppModule

```typescript
import { TypeOrmModule } from '@nestjs/typeorm';

@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        url: config.get('DATABASE_URL'),
        entities: [__dirname + '/**/*.entity{.ts,.js}'],
        migrations: [__dirname + '/migrations/**/*{.ts,.js}'],
        synchronize: config.get('NODE_ENV') === 'development', // NUNCA en producción
        logging: config.get('NODE_ENV') === 'development',
      }),
    }),
  ],
})
```

### Entity TypeORM

```typescript
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  CreateDateColumn,
  UpdateDateColumn,
} from "typeorm";

@Entity("cars")
export class Car {
  @PrimaryGeneratedColumn("uuid")
  id: string;

  @Column()
  title: string;

  @Column({ nullable: true })
  description: string;

  @Column({ type: "decimal", precision: 10, scale: 2 })
  pricePerDay: number;

  @Column({ default: true })
  available: boolean;

  @ManyToOne(() => User, (user) => user.cars, { onDelete: "CASCADE" })
  owner: User;

  @Column()
  ownerId: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
```

### Repository TypeORM en módulo

```typescript
// cars.module.ts
@Module({
  imports: [TypeOrmModule.forFeature([Car])],
  controllers: [CarsController],
  providers: [CarsService],
})

// cars.service.ts
constructor(
  @InjectRepository(Car)
  private carRepository: Repository<Car>,
) {}

async findAll() {
  return this.carRepository.find({ relations: ['owner'] });
}

async findOne(id: string) {
  return this.carRepository.findOne({
    where: { id },
    relations: ['owner'],
  });
}
```

---

## Redis (caché)

```bash
pnpm add ioredis
```

```typescript
// redis/redis.module.ts
import { Module, Global } from '@nestjs/common';
import Redis from 'ioredis';

@Global()
@Module({
  providers: [
    {
      provide: 'REDIS_CLIENT',
      useFactory: (config: ConfigService) => {
        return new Redis({
          host: config.get('REDIS_HOST', 'localhost'),
          port: config.get<number>('REDIS_PORT', 6379),
        });
      },
      inject: [ConfigService],
    },
  ],
  exports: ['REDIS_CLIENT'],
})
export class RedisModule {}

// Uso en service:
constructor(@Inject('REDIS_CLIENT') private redis: Redis) {}

async getOrSet<T>(key: string, ttl: number, fetcher: () => Promise<T>): Promise<T> {
  const cached = await this.redis.get(key);
  if (cached) return JSON.parse(cached);

  const data = await fetcher();
  await this.redis.setex(key, ttl, JSON.stringify(data));
  return data;
}
```
