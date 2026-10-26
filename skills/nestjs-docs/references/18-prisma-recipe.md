# NestJS — Prisma 7 ORM

Integración de Prisma 7 con NestJS. Esta versión usa **driver adapters** obligatorios.

---

## Instalación (Prisma 7)

```bash
# Prisma 7 requiere driver adapters
pnpm add @prisma/client @prisma/adapter-pg pg
pnpm add -D prisma

npx prisma init
```

---

## schema.prisma (Prisma 7)

```prisma
// prisma/schema.prisma

generator client {
  provider   = "prisma-client"      // ← Nuevo nombre en v7
  output     = "../src/generated/prisma"
  engineType = "client"             // ← Requerido para driver adapters
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String    @id @default(uuid())
  email     String    @unique
  password  String
  name      String
  role      Role      @default(USER)
  createdAt DateTime  @default(now())
  updatedAt DateTime  @updatedAt
  deletedAt DateTime?
  posts     Post[]

  @@map("users")
}

model Post {
  id        String   @id @default(uuid())
  title     String
  content   String?
  published Boolean  @default(false)
  authorId  String
  author    User     @relation(fields: [authorId], references: [id])
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@map("posts")
}

enum Role {
  USER
  ADMIN
  SUPER_ADMIN
}
```

---

## PrismaService (Prisma 7 con driver adapter)

```typescript
// src/prisma/prisma.service.ts
import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  Logger,
} from "@nestjs/common";
import { PrismaClient } from "../generated/prisma/client.js"; // ← Ruta generada
import { PrismaPg } from "@prisma/adapter-pg";
import pg from "pg";

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    // Crear pool de conexiones
    const pool = new pg.Pool({
      connectionString: process.env.DATABASE_URL,
      max: 20, // Máximo de conexiones
      idleTimeoutMillis: 30000, // Cerrar conexiones idle
      connectionTimeoutMillis: 5000,
    });

    // Inicializar con driver adapter
    const adapter = new PrismaPg(pool);
    super({ adapter });
  }

  async onModuleInit() {
    try {
      await this.$connect();
      this.logger.log("Database connected");
    } catch (error) {
      this.logger.error("Database connection failed", error);
      throw error;
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
    this.logger.log("Database disconnected");
  }
}
```

## PrismaModule (global)

```typescript
// src/prisma/prisma.module.ts
import { Global, Module } from "@nestjs/common";
import { PrismaService } from "./prisma.service";

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
```

```typescript
// app.module.ts
@Module({
  imports: [PrismaModule, ...],
})
export class AppModule {}
```

## Uso en servicios

```typescript
@Injectable()
export class UsersService {
  constructor(private prisma: PrismaService) {}

  // Create
  async create(dto: CreateUserDto) {
    return this.prisma.user.create({ data: dto });
  }

  // FindAll con paginación
  async findAll(page = 1, limit = 10) {
    const skip = (page - 1) * limit;
    const [data, total] = await this.prisma.$transaction([
      this.prisma.user.findMany({ skip, take: limit }),
      this.prisma.user.count(),
    ]);
    return { data, total, page, limit };
  }

  // FindOne
  async findOne(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException(`User ${id} not found`);
    return user;
  }

  // Update
  async update(id: string, dto: UpdateUserDto) {
    return this.prisma.user.update({ where: { id }, data: dto });
  }

  // Delete (soft delete)
  async remove(id: string) {
    return this.prisma.user.update({
      where: { id },
      data: { deletedAt: new Date() },
    });
  }

  // Delete (hard delete)
  async hardDelete(id: string) {
    return this.prisma.user.delete({ where: { id } });
  }
}
```

## Queries con relaciones

```typescript
// Include relaciones
const userWithPosts = await this.prisma.user.findUnique({
  where: { id },
  include: { posts: true, profile: true },
});

// Select campos específicos
const userEmail = await this.prisma.user.findUnique({
  where: { id },
  select: { id: true, email: true, name: true },
});

// Filtros
const activeAdmins = await this.prisma.user.findMany({
  where: {
    role: "ADMIN",
    deletedAt: null,
    createdAt: { gte: new Date("2024-01-01") },
  },
  orderBy: { createdAt: "desc" },
});

// Búsqueda por texto
const users = await this.prisma.user.findMany({
  where: {
    OR: [
      { name: { contains: search, mode: "insensitive" } },
      { email: { contains: search, mode: "insensitive" } },
    ],
  },
});
```

## Transacciones

```typescript
// Transacción simple ($transaction)
const [newPost, updatedUser] = await this.prisma.$transaction([
  this.prisma.post.create({ data: { title, authorId: userId } }),
  this.prisma.user.update({
    where: { id: userId },
    data: { postCount: { increment: 1 } },
  }),
]);

// Transacción interactiva (rollback automático si hay error)
await this.prisma.$transaction(async (tx) => {
  const user = await tx.user.create({ data: { email } });
  await tx.wallet.create({ data: { userId: user.id, balance: 0 } });
  // Si cualquier línea falla, todo hace rollback
  return user;
});
```

## schema.prisma típico (Prisma 7)

```prisma
generator client {
  provider   = "prisma-client"       // ← v7: nuevo nombre
  output     = "../src/generated/prisma"
  engineType = "client"              // ← v7: requerido
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String    @id @default(uuid())
  email     String    @unique
  password  String
  name      String
  role      Role      @default(USER)
  createdAt DateTime  @default(now())
  updatedAt DateTime  @updatedAt
  deletedAt DateTime?
  posts     Post[]
  profile   Profile?

  @@index([email])
  @@index([deletedAt])
  @@map("users")
}

model Post {
  id        String   @id @default(uuid())
  title     String
  content   String?
  published Boolean  @default(false)
  authorId  String
  author    User     @relation(fields: [authorId], references: [id])
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@index([authorId])
  @@map("posts")
}

enum Role {
  USER
  ADMIN
  SUPER_ADMIN
}
```

## Comandos Prisma

```bash
npx prisma generate          # regenerar Prisma Client
npx prisma db push           # push schema a DB (dev sin migrations)
npx prisma migrate dev       # crear y aplicar migración
npx prisma migrate deploy    # aplicar migraciones en producción
npx prisma studio            # UI web para la base de datos
npx prisma db seed           # ejecutar seed
```

## Soft Delete con $extends (Prisma 7)

El middleware `$use()` ya no existe en Prisma 7. Usar `$extends()` en su lugar:

```typescript
// src/prisma/prisma.service.ts
import { PrismaClient } from "../generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";
import pg from "pg";

// Crear cliente base
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);

const basePrisma = new PrismaClient({ adapter });

// Extender con soft delete
export const prisma = basePrisma.$extends({
  name: "softDelete",
  model: {
    $allModels: {
      async softDelete<T>(this: T, id: string) {
        const context = Prisma.getExtensionContext(this);
        return (context as any).update({
          where: { id },
          data: { deletedAt: new Date() },
        });
      },
    },
  },
  query: {
    $allModels: {
      // Filtrar automáticamente registros eliminados en findMany/findFirst
      async findMany({ model, operation, args, query }) {
        args.where = { ...args.where, deletedAt: null };
        return query(args);
      },
      async findFirst({ model, operation, args, query }) {
        args.where = { ...args.where, deletedAt: null };
        return query(args);
      },
      async count({ model, operation, args, query }) {
        args.where = { ...args.where, deletedAt: null };
        return query(args);
      },
    },
  },
});

export type ExtendedPrismaClient = typeof prisma;
```

Uso:

```typescript
// Soft delete
await this.prisma.user.softDelete(userId);

// findMany automáticamente excluye eliminados
const activeUsers = await this.prisma.user.findMany();

// Para incluir eliminados, usar findManyUnfiltered (crear método custom)
```

---

## Paginación cursor-based

```typescript
async findAllCursor(cursor?: string, limit = 10) {
  return this.prisma.post.findMany({
    take: limit,
    skip: cursor ? 1 : 0,
    cursor: cursor ? { id: cursor } : undefined,
    orderBy: { createdAt: 'desc' },
  });
}
```

---

## Comandos Prisma 7

```bash
npx prisma generate          # Regenerar cliente (en output path)
npx prisma db push           # Push schema a DB (dev sin migrations)
npx prisma migrate dev       # Crear y aplicar migración
npx prisma migrate deploy    # Aplicar migraciones (producción)
npx prisma studio            # UI web para la base de datos
npx prisma db seed           # Ejecutar seed

# Nuevo en v7: configuración via prisma.config.ts
npx prisma init --config     # Crear prisma.config.ts
```

---

## prisma.config.ts (nuevo en v7)

```typescript
// prisma.config.ts
import { defineConfig } from "prisma/config";

export default defineConfig({
  earlyAccess: true,
  schema: "./prisma/schema.prisma",
});
```
