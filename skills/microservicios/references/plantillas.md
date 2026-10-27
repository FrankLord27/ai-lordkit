# Plantillas: microservicios con NestJS, Prisma y PostgreSQL

Ejemplos mínimos para el Bloque 0 y el Bloque 0.5. El scope `@mystack` y los nombres `svc-orders` o `svc-catalog` son de ejemplo. Antes de usar una API de librería que no domines, consulta Context7.

## 1. Configuración validada (`packages/service-kit/src/config.ts`)

Cada servicio declara sus variables con Zod. Si falta una, el servicio no arranca y dice cuál falta.

```ts
import { z } from "zod";

export function loadConfig<T extends z.ZodType>(schema: T): z.infer<T> {
  const result = schema.safeParse(process.env);
  if (!result.success) {
    const lines = result.error.issues.map((i) => `- ${i.path.join(".")}: ${i.message}`);
    console.error(`Configuración inválida:\n${lines.join("\n")}`);
    process.exit(1);
  }
  return result.data;
}
```

```ts
// apps/svc-orders/src/config.ts
import { z } from "zod";
import { loadConfig } from "@mystack/service-kit";

export const config = loadConfig(
  z.object({
    PORT: z.coerce.number().default(3000),
    DATABASE_URL: z.url(),
    BROKER_URL: z.url(),
    JWT_PUBLIC_KEY: z.string().min(1),
    SVC_CATALOG_URL: z.url(),
  }),
);
```

## 2. Gateway (`apps/gateway/src/main.ts`)

Rutea por prefijo sin reescribir la ruta, valida el JWT, agrega `x-request-id` y responde 503 si el servicio está caído. `bodyParser: false` hace que el cuerpo llegue intacto al servicio.

```ts
import { randomUUID } from "node:crypto";
import { NestFactory } from "@nestjs/core";
import type { NextFunction, Request, Response } from "express";
import { createProxyMiddleware } from "http-proxy-middleware";
import { importSPKI, jwtVerify } from "jose";
import { z } from "zod";
import { loadConfig } from "@mystack/service-kit";
import { AppModule } from "./app.module";

const env = loadConfig(
  z.object({
    PORT: z.coerce.number().default(3000),
    WEB_ORIGIN: z.url(),
    JWT_PUBLIC_KEY: z.string().min(1),
    SVC_IDENTITY_URL: z.url(),
    SVC_ORDERS_URL: z.url(),
  }),
);

// Cada servicio es dueño de sus prefijos.
const routes: ReadonlyArray<{ prefixes: string[]; target: string }> = [
  { prefixes: ["/auth"], target: env.SVC_IDENTITY_URL },
  { prefixes: ["/orders", "/returns"], target: env.SVC_ORDERS_URL },
];
const PUBLIC_PATHS = ["/auth/login", "/auth/refresh", "/health"];

async function bootstrap(): Promise<void> {
  const publicKey = await importSPKI(env.JWT_PUBLIC_KEY, "RS256");
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  app.enableCors({ origin: env.WEB_ORIGIN, credentials: true });

  app.use((req: Request, _res: Response, next: NextFunction) => {
    req.headers["x-request-id"] ??= randomUUID();
    next();
  });

  app.use(async (req: Request, res: Response, next: NextFunction) => {
    if (PUBLIC_PATHS.some((p) => req.path.startsWith(p))) return next();
    const token = req.headers.authorization?.replace(/^Bearer /, "");
    if (!token) return res.status(401).json({ message: "Falta el token" });
    try {
      await jwtVerify(token, publicKey, { issuer: "svc-identity" });
      return next();
    } catch {
      return res.status(401).json({ message: "Token inválido o vencido" });
    }
  });

  for (const { prefixes, target } of routes) {
    app.use(
      createProxyMiddleware({
        target,
        pathFilter: prefixes,
        changeOrigin: true,
        proxyTimeout: 10_000,
        on: {
          error: (_err, _req, res) => {
            if ("writeHead" in res && !res.headersSent) {
              res.writeHead(503, { "content-type": "application/json" });
            }
            res.end(JSON.stringify({ message: "Servicio no disponible, intenta en un momento" }));
          },
        },
      }),
    );
  }

  await app.listen(env.PORT);
}

void bootstrap();
```

Cada servicio vuelve a verificar el token con el mismo `JWT_PUBLIC_KEY` (guard en `service-kit`). Solo `svc-identity` tiene la llave privada.

## 3. Contratos (`packages/contracts`)

```ts
// packages/contracts/src/orders/events.ts
import { z } from "zod";

export const OrderCreatedV1 = z.object({
  orderId: z.uuid(),
  tenantId: z.uuid(),
  items: z
    .array(z.object({ productId: z.uuid(), quantity: z.number().int().positive() }))
    .min(1),
  occurredAt: z.iso.datetime(),
});
export type OrderCreatedV1 = z.infer<typeof OrderCreatedV1>;

// Un evento nunca cambia de forma: si cambia, se crea order.created.v2.
export const ORDER_EVENTS = {
  "order.created.v1": OrderCreatedV1,
} as const;
```

## 4. Outbox con Prisma (servicio que publica)

```prisma
model OutboxEvent {
  id          String    @id @default(uuid())
  type        String
  payload     Json
  createdAt   DateTime  @default(now())
  publishedAt DateTime?

  @@index([publishedAt, createdAt])
}
```

El cambio y el evento se guardan en la misma transacción. Si la transacción falla, no sale ningún evento; si sale bien, el evento sale aunque el broker esté caído en ese momento.

```ts
async createOrder(input: CreateOrderInput, tenantId: string) {
  return this.prisma.$transaction(async (tx) => {
    const order = await tx.order.create({ data: { tenantId, status: "PENDING_STOCK", items: { create: input.items } } });
    const payload = OrderCreatedV1.parse({
      orderId: order.id,
      tenantId,
      items: input.items,
      occurredAt: new Date().toISOString(),
    });
    await tx.outboxEvent.create({ data: { type: "order.created.v1", payload } });
    return order;
  });
}
```

El worker del outbox (cada 1 o 2 segundos) publica en lotes. `SKIP LOCKED` permite correr varias réplicas sin publicar dos veces el mismo lote. La entrega es "al menos una vez": por eso los consumidores son idempotentes.

```ts
async publishPending(): Promise<void> {
  await this.prisma.$transaction(async (tx) => {
    const batch = await tx.$queryRaw<Array<{ id: string; type: string; payload: unknown }>>`
      SELECT id, type, payload FROM "OutboxEvent"
      WHERE "publishedAt" IS NULL
      ORDER BY "createdAt"
      LIMIT 50
      FOR UPDATE SKIP LOCKED`;
    if (batch.length === 0) return;
    for (const event of batch) {
      await this.broker.publish(event.type, { id: event.id, data: event.payload });
    }
    await tx.outboxEvent.updateMany({
      where: { id: { in: batch.map((e) => e.id) } },
      data: { publishedAt: new Date() },
    });
  });
}
```

`this.broker` es un adaptador de `service-kit` sobre RabbitMQ o NATS. El servicio no conoce la librería del broker.

## 5. Consumidor idempotente (servicio que escucha)

```prisma
model ProcessedEvent {
  id          String   @id
  processedAt DateTime @default(now())
}
```

```ts
async onOrderCreated(event: { id: string; data: unknown }): Promise<void> {
  const data = OrderCreatedV1.parse(event.data);
  await this.prisma.$transaction(async (tx) => {
    const marked = await tx.processedEvent.createMany({ data: [{ id: event.id }], skipDuplicates: true });
    if (marked.count === 0) return; // ya se procesó
    await this.reserveStock(tx, data); // si no alcanza, publica stock.rejected.v1 por el outbox
  });
}
```

Saga del ejemplo: `order.created.v1` → el inventario reserva y publica `stock.reserved.v1` o `stock.rejected.v1` → pedidos pasa a `CONFIRMED` o `CANCELLED` y el WebSocket avisa al usuario. Ningún paso se traga un error.

## 6. Cliente síncrono tipado

Solo para consultas que se necesitan ya. Siempre con timeout, y la respuesta se valida con el contrato.

```ts
import { ProductDto } from "@mystack/contracts";

export class UpstreamError extends Error {
  constructor(readonly service: string, readonly status: number) {
    super(`${service} respondió ${status}`);
  }
}

export function createCatalogClient(baseUrl: string) {
  return {
    async getProduct(id: string, ctx: { requestId: string; authorization: string }) {
      const res = await fetch(`${baseUrl}/catalog/products/${id}`, {
        headers: { "x-request-id": ctx.requestId, authorization: ctx.authorization },
        signal: AbortSignal.timeout(3_000),
      });
      if (res.status === 404) return null;
      if (!res.ok) throw new UpstreamError("svc-catalog", res.status);
      return ProductDto.parse(await res.json());
    },
  };
}
```

## 7. Compose maestro (`infra/compose.yml`)

Solo `web` y `gateway` publican puertos. En desarrollo hay un solo PostgreSQL con **una base y un usuario por servicio** (script en `infra/postgres/init/`). En producción, bases separadas.

```yaml
x-service: &service
  restart: unless-stopped
  networks: [internal]
  healthcheck:
    test: ["CMD", "wget", "-qO-", "http://localhost:3000/ready"]
    interval: 10s
    timeout: 3s
    retries: 5

services:
  postgres:
    image: postgres:16-alpine
    env_file: ./postgres/.env
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./postgres/init:/docker-entrypoint-initdb.d:ro
    networks: [internal]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER}"]
      interval: 5s
      retries: 10

  broker:
    image: rabbitmq:4-alpine
    networks: [internal]
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      retries: 10

  svc-identity:
    <<: *service
    build: { context: .., dockerfile: apps/svc-identity/Dockerfile }
    env_file: ../apps/svc-identity/.env
    depends_on:
      postgres: { condition: service_healthy }

  svc-orders:
    <<: *service
    build: { context: .., dockerfile: apps/svc-orders/Dockerfile }
    env_file: ../apps/svc-orders/.env
    depends_on:
      postgres: { condition: service_healthy }
      broker: { condition: service_healthy }

  gateway:
    <<: *service
    build: { context: .., dockerfile: apps/gateway/Dockerfile }
    env_file: ../apps/gateway/.env
    ports: ["8080:3000"]
    networks: [internal, edge]
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 10s
      retries: 5
    depends_on:
      svc-identity: { condition: service_healthy }

  web:
    build: { context: .., dockerfile: apps/web/Dockerfile }
    env_file: ../apps/web/.env
    ports: ["3000:3000"]
    networks: [edge]
    depends_on: [gateway]

networks:
  internal:
  edge:

volumes:
  pg_data:
```

Las migraciones no corren al arrancar el servicio: van en un paso aparte (`prisma migrate deploy` por servicio en CI o en un job de una sola vez). El gateway depende solo de `svc-identity` a propósito: si `svc-orders` cae, el gateway sigue arriba y responde 503 en `/orders`.

## 8. Dockerfile por servicio (multi-stage con `turbo prune`)

```dockerfile
FROM node:24-alpine AS base
RUN corepack enable

FROM base AS prune
WORKDIR /repo
COPY . .
RUN pnpm dlx turbo@2.5.0 prune @mystack/svc-orders --docker

FROM base AS build
WORKDIR /repo
COPY --from=prune /repo/out/json/ .
RUN pnpm install --frozen-lockfile
COPY --from=prune /repo/out/full/ .
RUN pnpm turbo run build --filter=@mystack/svc-orders

FROM base AS run
WORKDIR /repo
ENV NODE_ENV=production
COPY --from=build --chown=node:node /repo .
USER node
EXPOSE 3000
CMD ["node", "apps/svc-orders/dist/main.js"]
```

El `build` del servicio incluye `prisma generate`. La imagen final lleva dependencias de desarrollo: cuando el tamaño importe, se optimiza con `pnpm deploy`.
