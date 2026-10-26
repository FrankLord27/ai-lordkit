# Redis — Sets

Colecciones de strings únicos sin orden. Para tags, relaciones, deduplicación.

## Comandos

```bash
SADD key m1 m2                # Agregar (ignora duplicados)
SREM key m1 m2                # Eliminar
SMEMBERS key                  # Todos los miembros
SISMEMBER key member          # ¿Es miembro? → 1/0
SCARD key                     # Cantidad
SRANDMEMBER key 3             # 3 aleatorios
SPOP key                      # Quitar aleatorio

# Operaciones de conjuntos
SUNION key1 key2              # Unión
SINTER key1 key2              # Intersección
SDIFF key1 key2               # Diferencia
SINTERSTORE dest k1 k2        # Guardar resultado
```

```typescript
await redis.sadd("tags:post:123", "js", "redis", "backend");
const tags = await redis.smembers("tags:post:123");
const isMember = await redis.sismember("tags:post:123", "redis"); // 1

// Posts con tag 'js' Y 'redis'
const posts = await redis.sinter("tag:js:posts", "tag:redis:posts");
```

## Sistema de Tags con Índice Inverso

```typescript
class TagSystem {
  constructor(private redis: Redis) {}

  async addTags(entity: string, id: string, tags: string[]): Promise<void> {
    // Tags de la entidad
    await this.redis.sadd(`tags:${entity}:${id}`, ...tags);
    // Índice inverso: entidades por tag
    for (const tag of tags) {
      await this.redis.sadd(`tag:${tag}:${entity}s`, id);
    }
  }

  async getByAllTags(entity: string, tags: string[]): Promise<string[]> {
    const keys = tags.map((t) => `tag:${t}:${entity}s`);
    return this.redis.sinter(...keys);
  }

  async getByAnyTag(entity: string, tags: string[]): Promise<string[]> {
    const keys = tags.map((t) => `tag:${t}:${entity}s`);
    return this.redis.sunion(...keys);
  }
}
```

## Usuarios Online

```typescript
class OnlineTracker {
  constructor(private redis: Redis) {}
  private key() {
    return `online:${Math.floor(Date.now() / 300000)}`;
  } // Bucket 5min

  async heartbeat(userId: string): Promise<void> {
    await this.redis.sadd(this.key(), userId);
    await this.redis.expire(this.key(), 600);
  }

  async isOnline(userId: string): Promise<boolean> {
    return (await this.redis.sismember(this.key(), userId)) === 1;
  }

  async count(): Promise<number> {
    return this.redis.scard(this.key());
  }
}
```

## Deduplicación de Eventos

```typescript
class Deduplicator {
  constructor(private redis: Redis) {}

  async isDuplicate(
    eventType: string,
    eventId: string,
    windowSec = 3600,
  ): Promise<boolean> {
    const key = `dedup:${eventType}:${Math.floor(Date.now() / 1000 / windowSec)}`;
    const added = await this.redis.sadd(key, eventId);
    if (added === 1) {
      await this.redis.expire(key, windowSec * 2);
      return false; // Nuevo
    }
    return true; // Duplicado
  }
}

// Procesar webhook solo una vez
if (!(await dedup.isDuplicate("webhook", event.id))) {
  await processEvent(event);
}
```

## Sistema de Permisos

```typescript
class Permissions {
  constructor(private redis: Redis) {}

  async setRole(role: string, perms: string[]): Promise<void> {
    await this.redis.del(`role:${role}`);
    if (perms.length) await this.redis.sadd(`role:${role}`, ...perms);
  }

  async assignRole(userId: string, role: string): Promise<void> {
    await this.redis.sadd(`user:${userId}:roles`, role);
  }

  async hasPermission(userId: string, perm: string): Promise<boolean> {
    const roles = await this.redis.smembers(`user:${userId}:roles`);
    for (const role of roles) {
      if (await this.redis.sismember(`role:${role}`, perm)) return true;
    }
    return false;
  }
}
```
