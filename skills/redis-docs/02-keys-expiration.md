# Redis — Keys, TTL y Expiración

## Convención de Naming

```
{tipo}:{entidad}:{id}:{subcampo}

cache:user:123         # Cache de usuario
session:token123       # Sesión por token
lock:order:456         # Lock distribuido
queue:emails           # Cola de trabajo
ratelimit:ip:1.2.3.4   # Rate limit
```

## Comandos de Keys

```bash
EXISTS key                    # Verificar existencia
TYPE key                      # Tipo de dato
RENAME old new                # Renombrar
KEYS pattern*                 # Buscar (¡NO en producción!)
SCAN 0 MATCH pattern* COUNT 100  # Buscar seguro (paginado)
DEL key1 key2                 # Eliminar
UNLINK key1 key2              # Eliminar async (no bloquea)
```

## TTL (Time To Live)

```bash
# Al crear
SET key "value" EX 60         # Expira en 60 segundos
SETEX key 60 "value"          # Equivalente

# Después de crear
EXPIRE key 60                 # Establecer TTL
TTL key                       # Ver TTL restante (-1 sin TTL, -2 no existe)
PERSIST key                   # Remover TTL
```

## Patrones Comunes

```typescript
// Cache con TTL
await redis.setex("cache:user:123", 300, JSON.stringify(user));

// TTL con jitter (evitar stampede)
function getTTLWithJitter(base: number): number {
  return base + Math.floor(Math.random() * 60);
}
await redis.setex(key, getTTLWithJitter(300), value);

// Sliding window (renovar en cada acceso)
await redis.expire(`session:${id}`, 1800); // 30 min desde ahora
```

## Eliminar por Patrón

```typescript
async function deletePattern(redis: Redis, pattern: string): Promise<number> {
  let cursor = "0";
  let deleted = 0;
  do {
    const [next, keys] = await redis.scan(
      cursor,
      "MATCH",
      pattern,
      "COUNT",
      100,
    );
    cursor = next;
    if (keys.length > 0) {
      deleted += await redis.unlink(...keys);
    }
  } while (cursor !== "0");
  return deleted;
}

await deletePattern(redis, "cache:products:*");
```
