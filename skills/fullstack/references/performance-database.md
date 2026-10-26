# Performance en Base de Datos — PostgreSQL + Prisma

> ⚠️ **Prisma 7:** los ejemplos con `new PrismaClient()` / `extends PrismaClient` asumen el setup v7 con **driver adapter** (`@prisma/adapter-pg`) y `prisma.config.ts` — sin adapter NO compilan. Setup completo en `prisma7-docs`.

---

## El problema más común: queries sin índice

Una query sin índice hace un Sequential Scan — lee toda la tabla fila por fila.
Con 100 registros no se nota. Con 100.000 registros tumba el servidor.

### Cómo detectarlo con EXPLAIN ANALYZE

```sql
-- Ejecutar directamente en PostgreSQL para ver el plan de ejecución
EXPLAIN ANALYZE
SELECT * FROM bookings WHERE user_id = 'uuid-123' AND status = 'CONFIRMED';

-- Output sin índice (malo):
-- Seq Scan on bookings (cost=0.00..2847.00 rows=1 width=156)
--                       ^^^^^^^^^^^^^ Lee toda la tabla

-- Output con índice (bueno):
-- Index Scan using idx_bookings_user_status on bookings (cost=0.43..8.45 rows=1)
--                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Usa el índice
```

```typescript
// Desde Prisma: loguear todas las queries en desarrollo
// apps/api/src/prisma/prisma.service.ts
export class PrismaService extends PrismaClient implements OnModuleInit {
  constructor() {
    super({
      log:
        process.env.NODE_ENV === "development"
          ? ["query", "warn", "error"] // Loguea cada query con su duración
          : ["warn", "error"],
    });
  }
}
// Busca en los logs queries que tarden > 100ms
```

### Índices en Prisma — reglas de cuándo crear uno

```prisma
model Booking {
  id         String        @id @default(uuid())
  userId     String
  carId      String
  status     BookingStatus
  pickupDate DateTime
  returnDate DateTime
  createdAt  DateTime      @default(now())

  // ✅ Índice simple — columna que aparece sola en WHERE frecuente
  @@index([userId])
  @@index([status])

  // ✅ Índice compuesto — cuando filtras por dos columnas JUNTAS
  // El orden importa: poner primero la columna de mayor selectividad
  @@index([userId, status])        // Para: WHERE userId = X AND status = Y
  @@index([pickupDate, returnDate]) // Para: búsquedas por rango de fechas

  // ✅ Índice único — cuando la combinación debe ser única
  @@unique([userId, carId, pickupDate])
}

// Regla: crear índice en columnas que van en:
// - WHERE ... = valor
// - ORDER BY columna
// - JOIN ... ON tabla.columna = ...
// - GROUP BY columna

// NO crear índice en:
// - Columnas con muy poca variedad de valores (status con 3 valores)
//   → A veces sí vale si filtra mucho volumen
// - Tablas pequeñas (< 1000 registros) → el seq scan es igual de rápido
// - Columnas que se actualizan muy frecuentemente → el índice se reconstruye
```

---

## El problema N+1 — el más destructivo

N+1 ocurre cuando haces 1 query para obtener una lista y luego N queries
más para obtener datos relacionados de cada elemento.

```typescript
// ❌ N+1 — Problema clásico
// 1 query para obtener bookings:
const bookings = await prisma.booking.findMany({ where: { userId } });

// N queries adicionales — una por cada booking:
for (const booking of bookings) {
  const car = await prisma.car.findUnique({ where: { id: booking.carId } });
  // Si hay 50 bookings → 51 queries en total
}
```

```typescript
// ✅ Solución con include de Prisma — 1 sola query con JOIN
const bookings = await prisma.booking.findMany({
  where: { userId },
  include: {
    car: {
      include: {
        images: { orderBy: { order: "asc" }, take: 1 }, // Solo la primera imagen
        location: true,
      },
    },
    user: {
      select: { id: true, name: true, email: true }, // Solo campos necesarios
    },
  },
});
// Resultado: 1 query con todos los datos. No importa cuántos bookings haya.
```

### Cómo detectar N+1 en desarrollo

```typescript
// Contar queries por request — si una request hace más de 5-10 queries, hay N+1
// En el log de Prisma verás algo así:
// prisma:query SELECT ... FROM "Car" WHERE "id" = $1  ← se repite N veces
// prisma:query SELECT ... FROM "Car" WHERE "id" = $2
// prisma:query SELECT ... FROM "Car" WHERE "id" = $3

// Herramienta: prisma-query-inspector
// O simplemente: grep en los logs por "prisma:query" y contar repeticiones del mismo patrón
```

### DataLoader — para N+1 en resolvers GraphQL o lógica compleja

```typescript
// pnpm add dataloader
import DataLoader from "dataloader";

// El DataLoader agrupa todas las llamadas que ocurren en el mismo tick
// en una sola query batch
@Injectable()
export class CarLoader {
  private loader = new DataLoader<string, Car>(async (ids) => {
    // Recibe todos los IDs juntos → una sola query
    const cars = await this.prisma.car.findMany({
      where: { id: { in: ids as string[] } },
    });

    // Devolver en el mismo orden que los IDs recibidos
    return ids.map((id) => cars.find((car) => car.id === id) ?? null);
  });

  async load(id: string): Promise<Car> {
    return this.loader.load(id);
  }
}

// Uso — aunque se llame 50 veces, hace 1 sola query
const car = await this.carLoader.load(booking.carId);
```

---

## Select solo los campos necesarios

```typescript
// ❌ Trae todos los campos — incluye datos pesados o innecesarios
const users = await prisma.user.findMany();

// ✅ Solo los campos que necesitas
const users = await prisma.user.findMany({
  select: {
    id: true,
    name: true,
    email: true,
    // ❌ No incluir: password, createdAt, internalNotes, etc.
  },
});

// ✅ Excluir campos pesados — útil cuando hay campos TEXT o JSONB grandes
const cars = await prisma.car.findMany({
  select: {
    id: true,
    model: true,
    dailyRate: true,
    // Omitir: description (TEXT largo), technicalSpecs (JSONB)
    images: { select: { url: true }, take: 1 },
  },
});
```

---

## Paginación eficiente

### Offset pagination — simple pero lenta en tablas grandes

```typescript
// Funciona bien hasta ~50k registros
async findAll(page: number, limit: number) {
  const skip = (page - 1) * limit;

  const [data, total] = await Promise.all([
    this.prisma.item.findMany({
      skip,
      take: limit,
      orderBy: { createdAt: 'desc' },
    }),
    this.prisma.item.count(),
  ]);

  return {
    data,
    total,
    page,
    limit,
    hasNextPage: skip + limit < total,
    totalPages: Math.ceil(total / limit),
  };
}
```

### Cursor pagination — eficiente para tablas grandes

```typescript
// Más eficiente para tablas con > 100k registros
// No necesita COUNT(*) — más rápida
async findAllCursor(cursor?: string, limit = 20) {
  const items = await this.prisma.item.findMany({
    take: limit + 1,  // Tomar uno más para saber si hay siguiente página
    cursor: cursor ? { id: cursor } : undefined,
    orderBy: { createdAt: 'desc' },
    skip: cursor ? 1 : 0,  // Saltar el cursor actual
  });

  const hasNextPage = items.length > limit;
  const data = hasNextPage ? items.slice(0, -1) : items;
  const nextCursor = hasNextPage ? data[data.length - 1].id : null;

  return { data, nextCursor, hasNextPage };
}
```

---

## Connection pooling — nunca abrir demasiadas conexiones

```typescript
// PostgreSQL tiene un límite de conexiones (default: 100)
// Cada instancia de la app abre un pool de conexiones

// prisma.service.ts — configurar el pool
export class PrismaService extends PrismaClient {
  constructor() {
    super({
      datasources: {
        db: {
          url: process.env.DATABASE_URL,
          // ?connection_limit=10 — máximo 10 conexiones por instancia
          // Si tienes 3 instancias de la app → 30 conexiones usadas de 100
        },
      },
    });
  }
}
```

```env
# En la URL de conexión
DATABASE_URL=postgresql://user:pass@host:5432/db?connection_limit=10&pool_timeout=10
```

### PgBouncer — connection pooler externo (cuando escala)

```
Sin PgBouncer:   App (10 conex) → PostgreSQL (10 conex abiertas permanentemente)
Con PgBouncer:   App (100 conex) → PgBouncer → PostgreSQL (10 conex reales)
```

PgBouncer gestiona un pool pequeño de conexiones reales y reutiliza entre
las conexiones de la app. Necesario cuando hay múltiples instancias de la app.

---

## Queries frecuentes — patrones optimizados

```typescript
// ✅ Buscar por múltiples IDs — una sola query
const items = await prisma.item.findMany({
  where: { id: { in: ids } },
});

// ✅ Upsert — crear o actualizar en una sola operación atómica
await prisma.item.upsert({
  where: { slug: item.slug },
  create: { ...item },
  update: { price: item.price, updatedAt: new Date() },
});

// ✅ Agregar sin cargar todos los registros
const stats = await prisma.booking.aggregate({
  where: { userId, status: "COMPLETED" },
  _sum: { totalPrice: true },
  _count: { id: true },
  _avg: { totalPrice: true },
});

// ✅ Verificar existencia sin traer el registro completo
const exists = await prisma.item.findFirst({
  where: { slug },
  select: { id: true }, // Solo el ID — lo más ligero posible
});
```
