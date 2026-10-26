# Redis — Hashes

Estructura para objetos con múltiples campos. Ideal para perfiles, sesiones, configuraciones.

## Comandos

```bash
HSET key field value          # Set campo
HSET key f1 v1 f2 v2          # Set múltiples
HGET key field                # Get campo
HMGET key f1 f2               # Get múltiples
HGETALL key                   # Get todo
HDEL key field                # Eliminar campo
HINCRBY key field 1           # Incrementar
HEXISTS key field             # ¿Existe campo?
HKEYS key                     # Lista de campos
HVALS key                     # Lista de valores
HLEN key                      # Cantidad de campos
```

```typescript
// Crear hash
await redis.hset("user:123", {
  name: "John",
  email: "j@ex.com",
  role: "admin",
});

// Obtener campo
const name = await redis.hget("user:123", "name");

// Obtener todo
const user = await redis.hgetall("user:123");
// { name: 'John', email: 'j@ex.com', role: 'admin' }

// Incrementar
await redis.hincrby("user:123", "loginCount", 1);
```

## Sesiones de Usuario

```typescript
interface Session {
  userId: string;
  email: string;
  role: string;
  tenantId: string;
}

class SessionStore {
  constructor(private redis: Redis) {}
  private key(id: string) {
    return `session:${id}`;
  }

  async create(sessionId: string, data: Session, ttl: number): Promise<void> {
    await this.redis.hset(this.key(sessionId), data as Record<string, string>);
    await this.redis.expire(this.key(sessionId), ttl);
  }

  async get(sessionId: string): Promise<Session | null> {
    const data = await this.redis.hgetall(this.key(sessionId));
    return Object.keys(data).length > 0 ? (data as unknown as Session) : null;
  }

  async refresh(sessionId: string, ttl: number): Promise<void> {
    await this.redis.expire(this.key(sessionId), ttl);
  }

  async destroy(sessionId: string): Promise<void> {
    await this.redis.del(this.key(sessionId));
  }
}
```

## Carrito de Compras

```typescript
class Cart {
  constructor(private redis: Redis) {}
  private key(userId: string) {
    return `cart:${userId}`;
  }

  async add(userId: string, productId: string, qty: number): Promise<void> {
    await this.redis.hincrby(this.key(userId), productId, qty);
    await this.redis.expire(this.key(userId), 7 * 24 * 3600); // 7 días
  }

  async get(userId: string): Promise<Record<string, number>> {
    const cart = await this.redis.hgetall(this.key(userId));
    return Object.fromEntries(
      Object.entries(cart).map(([k, v]) => [k, parseInt(v)]),
    );
  }

  async remove(userId: string, productId: string): Promise<void> {
    await this.redis.hdel(this.key(userId), productId);
  }
}
```

## Hash vs String+JSON

| Aspecto              | Hash          | String (JSON)     |
| -------------------- | ------------- | ----------------- |
| Leer un campo        | `HGET` O(1)   | Deserializar todo |
| Actualizar campo     | `HSET` O(1)   | Read-modify-write |
| Estructuras anidadas | ❌ No soporta | ✅ Sí             |

**Regla:** Usar Hash si accedes campos individualmente, String+JSON si siempre lees/escribes todo.
