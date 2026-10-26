# Redis — Lists

Listas ordenadas. Ideales para colas, pilas, feeds, y logs.

## Comandos

```bash
LPUSH key v1 v2               # Agregar al inicio
RPUSH key v1 v2               # Agregar al final
LPOP key                      # Quitar del inicio
RPOP key                      # Quitar del final
LRANGE key 0 -1               # Obtener todos
LRANGE key 0 9                # Primeros 10
LLEN key                      # Cantidad
LINDEX key 0                  # Elemento por índice
LTRIM key 0 99                # Mantener solo 0-99
BLPOP key timeout             # Pop bloqueante
LMOVE src dst LEFT RIGHT      # Mover entre listas
```

## Patrones de Cola

```typescript
// FIFO (cola normal)
await redis.rpush("queue", "job1"); // Agregar al final
const job = await redis.lpop("queue"); // Tomar del inicio

// LIFO (stack)
await redis.lpush("stack", "item");
const item = await redis.lpop("stack");

// Blocking pop (espera si está vacía)
const [key, job] = await redis.blpop("queue", 5); // 5s timeout
```

## Cola de Tareas Simple

```typescript
class JobQueue {
  constructor(
    private redis: Redis,
    private name: string,
  ) {}
  private get key() {
    return `queue:${this.name}`;
  }

  async enqueue(job: object): Promise<void> {
    await this.redis.rpush(this.key, JSON.stringify(job));
  }

  async dequeue(timeout = 5): Promise<object | null> {
    const result = await this.redis.blpop(this.key, timeout);
    return result ? JSON.parse(result[1]) : null;
  }

  async length(): Promise<number> {
    return this.redis.llen(this.key);
  }
}

// Producer
const queue = new JobQueue(redis, "emails");
await queue.enqueue({ to: "user@ex.com", template: "welcome" });

// Consumer
while (true) {
  const job = await queue.dequeue();
  if (job) await processJob(job);
}
```

## Activity Feed

```typescript
class ActivityFeed {
  constructor(private redis: Redis) {}
  private key(userId: string) {
    return `feed:${userId}`;
  }

  async push(userId: string, event: object): Promise<void> {
    const key = this.key(userId);
    await this.redis.lpush(key, JSON.stringify({ ...event, ts: Date.now() }));
    await this.redis.ltrim(key, 0, 99); // Últimos 100
  }

  async get(userId: string, limit = 20): Promise<object[]> {
    const items = await this.redis.lrange(this.key(userId), 0, limit - 1);
    return items.map((i) => JSON.parse(i));
  }
}
```

## Reliable Queue (con LMOVE)

```typescript
// Mover de pending a processing atómicamente
const job = await redis.lmove(
  "queue:pending",
  "queue:processing",
  "LEFT",
  "RIGHT",
);

// Si falla, mover de vuelta
await redis.lmove("queue:processing", "queue:pending", "LEFT", "LEFT");
```

> **Nota:** Para colas en producción, usa BullMQ → ver `23-queues-bullmq.md`
