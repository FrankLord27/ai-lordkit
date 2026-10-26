# Arquitectura Multi-Tenant — Aislamiento de Datos

Este documento cubre estrategias de multi-tenancy para aplicaciones SaaS B2B.
**Es opcional** — solo implementar si el proyecto lo requiere.

---

## ¿Necesitas multi-tenancy?

| Tipo de proyecto             | Multi-tenant | Ejemplo                         |
| ---------------------------- | ------------ | ------------------------------- |
| SaaS B2B                     | ✅ Sí        | Helpdesk (múltiples empresas)   |
| Marketplace con proveedores  | ✅ Sí        | Renta de autos (proveedores)    |
| App B2C con usuarios         | ❌ No        | App de notas personal           |
| App interna de una empresa   | ❌ No        | Dashboard interno               |
| Proyecto con un solo cliente | ❌ No        | Sitio web corporativo           |

**Regla:** Si múltiples organizaciones/empresas usan la misma instancia y sus datos deben estar completamente aislados → multi-tenant.

---

## Estrategias de aislamiento

### 1. Columna tenantId (recomendado para empezar)

Todos los datos en las mismas tablas, filtrados por `tenantId`.

```
✅ Ventajas:
- Simple de implementar
- Un solo schema de DB
- Fácil de escalar horizontalmente
- Costo bajo (una sola DB)

❌ Desventajas:
- Riesgo de data leak si olvidas filtrar
- Queries más complejas
- Un tenant grande puede afectar a otros
```

### 2. Schema por tenant (PostgreSQL)

Cada tenant tiene su propio schema en la misma DB.

```
✅ Ventajas:
- Aislamiento más fuerte
- Fácil de hacer backup por tenant
- Mejor para compliance estricto

❌ Desventajas:
- Migrations más complejas (aplicar a N schemas)
- Conexiones separadas por schema
- Más costoso de operar
```

### 3. Base de datos por tenant

Cada tenant tiene su propia base de datos.

```
✅ Ventajas:
- Aislamiento total
- Fácil de migrar tenants a otros servidores
- Ideal para enterprise con requisitos de compliance

❌ Desventajas:
- Muy costoso
- Operacionalmente complejo
- Overkill para la mayoría de casos
```

**Recomendación:** Empezar con **columna tenantId** + middleware. Migrar a schema por tenant solo si un cliente enterprise lo requiere.

---

## Implementación: Columna tenantId

### 1. Schema Prisma

```prisma
// prisma/schema.prisma

model Tenant {
  id        String   @id @default(uuid())
  name      String
  slug      String   @unique  // Para subdominio: acme.tuapp.com
  plan      Plan     @default(FREE)
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  // Relaciones
  users     User[]
  // ... todas las entidades del tenant
}

model User {
  id        String   @id @default(uuid())
  email     String
  tenantId  String
  tenant    Tenant   @relation(fields: [tenantId], references: [id])
  // ...

  @@unique([email, tenantId])  // Email único por tenant
  @@index([tenantId])
}

model Ticket {
  id          String   @id @default(uuid())
  title       String
  description String?
  status      TicketStatus @default(OPEN)
  tenantId    String
  tenant      Tenant   @relation(fields: [tenantId], references: [id])
  createdById String
  createdBy   User     @relation(fields: [createdById], references: [id])
  // ...

  @@index([tenantId])
  @@index([tenantId, status])
  @@index([tenantId, createdById])
}

// REGLA: Toda tabla que contenga datos de negocio DEBE tener tenantId
// Excepciones: tablas de sistema (audit_log, migrations, etc.)
```

### 2. Extraer tenantId del request

```typescript
// common/middleware/tenant.middleware.ts
import {
  Injectable,
  NestMiddleware,
  UnauthorizedException,
} from "@nestjs/common";
import { Request, Response, NextFunction } from "express";
import { PrismaService } from "../../prisma/prisma.service";

// Extender el tipo Request para incluir tenant
declare global {
  namespace Express {
    interface Request {
      tenantId?: string;
      tenant?: { id: string; slug: string; plan: string };
    }
  }
}

@Injectable()
export class TenantMiddleware implements NestMiddleware {
  constructor(private readonly prisma: PrismaService) {}

  async use(req: Request, res: Response, next: NextFunction) {
    // Estrategia 1: Extraer del JWT (recomendado)
    const tenantId = req.user?.tenantId;

    // Estrategia 2: Extraer del header (para APIs públicas)
    // const tenantId = req.headers['x-tenant-id'] as string;

    // Estrategia 3: Extraer del subdominio
    // const host = req.headers.host ?? '';
    // const subdomain = host.split('.')[0];
    // const tenant = await this.prisma.tenant.findUnique({ where: { slug: subdomain } });
    // const tenantId = tenant?.id;

    if (!tenantId) {
      throw new UnauthorizedException("Tenant no identificado");
    }

    // Cargar datos del tenant si se necesitan en la request
    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, slug: true, plan: true },
    });

    if (!tenant) {
      throw new UnauthorizedException("Tenant no encontrado");
    }

    req.tenantId = tenantId;
    req.tenant = tenant;

    next();
  }
}
```

### 3. Registrar middleware

```typescript
// app.module.ts
import { Module, NestModule, MiddlewareConsumer } from "@nestjs/common";
import { TenantMiddleware } from "./common/middleware/tenant.middleware";

@Module({
  // ...
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer
      .apply(TenantMiddleware)
      .exclude(
        "auth/login", // Login no tiene tenant aún
        "auth/register", // Registro puede crear tenant
        "health", // Health check público
      )
      .forRoutes("*");
  }
}
```

### 4. Decorator @CurrentTenant

```typescript
// common/decorators/current-tenant.decorator.ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';

export const CurrentTenant = createParamDecorator(
  (data: unknown, ctx: ExecutionContext): string => {
    const request = ctx.switchToHttp().getRequest();
    return request.tenantId;
  },
);

// Uso en controller:
@Get()
findAll(@CurrentTenant() tenantId: string) {
  return this.ticketsService.findAll(tenantId);
}
```

### 5. Repository con tenantId obligatorio

```typescript
// modules/tickets/repositories/ticket.repository.ts
import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../../prisma/prisma.service";

@Injectable()
export class TicketRepository {
  constructor(private readonly prisma: PrismaService) {}

  // TODAS las queries filtran por tenantId
  async findAll(tenantId: string, filters: FindTicketsDto) {
    return this.prisma.ticket.findMany({
      where: {
        tenantId, // ← SIEMPRE presente
        status: filters.status,
      },
      orderBy: { createdAt: "desc" },
    });
  }

  async findById(tenantId: string, id: string) {
    return this.prisma.ticket.findFirst({
      where: {
        id,
        tenantId, // ← Evita acceso cross-tenant
      },
    });
  }

  async create(tenantId: string, data: CreateTicketDto, userId: string) {
    return this.prisma.ticket.create({
      data: {
        ...data,
        tenantId, // ← SIEMPRE se inyecta
        createdById: userId,
      },
    });
  }

  async update(tenantId: string, id: string, data: UpdateTicketDto) {
    // Primero verificar que pertenece al tenant
    const ticket = await this.findById(tenantId, id);
    if (!ticket) {
      throw new NotFoundException("Ticket no encontrado");
    }

    return this.prisma.ticket.update({
      where: { id },
      data,
    });
  }

  async delete(tenantId: string, id: string) {
    const ticket = await this.findById(tenantId, id);
    if (!ticket) {
      throw new NotFoundException("Ticket no encontrado");
    }

    return this.prisma.ticket.delete({ where: { id } });
  }
}
```

---

## Row-Level Security (RLS) en PostgreSQL

RLS es una capa adicional de seguridad a nivel de base de datos. Incluso si olvidas filtrar en el código, PostgreSQL bloquea el acceso.

### Habilitar RLS

```sql
-- Habilitar RLS en tablas con datos de tenant
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets ENABLE ROW LEVEL SECURITY;
-- ... todas las tablas multi-tenant

-- Forzar RLS incluso para el owner de la tabla
ALTER TABLE tickets FORCE ROW LEVEL SECURITY;
```

### Crear políticas

```sql
-- Política de lectura: solo ver datos del propio tenant
CREATE POLICY tenant_isolation_select ON tickets
  FOR SELECT
  USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- Política de inserción: solo crear en el propio tenant
CREATE POLICY tenant_isolation_insert ON tickets
  FOR INSERT
  WITH CHECK (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- Política de actualización
CREATE POLICY tenant_isolation_update ON tickets
  FOR UPDATE
  USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- Política de eliminación
CREATE POLICY tenant_isolation_delete ON tickets
  FOR DELETE
  USING (tenant_id = current_setting('app.current_tenant_id')::uuid);

-- Política combinada (alternativa más simple)
CREATE POLICY tenant_isolation ON tickets
  FOR ALL
  USING (tenant_id = current_setting('app.current_tenant_id')::uuid)
  WITH CHECK (tenant_id = current_setting('app.current_tenant_id')::uuid);
```

### Setear el tenant en cada request

```typescript
// prisma/prisma.service.ts con RLS
import {
  Injectable,
  OnModuleInit,
  OnModuleDestroy,
  Scope,
} from "@nestjs/common";
import { PrismaClient } from "@prisma/client";
import { REQUEST } from "@nestjs/core";
import { Inject } from "@nestjs/common";
import { Request } from "express";

@Injectable({ scope: Scope.REQUEST }) // ← Instancia por request
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor(@Inject(REQUEST) private readonly request: Request) {
    super();
  }

  async onModuleInit() {
    await this.$connect();

    // Setear el tenant para RLS en cada query
    const tenantId = this.request.tenantId;
    if (tenantId) {
      await this
        .$executeRaw`SELECT set_config('app.current_tenant_id', ${tenantId}, true)`;
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
```

⚠️ **Nota:** Usar `Scope.REQUEST` tiene implicaciones de performance. Evaluar si RLS es necesario para tu caso de uso.

### Alternativa: Client Extension `$extends` (Prisma 7, sin scope request)

> ⚠️ El middleware `$use()` fue **eliminado en Prisma 7**. El mecanismo vigente es una query extension con `$extends`. Ver `prisma7-docs` para el setup completo con driver adapters.

```typescript
// prisma/tenant.extension.ts
import { Prisma } from "@prisma/client";
import { ClsService } from "nestjs-cls"; // Context Local Storage

// Modelos SIN tenantId (catálogos globales) — lista explícita
const GLOBAL_MODELS = new Set(["Tenant"]);

export const tenantExtension = (cls: ClsService) =>
  Prisma.defineExtension({
    name: "tenant-isolation",
    query: {
      $allModels: {
        async $allOperations({ model, operation, args, query }) {
          const tenantId = cls.get("tenantId");
          if (!tenantId || GLOBAL_MODELS.has(model)) return query(args);

          // Inyectar en WHERE para lecturas/updates/deletes
          if (
            [
              "findMany",
              "findFirst",
              "findUnique",
              "count",
              "aggregate",
              "updateMany",
              "deleteMany",
            ].includes(operation)
          ) {
            (args as any).where = { ...(args as any).where, tenantId };
          }

          // Inyectar en data para creates
          if (operation === "create") {
            (args as any).data = { ...(args as any).data, tenantId };
          }
          if (operation === "createMany") {
            const data = (args as any).data;
            (args as any).data = Array.isArray(data)
              ? data.map((d: object) => ({ ...d, tenantId }))
              : { ...data, tenantId };
          }

          return query(args);
        },
      },
    },
  });
```

```typescript
// prisma/prisma.service.ts — aplicar la extensión al cliente base (Prisma 7 + driver adapter)
// El cliente extendido es un TIPO NUEVO: exponerlo desde el service y usarlo en repositories.
const extendedClient = basePrismaClient.$extends(tenantExtension(cls));
```

---

## Testing de aislamiento

```typescript
// test/tenant-isolation.integration.spec.ts
import { Test } from "@nestjs/testing";
import { PrismaService } from "../prisma/prisma.service";
import { TicketRepository } from "../modules/tickets/repositories/ticket.repository";

describe("Tenant Isolation", () => {
  let prisma: PrismaService;
  let ticketRepo: TicketRepository;
  let tenantA: string;
  let tenantB: string;

  beforeAll(async () => {
    // Crear dos tenants de prueba
    const tA = await prisma.tenant.create({
      data: { name: "Tenant A", slug: "tenant-a" },
    });
    const tB = await prisma.tenant.create({
      data: { name: "Tenant B", slug: "tenant-b" },
    });
    tenantA = tA.id;
    tenantB = tB.id;

    // Crear datos en cada tenant
    await prisma.ticket.create({
      data: { title: "Ticket de A", tenantId: tenantA, createdById: "user-a" },
    });
    await prisma.ticket.create({
      data: { title: "Ticket de B", tenantId: tenantB, createdById: "user-b" },
    });
  });

  it("tenant A no puede ver tickets de tenant B", async () => {
    const tickets = await ticketRepo.findAll(tenantA, {});

    expect(tickets).toHaveLength(1);
    expect(tickets[0].title).toBe("Ticket de A");
    expect(tickets.some((t) => t.tenantId === tenantB)).toBe(false);
  });

  it("tenant A no puede acceder a ticket de tenant B por ID", async () => {
    const ticketB = await prisma.ticket.findFirst({
      where: { tenantId: tenantB },
    });

    // Intentar acceder desde tenant A
    const result = await ticketRepo.findById(tenantA, ticketB!.id);

    expect(result).toBeNull();
  });

  it("crear ticket siempre usa el tenantId del request", async () => {
    const ticket = await ticketRepo.create(
      tenantA,
      { title: "Nuevo" },
      "user-a",
    );

    expect(ticket.tenantId).toBe(tenantA);
  });
});
```

---

## Subdominios por tenant (opcional)

Para apps donde cada tenant accede por su propio subdominio: `acme.tuapp.com`

### Next.js middleware para subdominio

> Next 16.2+: el archivo se llama `proxy.ts` (mismo código, `middleware.ts` quedó renombrado). En Next 15/16.0-16.1 sigue siendo `middleware.ts`.

```typescript
// apps/web/middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const host = request.headers.get("host") ?? "";
  const subdomain = host.split(".")[0];

  // Ignorar www y el dominio principal
  if (subdomain === "www" || subdomain === "tuapp") {
    return NextResponse.next();
  }

  // Pasar el subdomain al API
  const response = NextResponse.next();
  response.headers.set("x-tenant-slug", subdomain);

  return response;
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
```

### Configuración de DNS

```
# Wildcard DNS para subdominios
*.tuapp.com  →  A  →  IP_DEL_SERVIDOR

# O con Cloudflare/Vercel, el wildcard es automático
```

---

## Checklist de implementación

### Fase 1: Básico

- [ ] Agregar `tenantId` a todas las tablas de negocio
- [ ] Crear `TenantMiddleware` para extraer tenant del JWT
- [ ] Crear decorator `@CurrentTenant()`
- [ ] Actualizar todos los repositories para filtrar por `tenantId`
- [ ] Agregar índices `@@index([tenantId])` en schema Prisma

### Fase 2: Seguridad

- [ ] Tests de aislamiento entre tenants
- [ ] Habilitar RLS en PostgreSQL (opcional pero recomendado)
- [ ] Auditar todas las queries para verificar filtro de tenant

### Fase 3: Features avanzados

- [ ] Subdominios por tenant (si aplica)
- [ ] Planes y límites por tenant
- [ ] Admin de tenants (crear, suspender, migrar)
- [ ] Métricas por tenant
