# Prisma 7 — Audit Logging

Registrar automáticamente quién creó/modificó cada registro y cuándo.

---

## Campos de auditoría en el schema

```prisma
model Ticket {
  id          String   @id @default(uuid())
  title       String
  description String?
  status      Status   @default(OPEN)

  // Campos de auditoría
  createdAt   DateTime @default(now())
  createdById String
  createdBy   User     @relation("TicketsCreated", fields: [createdById], references: [id])

  updatedAt   DateTime @updatedAt
  updatedById String?
  updatedBy   User?    @relation("TicketsUpdated", fields: [updatedById], references: [id])

  // Multi-tenant
  tenantId    String
  tenant      Tenant   @relation(fields: [tenantId], references: [id])

  @@index([tenantId])
  @@index([createdById])
  @@map("tickets")
}

model User {
  id              String   @id @default(uuid())
  email           String   @unique

  // Relaciones inversas de auditoría
  ticketsCreated  Ticket[] @relation("TicketsCreated")
  ticketsUpdated  Ticket[] @relation("TicketsUpdated")

  @@map("users")
}
```

---

## Extensión de auditoría con $extends()

```typescript
// src/prisma/audit.extension.ts
import { Prisma, PrismaClient } from "../generated/prisma/client.js";
import { ClsService } from "nestjs-cls";

// Modelos que requieren auditoría
const AUDITED_MODELS = ["Ticket", "Asset", "Comment"] as const;

export function auditExtension(prisma: PrismaClient, cls: ClsService) {
  return prisma.$extends({
    name: "audit",

    query: {
      $allModels: {
        // Inyectar createdById en create
        async create({ model, operation, args, query }) {
          if (AUDITED_MODELS.includes(model as any)) {
            const userId = cls.get("userId");
            const tenantId = cls.get("tenantId");

            if (userId) {
              args.data = {
                ...args.data,
                createdById: userId,
              };
            }

            if (tenantId && !args.data.tenantId) {
              args.data = {
                ...args.data,
                tenantId,
              };
            }
          }
          return query(args);
        },

        // Inyectar en createMany
        async createMany({ model, operation, args, query }) {
          if (AUDITED_MODELS.includes(model as any)) {
            const userId = cls.get("userId");
            const tenantId = cls.get("tenantId");

            if (Array.isArray(args.data)) {
              args.data = args.data.map((item) => ({
                ...item,
                ...(userId && { createdById: userId }),
                ...(tenantId && !item.tenantId && { tenantId }),
              }));
            }
          }
          return query(args);
        },

        // Inyectar updatedById en update
        async update({ model, operation, args, query }) {
          if (AUDITED_MODELS.includes(model as any)) {
            const userId = cls.get("userId");

            if (userId) {
              args.data = {
                ...args.data,
                updatedById: userId,
              };
            }
          }
          return query(args);
        },

        // Inyectar en updateMany
        async updateMany({ model, operation, args, query }) {
          if (AUDITED_MODELS.includes(model as any)) {
            const userId = cls.get("userId");

            if (userId) {
              args.data = {
                ...args.data,
                updatedById: userId,
              };
            }
          }
          return query(args);
        },
      },
    },
  });
}
```

---

## Configuración de Context Local Storage (CLS)

```bash
pnpm add nestjs-cls
```

```typescript
// app.module.ts
import { ClsModule } from "nestjs-cls";

@Module({
  imports: [
    ClsModule.forRoot({
      global: true,
      middleware: {
        mount: true,
        setup: (cls, req) => {
          // El guard de auth ya habrá seteado req.user
          cls.set("userId", req.user?.sub);
          cls.set("tenantId", req.user?.tenantId);
        },
      },
    }),
  ],
})
export class AppModule {}
```

---

## Integración completa

```typescript
// src/prisma/prisma.service.ts
import { Injectable, OnModuleInit, OnModuleDestroy } from "@nestjs/common";
import { PrismaClient } from "../generated/prisma/client.js";
import { PrismaPg } from "@prisma/adapter-pg";
import { ClsService } from "nestjs-cls";
import pg from "pg";
import { softDeleteExtension } from "./soft-delete.extension";
import { auditExtension } from "./audit.extension";

@Injectable()
export class PrismaService implements OnModuleInit, OnModuleDestroy {
  public client: ReturnType<typeof this.createClient>;

  constructor(private readonly cls: ClsService) {
    this.client = this.createClient();
  }

  private createClient() {
    const pool = new pg.Pool({
      connectionString: process.env.DATABASE_URL,
    });

    const basePrisma = new PrismaClient({
      adapter: new PrismaPg(pool),
    });

    // Encadenar extensiones
    return basePrisma
      .$extends(softDeleteExtension)
      .$extends(auditExtension(basePrisma, this.cls));
  }

  async onModuleInit() {
    await this.client.$connect();
  }

  async onModuleDestroy() {
    await this.client.$disconnect();
  }
}
```

---

## Tabla de Audit Log (historial completo)

Para auditoría más detallada, crear una tabla separada:

```prisma
model AuditLog {
  id         String   @id @default(uuid())
  tableName  String
  recordId   String
  action     Action
  oldValues  Json?
  newValues  Json?
  userId     String
  user       User     @relation(fields: [userId], references: [id])
  tenantId   String
  ipAddress  String?
  userAgent  String?
  createdAt  DateTime @default(now())

  @@index([tableName, recordId])
  @@index([userId])
  @@index([tenantId])
  @@index([createdAt])
  @@map("audit_logs")
}

enum Action {
  CREATE
  UPDATE
  DELETE
  RESTORE
}
```

### Extensión de audit log completo

```typescript
// src/prisma/audit-log.extension.ts
import { Prisma, PrismaClient } from "../generated/prisma/client.js";
import { ClsService } from "nestjs-cls";

export function auditLogExtension(prisma: PrismaClient, cls: ClsService) {
  return prisma.$extends({
    name: "auditLog",

    query: {
      $allModels: {
        async create({ model, operation, args, query }) {
          const result = await query(args);

          await logAudit(prisma, cls, {
            tableName: model,
            recordId: (result as any).id,
            action: "CREATE",
            newValues: result,
          });

          return result;
        },

        async update({ model, operation, args, query }) {
          // Obtener valores anteriores
          const context = Prisma.getExtensionContext(this);
          const oldRecord = await (context as any).findUnique({
            where: args.where,
          });

          const result = await query(args);

          await logAudit(prisma, cls, {
            tableName: model,
            recordId: (result as any).id,
            action: "UPDATE",
            oldValues: oldRecord,
            newValues: result,
          });

          return result;
        },

        async delete({ model, operation, args, query }) {
          // Obtener valores antes de eliminar
          const context = Prisma.getExtensionContext(this);
          const oldRecord = await (context as any).findUnique({
            where: args.where,
          });

          const result = await query(args);

          await logAudit(prisma, cls, {
            tableName: model,
            recordId: (oldRecord as any).id,
            action: "DELETE",
            oldValues: oldRecord,
          });

          return result;
        },
      },
    },
  });
}

async function logAudit(
  prisma: PrismaClient,
  cls: ClsService,
  data: {
    tableName: string;
    recordId: string;
    action: "CREATE" | "UPDATE" | "DELETE" | "RESTORE";
    oldValues?: unknown;
    newValues?: unknown;
  },
) {
  const userId = cls.get("userId");
  const tenantId = cls.get("tenantId");
  const ipAddress = cls.get("ipAddress");
  const userAgent = cls.get("userAgent");

  if (!userId || !tenantId) return;

  // Usar setTimeout para no bloquear la respuesta
  setImmediate(async () => {
    try {
      await prisma.auditLog.create({
        data: {
          tableName: data.tableName,
          recordId: data.recordId,
          action: data.action,
          oldValues: data.oldValues
            ? JSON.parse(JSON.stringify(data.oldValues))
            : null,
          newValues: data.newValues
            ? JSON.parse(JSON.stringify(data.newValues))
            : null,
          userId,
          tenantId,
          ipAddress,
          userAgent,
        },
      });
    } catch (error) {
      console.error("Failed to create audit log:", error);
    }
  });
}
```

---

## Consultar historial de auditoría

```typescript
// modules/audit/audit.service.ts
@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  // Historial de un registro específico
  async getRecordHistory(tableName: string, recordId: string) {
    return this.prisma.auditLog.findMany({
      where: { tableName, recordId },
      include: { user: { select: { id: true, name: true, email: true } } },
      orderBy: { createdAt: "desc" },
    });
  }

  // Actividad de un usuario
  async getUserActivity(userId: string, limit = 50) {
    return this.prisma.auditLog.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
      take: limit,
    });
  }

  // Actividad reciente del tenant
  async getTenantActivity(tenantId: string, since: Date) {
    return this.prisma.auditLog.findMany({
      where: {
        tenantId,
        createdAt: { gte: since },
      },
      include: { user: { select: { name: true } } },
      orderBy: { createdAt: "desc" },
    });
  }

  // Ver cambios específicos de un campo
  async getFieldChanges(
    tableName: string,
    recordId: string,
    fieldName: string,
  ) {
    const logs = await this.getRecordHistory(tableName, recordId);

    return logs
      .filter((log) => {
        const oldVal = (log.oldValues as any)?.[fieldName];
        const newVal = (log.newValues as any)?.[fieldName];
        return oldVal !== newVal;
      })
      .map((log) => ({
        changedAt: log.createdAt,
        changedBy: log.user,
        oldValue: (log.oldValues as any)?.[fieldName],
        newValue: (log.newValues as any)?.[fieldName],
      }));
  }
}
```

---

## Setear contexto en el middleware

```typescript
// common/middleware/audit-context.middleware.ts
import { Injectable, NestMiddleware } from "@nestjs/common";
import { ClsService } from "nestjs-cls";
import { Request, Response, NextFunction } from "express";

@Injectable()
export class AuditContextMiddleware implements NestMiddleware {
  constructor(private readonly cls: ClsService) {}

  use(req: Request, res: Response, next: NextFunction) {
    // IP del cliente (considerando proxies)
    const ip = req.headers["x-forwarded-for"] || req.socket.remoteAddress;
    this.cls.set("ipAddress", Array.isArray(ip) ? ip[0] : ip);

    // User agent
    this.cls.set("userAgent", req.headers["user-agent"]);

    next();
  }
}
```

---

## Checklist

- [ ] Agregar campos `createdAt`, `createdById`, `updatedAt`, `updatedById`
- [ ] Configurar nestjs-cls para contexto de request
- [ ] Implementar extensión de auditoría
- [ ] Crear tabla AuditLog para historial completo
- [ ] API para consultar historial de cambios
- [ ] Limpiar logs viejos periódicamente (GDPR)
