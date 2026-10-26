# Redis — Transacciones y Lua Scripts

## MULTI/EXEC (Transacciones)

```typescript
// Transacción básica
const results = await redis
  .multi()
  .set("user:123:name", "John")
  .incr("user:123:visits")
  .expire("user:123:name", 3600)
  .exec();
// results = [[null, 'OK'], [null, 1], [null, 1]]
```

## WATCH (Optimistic Locking)

```typescript
async function transfer(
  from: string,
  to: string,
  amount: number,
): Promise<boolean> {
  await redis.watch(`balance:${from}`, `balance:${to}`);

  const fromBalance = parseInt((await redis.get(`balance:${from}`)) ?? "0");
  if (fromBalance < amount) {
    await redis.unwatch();
    throw new Error("Insufficient funds");
  }

  const result = await redis
    .multi()
    .decrby(`balance:${from}`, amount)
    .incrby(`balance:${to}`, amount)
    .exec();

  return result !== null; // null si alguien modificó las keys
}
```

## Pipeline (sin atomicidad, mejor performance)

```typescript
const results = await redis
  .pipeline()
  .set("key1", "v1")
  .set("key2", "v2")
  .get("key1")
  .exec();
```

## Lua Scripts (atómicos)

```typescript
// Definir comando personalizado
redis.defineCommand("getOrSetEx", {
  numberOfKeys: 1,
  lua: `
    local value = redis.call('GET', KEYS[1])
    if value then return value end
    redis.call('SETEX', KEYS[1], ARGV[2], ARGV[1])
    return ARGV[1]
  `,
});

const data = await redis.getOrSetEx("cache:key", "default", 300);
```

## Scripts Comunes

```typescript
// Rate limiting
redis.defineCommand("rateLimit", {
  numberOfKeys: 1,
  lua: `
    local key, limit, window, now = KEYS[1], tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3])
    redis.call('ZREMRANGEBYSCORE', key, 0, now - window)
    local count = redis.call('ZCARD', key)
    if count >= limit then return 0 end
    redis.call('ZADD', key, now, now .. '-' .. math.random())
    redis.call('EXPIRE', key, window)
    return 1
  `,
});

// Distributed lock
redis.defineCommand("acquireLock", {
  numberOfKeys: 1,
  lua: `
    if redis.call('SET', KEYS[1], ARGV[1], 'NX', 'EX', ARGV[2]) then return 1 end
    return 0
  `,
});
```
