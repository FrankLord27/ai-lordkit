# Redis — Patrones de Cache

Estrategias de caching para alto rendimiento.

## Patrones Principales

### Cache-Aside (Lazy Loading) — El más común

```typescript
async function getUser(id: string): Promise<User> {
  // 1. Buscar en cache
  const cached = await redis.get(`user:${id}`);
  if (cached) return JSON.parse(cached);

  // 2. Cache miss → DB
  const user = await prisma.user.findUnique({ where: { id } });

  // 3. Guardar en cache
  if (user) await redis.setex(`user:${id}`, 300, JSON.stringify(user));
  return user;
}
```

### Write-Through

```typescript
async function updateUser(id: string, data: UpdateDto): Promise<User> {
  const user = await prisma.user.update({ where: { id }, data });
  await redis.setex(`user:${id}`, 300, JSON.stringify(user)); // Actualizar cache
  return user;
}
```

### Write-Behind (async)

```typescript
async function updateUserAsync(id: string, data: UpdateDto): Promise<void> {
  // 1. Actualizar cache
  const current = JSON.parse((await redis.get(`user:${id}`)) ?? "{}");
  await redis.setex(`user:${id}`, 300, JSON.stringify({ ...current, ...data }));

  // 2. Encolar escritura a DB
  await redis.rpush(
    "queue:db-writes",
    JSON.stringify({ entity: "user", id, data }),
  );
}
```

---

## Invalidación de Cache

### TTL (automático)

```typescript
await redis.setex("cache:data", 300, value); // Expira en 5 min
```

### Event-based

```typescript
async function updateUser(id: string, data: UpdateDto) {
  await prisma.user.update({ where: { id }, data });
  await redis.del(`user:${id}`, `user:${id}:profile`, `user:${id}:settings`);
}
```

### Tag-based

```typescript
class TaggedCache {
  async set(
    key: string,
    value: any,
    ttl: number,
    tags: string[],
  ): Promise<void> {
    await this.redis.setex(key, ttl, JSON.stringify(value));
    for (const tag of tags) await this.redis.sadd(`tag:${tag}`, key);
  }

  async invalidateTag(tag: string): Promise<number> {
    const keys = await this.redis.smembers(`tag:${tag}`);
    if (keys.length) await this.redis.del(...keys, `tag:${tag}`);
    return keys.length;
  }
}

// Uso
await cache.set("product:123", product, 3600, [
  "products",
  "category:electronics",
]);
await cache.invalidateTag("category:electronics"); // Invalida todos
```

---

## Problemas y Soluciones

### Cache Stampede (Thundering Herd)

Múltiples requests regeneran el cache simultáneamente.

```typescript
async function getOrSetWithLock<T>(
  key: string,
  loader: () => Promise<T>,
  ttl: number,
): Promise<T> {
  const cached = await redis.get(key);
  if (cached) return JSON.parse(cached);

  const lockKey = `lock:${key}`;
  const token = crypto.randomUUID();
  const acquired = await redis.set(lockKey, token, "EX", 10, "NX");

  if (acquired) {
    try {
      const data = await loader();
      await redis.setex(key, ttl, JSON.stringify(data));
      return data;
    } finally {
      await redis.eval(
        `if redis.call('GET',KEYS[1])==ARGV[1] then redis.call('DEL',KEYS[1]) end`,
        1,
        lockKey,
        token,
      );
    }
  } else {
    await new Promise((r) => setTimeout(r, 100));
    return getOrSetWithLock(key, loader, ttl); // Retry
  }
}
```

### TTL Jitter (evitar expiraciones masivas)

```typescript
function getTTLWithJitter(baseTTL: number): number {
  return baseTTL + Math.floor(Math.random() * baseTTL * 0.1); // ±10%
}

await redis.setex(key, getTTLWithJitter(300), value);
```

### Stale-While-Revalidate

```typescript
async function getWithSWR<T>(
  key: string,
  loader: () => Promise<T>,
  ttl: number,
  stale = 60,
): Promise<T> {
  const data = await redis.hgetall(key);

  if (data.value) {
    const age = Date.now() - parseInt(data.ts);
    const value = JSON.parse(data.value);

    if (age < ttl * 1000) return value; // Fresh
    if (age < (ttl + stale) * 1000) {
      // Stale pero usable - refrescar en background
      loader()
        .then((fresh) => {
          redis.hset(key, { value: JSON.stringify(fresh), ts: Date.now() });
        })
        .catch(console.error);
      return value;
    }
  }

  // Cargar síncronamente
  const fresh = await loader();
  await redis.hset(key, {
    value: JSON.stringify(fresh),
    ts: Date.now().toString(),
  });
  await redis.expire(key, ttl + stale);
  return fresh;
}
```

---

## Cache de Producción

```typescript
class ProductionCache {
  constructor(private redis: Redis) {}

  async get<T>(
    key: string,
    loader: () => Promise<T>,
    opts: { ttl: number; tags?: string[] },
  ): Promise<T> {
    const cached = await this.redis.get(`cache:${key}`);
    if (cached) return JSON.parse(cached);

    return this.loadWithLock(key, loader, opts);
  }

  private async loadWithLock<T>(
    key: string,
    loader: () => Promise<T>,
    opts: { ttl: number; tags?: string[] },
  ): Promise<T> {
    const lockKey = `lock:cache:${key}`;
    const token = crypto.randomUUID();
    const acquired = await this.redis.set(lockKey, token, "EX", 30, "NX");

    if (!acquired) {
      await new Promise((r) => setTimeout(r, 50 + Math.random() * 100));
      return this.get(key, loader, opts);
    }

    try {
      const data = await loader();
      const ttl = opts.ttl + Math.floor(Math.random() * opts.ttl * 0.1); // Jitter
      await this.redis.setex(`cache:${key}`, ttl, JSON.stringify(data));

      if (opts.tags) {
        for (const tag of opts.tags)
          await this.redis.sadd(`tag:${tag}`, `cache:${key}`);
      }
      return data;
    } finally {
      await this.redis.eval(
        `if redis.call('GET',KEYS[1])==ARGV[1] then redis.call('DEL',KEYS[1]) end`,
        1,
        lockKey,
        token,
      );
    }
  }

  async invalidate(key: string): Promise<void> {
    await this.redis.del(`cache:${key}`);
  }

  async invalidateTag(tag: string): Promise<void> {
    const keys = await this.redis.smembers(`tag:${tag}`);
    if (keys.length) await this.redis.del(...keys, `tag:${tag}`);
  }
}
```
