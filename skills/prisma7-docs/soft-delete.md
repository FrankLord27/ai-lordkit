# Prisma 7 — Soft Delete

Patrón completo de soft delete usando `$extends()` de Prisma 7.

---

## Concepto

En vez de eliminar registros físicamente (`DELETE`), los marcamos con `deletedAt`:

```sql
-- Hard delete (peligroso, irreversible)
DELETE FROM users WHERE id = '123';

-- Soft delete (seguro, recuperable)
UPDATE users SET deleted_at = NOW() WHERE id = '123';
```

---

## Schema con soporte para soft delete

```prisma
// prisma/schema.prisma
model User {
  id        String    @id @default(uuid())
  email     String    @unique
  name      String
  createdAt DateTime  @default(now())
  updatedAt DateTime  @updatedAt
  deletedAt DateTime? // ← Campo para soft delete

  @@index([deletedAt])
  @@map("users")
}

model Post {
  id        String    @id @default(uuid())
  title     String
  authorId  String
  createdAt DateTime  @default(now())
  updatedAt DateTime  @updatedAt
  deletedAt DateTime?

  @@index([deletedAt])
  @@index([authorId, deletedAt])
  @@map("posts")
}
```

---

## Extensión de soft delete con $extends()

```typescript
// src/prisma/soft-delete.extension.ts
import { Prisma, PrismaClient } from "../generated/prisma/client.js";

// Modelos que soportan soft delete
const SOFT_DELETE_MODELS = ["User", "Post", "Comment", "Ticket"] as const;
type SoftDeleteModel = (typeof SOFT_DELETE_MODELS)[number];

function isSoftDeleteModel(model: string): model is SoftDeleteModel {
  return SOFT_DELETE_MODELS.includes(model as SoftDeleteModel);
}

export function softDeleteExtension(prisma: PrismaClient) {
  return prisma.$extends({
    name: "softDelete",

    model: {
      // Método softDelete en todos los modelos
      $allModels: {
        async softDelete<T, A>(
          this: T,
          where: Prisma.Args<T, "update">["where"],
        ): Promise<Prisma.Result<T, A, "update">> {
          const context = Prisma.getExtensionContext(this);
          return (context as any).update({
            where,
            data: { deletedAt: new Date() },
          });
        },

        async softDeleteMany<T, A>(
          this: T,
          where: Prisma.Args<T, "updateMany">["where"],
        ): Promise<Prisma.Result<T, A, "updateMany">> {
          const context = Prisma.getExtensionContext(this);
          return (context as any).updateMany({
            where,
            data: { deletedAt: new Date() },
          });
        },

        async restore<T, A>(
          this: T,
          where: Prisma.Args<T, "update">["where"],
        ): Promise<Prisma.Result<T, A, "update">> {
          const context = Prisma.getExtensionContext(this);
          return (context as any).update({
            where,
            data: { deletedAt: null },
          });
        },
      },
    },

    query: {
      $allModels: {
        // Filtrar automáticamente en findMany
        async findMany({ model, operation, args, query }) {
          if (isSoftDeleteModel(model)) {
            args.where = { ...args.where, deletedAt: null };
          }
          return query(args);
        },

        // Filtrar en findFirst
        async findFirst({ model, operation, args, query }) {
          if (isSoftDeleteModel(model)) {
            args.where = { ...args.where, deletedAt: null };
          }
          return query(args);
        },

        // Filtrar en findUnique
        async findUnique({ model, operation, args, query }) {
          if (isSoftDeleteModel(model)) {
            // findUnique no permite where adicionales
            // Convertir a findFirst con el mismo where
            const context = Prisma.getExtensionContext(this);
            return (context as any).findFirst({
              where: { ...args.where, deletedAt: null },
              include: args.include,
              select: args.select,
            });
          }
          return query(args);
        },

        // Filtrar en count
        async count({ model, operation, args, query }) {
          if (isSoftDeleteModel(model)) {
            args.where = { ...args.where, deletedAt: null };
          }
          return query(args);
        },

        // Filtrar en aggregate
        async aggregate({ model, operation, args, query }) {
          if (isSoftDeleteModel(model)) {
            args.where = { ...args.where, deletedAt: null };
          }
          return query(args);
        },
      },
    },
  });
}
```

---

## Integración con PrismaService

```typescript
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient } from "../generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";
import pg from "pg";
import { softDeleteExtension } from "./soft-delete.extension";

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
});

const basePrisma = new PrismaClient({
  adapter: new PrismaPg(pool),
});

// Aplicar extensión
const extendedPrisma = softDeleteExtension(basePrisma);

export type ExtendedPrismaClient = typeof extendedPrisma;

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  readonly client = extendedPrisma;

  // Proxy para acceder como this.prisma.user en vez de this.prisma.client.user
  get user() {
    return this.client.user;
  }
  get post() {
    return this.client.post;
  }
  // ... agregar todos los modelos

  async onModuleInit() {
    await this.client.$connect();
  }

  async onModuleDestroy() {
    await this.client.$disconnect();
  }
}
```

---

## Uso en Services

```typescript
// modules/users/users.service.ts
@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  // findMany automáticamente excluye eliminados
  async findAll(): Promise<User[]> {
    return this.prisma.user.findMany();
    // SQL: SELECT * FROM users WHERE deleted_at IS NULL
  }

  // findOne también excluye eliminados
  async findOne(id: string): Promise<User | null> {
    return this.prisma.user.findUnique({ where: { id } });
  }

  // Soft delete
  async remove(id: string): Promise<User> {
    return this.prisma.user.softDelete({ id });
    // SQL: UPDATE users SET deleted_at = NOW() WHERE id = ?
  }

  // Soft delete múltiple
  async removeMany(ids: string[]): Promise<{ count: number }> {
    return this.prisma.user.softDeleteMany({
      id: { in: ids },
    });
  }

  // Restaurar
  async restore(id: string): Promise<User> {
    return this.prisma.user.restore({ id });
    // SQL: UPDATE users SET deleted_at = NULL WHERE id = ?
  }

  // Hard delete (bypass de extensión)
  async hardDelete(id: string): Promise<void> {
    // Usar cliente base sin extensión
    await basePrisma.user.delete({ where: { id } });
  }
}
```

---

## Queries que incluyen eliminados

A veces necesitas ver registros eliminados (admin, auditoría):

```typescript
// Opción 1: Método específico sin filtro
export function withDeletedExtension(prisma: PrismaClient) {
  return prisma.$extends({
    model: {
      $allModels: {
        async findManyWithDeleted<T, A>(
          this: T,
          args?: Prisma.Args<T, "findMany">,
        ): Promise<Prisma.Result<T, A, "findMany">> {
          const context = Prisma.getExtensionContext(this);
          // No agregar filtro de deletedAt
          return (context as any).findMany(args);
        },

        async findDeleted<T, A>(
          this: T,
          args?: Prisma.Args<T, "findMany">,
        ): Promise<Prisma.Result<T, A, "findMany">> {
          const context = Prisma.getExtensionContext(this);
          return (context as any).findMany({
            ...args,
            where: { ...args?.where, deletedAt: { not: null } },
          });
        },
      },
    },
  });
}

// Uso:
const allUsers = await this.prisma.user.findManyWithDeleted();
const deletedUsers = await this.prisma.user.findDeleted();
```

---

## Soft delete en cascada

Cuando eliminas un usuario, también eliminar sus posts:

```typescript
async softDeleteWithCascade(userId: string): Promise<void> {
  await this.prisma.$transaction([
    this.prisma.post.softDeleteMany({ authorId: userId }),
    this.prisma.comment.softDeleteMany({ userId }),
    this.prisma.user.softDelete({ id: userId }),
  ]);
}
```

---

## Índices recomendados

```prisma
model User {
  // ...
  deletedAt DateTime?

  // Índice para queries de activos (deletedAt IS NULL)
  @@index([deletedAt])

  // Índices compuestos para queries comunes
  @@index([email, deletedAt])
  @@index([tenantId, deletedAt])
}
```

---

## Limpieza de registros eliminados (hard delete programado)

```typescript
// Cron job para limpiar registros eliminados hace más de 30 días
@Cron('0 3 * * *') // Cada día a las 3am
async cleanupDeletedRecords() {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - 30);

  // Usar cliente base para hard delete
  const result = await basePrisma.user.deleteMany({
    where: {
      deletedAt: { lt: cutoff },
    },
  });

  this.logger.log(`Cleaned up ${result.count} deleted users`);
}
```

---

## Checklist

- [ ] Agregar campo `deletedAt DateTime?` a modelos relevantes
- [ ] Agregar índice `@@index([deletedAt])`
- [ ] Implementar extensión con `$extends()`
- [ ] Usar `softDelete()` en vez de `delete()`
- [ ] Verificar que queries filtran automáticamente
- [ ] Crear métodos para ver/restaurar eliminados (admin)
- [ ] Configurar limpieza periódica de registros viejos
