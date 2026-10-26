# 02 — Multi-Tenancy + Soft Delete

> ⚠️ **Prisma 7:** los ejemplos con `new PrismaClient()` / `extends PrismaClient` asumen el setup v7 con **driver adapter** (`@prisma/adapter-pg`) y `prisma.config.ts` — sin adapter NO compilan. Setup completo en `prisma7-docs`.

## Principio inquebrantable

**`tenantId` se obtiene del JWT en el backend, NUNCA del request body o query params.**

Si el cliente lo manda, lo ignorás. Si confiás en lo que manda el cliente, un atacante puede leer datos de otro tenant cambiando un UUID.

---

## Pattern obligatorio: Prisma Client Extension

En lugar de poner `tenantId` a mano en cada query (que se va a olvidar tarde o temprano), inyectarlo automáticamente:

```typescript
// shared/infrastructure/prisma/tenant.extension.ts
import { Prisma } from "@prisma/client";
import { AsyncLocalStorage } from "node:async_hooks";

export const tenantContext = new AsyncLocalStorage<{ tenantId: string }>();

const TENANT_MODELS = [
  "JournalEntry",
  "JournalLine",
  "Account",
  "Invoice",
  "Payment",
  "PosSession",
  "Product",
  "Customer",
  "Supplier",
  "CashShift",
  "AuditLog",
  // todos los modelos multi-tenant
] as const;

export const tenantExtension = Prisma.defineExtension({
  name: "tenant-isolation",
  query: {
    $allModels: {
      async $allOperations({ model, operation, args, query }) {
        if (!model || !TENANT_MODELS.includes(model as any)) {
          return query(args);
        }

        const ctx = tenantContext.getStore();
        if (!ctx?.tenantId) {
          throw new Error(`Tenant context missing for ${model}.${operation}`);
        }

        // READ: inyectar where.tenantId + where.deletedAt
        if (
          [
            "findUnique",
            "findFirst",
            "findMany",
            "count",
            "aggregate",
          ].includes(operation)
        ) {
          args.where = {
            ...(args.where ?? {}),
            tenantId: ctx.tenantId,
            deletedAt: null,
          };
        }

        // WRITE create: inyectar data.tenantId
        if (["create", "createMany"].includes(operation)) {
          if (operation === "create") {
            args.data = { ...args.data, tenantId: ctx.tenantId };
          } else {
            args.data = args.data.map((d: any) => ({
              ...d,
              tenantId: ctx.tenantId,
            }));
          }
        }

        // UPDATE / DELETE: garantizar tenantId en where
        if (
          ["update", "updateMany", "delete", "deleteMany"].includes(operation)
        ) {
          args.where = {
            ...(args.where ?? {}),
            tenantId: ctx.tenantId,
          };
        }

        return query(args);
      },
    },
  },
});
```

## Activación en NestJS

```typescript
// shared/infrastructure/prisma/prisma.service.ts
import { Injectable, OnModuleInit } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";
import { tenantExtension } from "./tenant.extension";

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  async onModuleInit() {
    await this.$connect();
  }
}

// Exportar cliente extendido
export const ExtendedPrismaProvider = {
  provide: "PRISMA",
  useFactory: (prisma: PrismaService) => prisma.$extends(tenantExtension),
  inject: [PrismaService],
};
```

## Middleware que activa el contexto

```typescript
// shared/presentation/middleware/tenant-context.middleware.ts
import { Injectable, NestMiddleware } from "@nestjs/common";
import { tenantContext } from "../../infrastructure/prisma/tenant.extension";

@Injectable()
export class TenantContextMiddleware implements NestMiddleware {
  use(req: any, _res: any, next: () => void) {
    const tenantId = req.user?.tenantId; // viene del JWT validado
    if (!tenantId) return next(); // rutas públicas no necesitan
    tenantContext.run({ tenantId }, () => next());
  }
}
```

---

## Soft Delete: regla unificada

Cada modelo multi-tenant tiene `deletedAt: DateTime?`. La extension ya filtra `deletedAt: null` en lecturas.

```prisma
model Product {
  id        String    @id @default(uuid())
  tenantId  String
  sku       String
  // ...
  deletedAt DateTime?

  @@unique([tenantId, sku])  // ojo: el unique debe incluir tenantId
  @@index([tenantId, deletedAt])
}
```

### Borrar = marcar deletedAt

```typescript
// en lugar de prisma.product.delete(...)
await prisma.product.update({
  where: { id: productId },
  data: { deletedAt: new Date() },
});
```

### Restaurar = poner deletedAt en null

Solo accesible para roles `ADMIN`. Bypass de la extension:

```typescript
async restore(id: string) {
  return this.prisma.$transaction(async (tx) => {
    return tx.product.update({
      where: { id }, // sin filtro tenantId — solo ADMIN
      data: { deletedAt: null },
    });
  });
}
```

---

## Restricciones `@unique` con tenant

Mal:

```prisma
sku String @unique  // ❌ no permite dos tenants con mismo SKU
```

Bien:

```prisma
@@unique([tenantId, sku])  // ✅ aislamiento real
```

Aplicalo a: SKU, número de factura, código de cuenta contable, RNC de cliente, email de usuario por tenant, etc.

---

## RLS (Row-Level Security) en PostgreSQL — opcional pero recomendado

Segunda barrera para auditoría. Aunque la app falle, la DB rechaza:

```sql
ALTER TABLE "Product" ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON "Product"
  USING ("tenantId" = current_setting('app.current_tenant')::uuid);
```

Y en la conexión Prisma, setear:

```typescript
await prisma.$executeRaw`SET LOCAL app.current_tenant = ${tenantId}`;
```

> **Nota:** RLS es complejo de mantener con Prisma. Para empezar, basta con la Client Extension. RLS se agrega cuando el sistema sea crítico (banca, salud).

---

## Tests que protegen el aislamiento

```typescript
describe("Multi-tenant isolation", () => {
  it("does not leak data from tenant A to tenant B", async () => {
    const productA = await createProductForTenant("tenant-a");

    await tenantContext.run({ tenantId: "tenant-b" }, async () => {
      const result = await prisma.product.findUnique({
        where: { id: productA.id },
      });
      expect(result).toBeNull();
    });
  });

  it("throws if tenant context is missing", async () => {
    await expect(prisma.product.findMany()).rejects.toThrow(
      /Tenant context missing/,
    );
  });
});
```

---

## Antipatrones comunes

| Antipatrón                               | Por qué falla                        | Reemplazo                                     |
| ---------------------------------------- | ------------------------------------ | --------------------------------------------- |
| `where: { tenantId: req.body.tenantId }` | Atacante manipula el body            | `tenantId` del JWT vía middleware             |
| `findMany()` sin filtro                  | Devuelve todo de todos los tenants   | Extension obligatoria                         |
| `@unique` sin tenant                     | Bloquea SKUs entre tenants distintos | `@@unique([tenantId, sku])`                   |
| `prisma.product.delete(...)`             | Pierde auditoría                     | `update({ data: { deletedAt: new Date() } })` |
| Restaurar sin chequear rol               | Cualquiera revive datos eliminados   | Solo `ADMIN`, registro en `AuditLog`          |
