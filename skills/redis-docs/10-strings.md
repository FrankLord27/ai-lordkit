# Redis — Strings

La estructura más básica. Almacena texto, números, JSON, o datos binarios (hasta 512MB).

## Comandos Básicos

```bash
SET key "value"               # Guardar
GET key                       # Obtener
SET key "v" EX 60             # Con TTL 60s
SET key "v" NX                # Solo si NO existe
SET key "v" XX                # Solo si YA existe
MSET k1 v1 k2 v2              # Set múltiple
MGET k1 k2 k3                 # Get múltiple
APPEND key " more"            # Agregar al final
STRLEN key                    # Longitud
```

## Contadores (atómicos)

```bash
INCR counter                  # +1
DECR counter                  # -1
INCRBY counter 5              # +5
INCRBYFLOAT counter 0.5       # +0.5
```

```typescript
await redis.incr("visits:page:123");
const visits = await redis.get("visits:page:123");
```

## Cache Simple

```typescript
class Cache {
  constructor(private redis: Redis) {}

  async get<T>(key: string): Promise<T | null> {
    const data = await this.redis.get(key);
    return data ? JSON.parse(data) : null;
  }

  async set<T>(key: string, value: T, ttl?: number): Promise<void> {
    const json = JSON.stringify(value);
    ttl
      ? await this.redis.setex(key, ttl, json)
      : await this.redis.set(key, json);
  }

  async getOrSet<T>(
    key: string,
    fn: () => Promise<T>,
    ttl?: number,
  ): Promise<T> {
    const cached = await this.get<T>(key);
    if (cached !== null) return cached;
    const value = await fn();
    await this.set(key, value, ttl);
    return value;
  }
}

// Uso
const user = await cache.getOrSet("user:123", () => db.findUser("123"), 300);
```

## Feature Flags

```typescript
class FeatureFlags {
  constructor(private redis: Redis) {}
  async isEnabled(flag: string): Promise<boolean> {
    return (await this.redis.get(`feature:${flag}`)) === "1";
  }
  async enable(flag: string): Promise<void> {
    await this.redis.set(`feature:${flag}`, "1");
  }
}
```

## Distributed Lock Simple

```typescript
async function withLock<T>(
  redis: Redis,
  resource: string,
  fn: () => Promise<T>,
): Promise<T> {
  const token = crypto.randomUUID();
  const acquired = await redis.set(`lock:${resource}`, token, "EX", 30, "NX");
  if (acquired !== "OK") throw new Error("Lock not acquired");
  try {
    return await fn();
  } finally {
    await redis.eval(
      `if redis.call('GET',KEYS[1])==ARGV[1] then return redis.call('DEL',KEYS[1]) end`,
      1,
      `lock:${resource}`,
      token,
    );
  }
}
```
