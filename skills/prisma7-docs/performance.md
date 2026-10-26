# Prisma 7 — Performance

Optimización de queries, índices, connection pooling, y debugging.

---

## 1. Logging de queries

```typescript
// prisma.service.ts — ver queries generadas
const prisma = new PrismaClient({
  adapter: new PrismaPg(pool),
  log: [
    { emit: "event", level: "query" },
    { emit: "stdout", level: "error" },
    { emit: "stdout", level: "warn" },
  ],
});

// Loguear queries con tiempo de ejecución
prisma.$on("query", (e) => {
  console.log(`Query: ${e.query}`);
  console.log(`Params: ${e.params}`);
  console.log(`Duration: ${e.duration}ms`);
});

// Solo queries lentas (> 100ms)
prisma.$on("query", (e) => {
  if (e.duration > 100) {
    console.warn(`⚠️ Slow query (${e.duration}ms): ${e.query}`);
  }
});
```

---

## 2. EXPLAIN ANALYZE

Ver el plan de ejecución de PostgreSQL:

```typescript
// Analizar query directamente
const plan = await prisma.$queryRaw`
  EXPLAIN ANALYZE
  SELECT * FROM users 
  WHERE email LIKE '%@gmail.com'
  AND deleted_at IS NULL
`;
console.log(plan);
```

### Qué buscar en el plan:

```
Seq Scan on users     ← ⚠️ Full table scan (malo para tablas grandes)
Index Scan on users   ← ✅ Usa índice
Bitmap Index Scan     ← ✅ Usa índice para múltiples condiciones
Sort                  ← ⚠️ Ordenamiento en memoria (puede ser lento)
Hash Join             ← ✅ Join eficiente
Nested Loop           ← ⚠️ Puede ser lento con muchos registros
```

---

## 3. Índices

### Agregar índices en schema.prisma

```prisma
model User {
  id        String    @id @default(uuid())
  email     String    @unique
  tenantId  String
  role      Role
  deletedAt DateTime?
  createdAt DateTime  @default(now())

  // Índice simple
  @@index([email])

  // Índice compuesto (orden importa)
  @@index([tenantId, deletedAt])
  @@index([tenantId, role, deletedAt])

  // Índice para ordenamiento
  @@index([createdAt(sort: Desc)])
}

model Ticket {
  id        String   @id @default(uuid())
  status    Status
  priority  Int
  tenantId  String
  assigneeId String?
  createdAt DateTime @default(now())

  // Índices para queries comunes
  @@index([tenantId, status])
  @@index([tenantId, assigneeId, status])
  @@index([tenantId, createdAt(sort: Desc)])
}
```

### Reglas para índices:

1. **Columnas en WHERE** → índice
2. **Columnas en ORDER BY** → índice con sort direction
3. **Columnas en JOINs** → índice en foreign key
4. **Filtros frecuentes** → índice compuesto con columnas más selectivas primero
5. **Soft delete** → siempre incluir `deletedAt` en índices compuestos

### Ver índices existentes:

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'users';
```

### Ver índices no utilizados:

```sql
SELECT
  schemaname || '.' || relname AS table,
  indexrelname AS index,
  pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
  idx_scan AS scans
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE idx_scan < 50
ORDER BY pg_relation_size(i.indexrelid) DESC;
```

---

## 4. Evitar N+1

### Problema N+1:

```typescript
// ❌ N+1: 1 query para posts + N queries para autores
const posts = await prisma.post.findMany();
for (const post of posts) {
  const author = await prisma.user.findUnique({
    where: { id: post.authorId },
  });
}
```

### Solución con include:

```typescript
// ✅ 1 query con JOIN
const posts = await prisma.post.findMany({
  include: { author: true },
});
```

### Solución con select (más eficiente):

```typescript
// ✅ Solo campos necesarios
const posts = await prisma.post.findMany({
  select: {
    id: true,
    title: true,
    author: {
      select: { id: true, name: true },
    },
  },
});
```

### Cargar relaciones en batch:

```typescript
// Cuando no puedes usar include (ej: procesamiento en lotes)
const posts = await prisma.post.findMany({ take: 100 });
const authorIds = [...new Set(posts.map((p) => p.authorId))];

const authors = await prisma.user.findMany({
  where: { id: { in: authorIds } },
});

const authorsMap = new Map(authors.map((a) => [a.id, a]));
const postsWithAuthors = posts.map((p) => ({
  ...p,
  author: authorsMap.get(p.authorId),
}));
```

---

## 5. Connection Pooling

### Configurar pool en driver adapter:

```typescript
import pg from "pg";

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,

  // Tamaño del pool
  max: 20, // Máximo de conexiones
  min: 5, // Mínimo de conexiones idle

  // Timeouts
  idleTimeoutMillis: 30000, // Cerrar conexión idle después de 30s
  connectionTimeoutMillis: 5000, // Timeout para obtener conexión

  // Validación
  allowExitOnIdle: false, // No cerrar pool si no hay queries
});

// Monitorear el pool
pool.on("connect", () => console.log("Pool: new connection"));
pool.on("remove", () => console.log("Pool: connection removed"));
pool.on("error", (err) => console.error("Pool error:", err));

// Métricas
setInterval(() => {
  console.log({
    total: pool.totalCount,
    idle: pool.idleCount,
    waiting: pool.waitingCount,
  });
}, 60000);
```

### Pool sizing:

```
Regla: pool_size = (core_count * 2) + effective_spindle_count

Para SSD: ~10-20 conexiones por proceso
Para HDD: ~5-10 conexiones
```

---

## 6. Paginación eficiente

### Offset pagination (simple pero lenta para páginas altas):

```typescript
// ⚠️ Lenta para offset grandes
const page2 = await prisma.post.findMany({
  skip: 1000, // PostgreSQL aún debe escanear 1000 filas
  take: 10,
});
```

### Cursor pagination (recomendada):

```typescript
// ✅ Siempre rápida, independiente de la posición
const posts = await prisma.post.findMany({
  take: 10,
  skip: cursor ? 1 : 0,
  cursor: cursor ? { id: cursor } : undefined,
  orderBy: { createdAt: "desc" },
});

// El cursor para la siguiente página
const nextCursor = posts.length === 10 ? posts[posts.length - 1].id : null;
```

### Seek pagination (más control):

```typescript
// Para ordenamiento compuesto
const posts = await prisma.post.findMany({
  where: {
    OR: [
      { createdAt: { lt: lastCreatedAt } },
      {
        createdAt: lastCreatedAt,
        id: { lt: lastId },
      },
    ],
  },
  take: 10,
  orderBy: [{ createdAt: "desc" }, { id: "desc" }],
});
```

---

## 7. Batch operations

### createMany es más rápido que múltiples create:

```typescript
// ❌ Lento: N queries
for (const item of items) {
  await prisma.item.create({ data: item });
}

// ✅ Rápido: 1 query
await prisma.item.createMany({
  data: items,
  skipDuplicates: true,
});
```

### Batch updates:

```typescript
// Actualizar muchos registros
await prisma.user.updateMany({
  where: { role: "GUEST", createdAt: { lt: cutoff } },
  data: { isActive: false },
});
```

### Batch con transacción:

```typescript
// Operaciones relacionadas en una transacción
await prisma.$transaction([
  prisma.orderItem.createMany({ data: items }),
  prisma.product.updateMany({
    where: { id: { in: productIds } },
    data: { stock: { decrement: 1 } },
  }),
  prisma.order.update({
    where: { id: orderId },
    data: { status: "CONFIRMED" },
  }),
]);
```

---

## 8. Raw queries para operaciones complejas

```typescript
// Agregaciones complejas
const stats = await prisma.$queryRaw`
  SELECT 
    DATE_TRUNC('month', created_at) as month,
    COUNT(*) as total,
    SUM(amount) as revenue
  FROM orders
  WHERE tenant_id = ${tenantId}
    AND created_at >= ${startDate}
  GROUP BY DATE_TRUNC('month', created_at)
  ORDER BY month DESC
`;

// Upsert masivo con ON CONFLICT
await prisma.$executeRaw`
  INSERT INTO products (id, name, price, updated_at)
  SELECT * FROM UNNEST(
    ${ids}::uuid[],
    ${names}::text[],
    ${prices}::decimal[],
    ${Array(ids.length).fill(new Date())}::timestamp[]
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    price = EXCLUDED.price,
    updated_at = EXCLUDED.updated_at
`;
```

---

## 9. Caché de queries

```typescript
// Cachear resultados frecuentes
async function getCategories(tenantId: string) {
  const cacheKey = `categories:${tenantId}`;

  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached);

  const categories = await prisma.category.findMany({
    where: { tenantId, deletedAt: null },
    orderBy: { name: "asc" },
  });

  await redis.setex(cacheKey, 300, JSON.stringify(categories)); // 5 min

  return categories;
}
```

---

## 10. Checklist de performance

### Antes de ir a producción:

- [ ] Logging de queries lentas habilitado
- [ ] Índices para todas las columnas en WHERE frecuentes
- [ ] Índices compuestos con `tenantId` primero
- [ ] Connection pool configurado correctamente
- [ ] N+1 queries eliminadas (usar include/select)
- [ ] Paginación cursor-based para listas largas
- [ ] Batch operations para inserts/updates masivos
- [ ] EXPLAIN ANALYZE en queries críticas
- [ ] Monitoreo de queries lentas en producción
