# Redis — Streams

Log de eventos append-only con consumer groups. Para event sourcing y mensajería.

## Comandos Básicos

```bash
XADD stream * field value     # Agregar (* = ID auto)
XADD stream MAXLEN ~1000 * f v # Con límite
XRANGE stream - +             # Todos los mensajes
XREVRANGE stream + - COUNT 10 # Últimos 10
XLEN stream                   # Cantidad
XREAD STREAMS stream $        # Esperar nuevos
XREAD BLOCK 5000 STREAMS s $  # Bloqueante 5s
```

## Consumer Groups

```bash
XGROUP CREATE stream group $ MKSTREAM  # Crear grupo
XREADGROUP GROUP group consumer COUNT 10 STREAMS stream >  # Leer
XACK stream group id1 id2     # Confirmar procesado
XPENDING stream group         # Ver pendientes
XCLAIM stream group consumer 60000 id  # Reclamar mensaje
```

```typescript
// Agregar mensaje
const id = await redis.xadd(
  "orders",
  "*",
  "orderId",
  "123",
  "status",
  "created",
);

// Crear consumer group
try {
  await redis.xgroup("CREATE", "orders", "processors", "$", "MKSTREAM");
} catch (e) {
  /* grupo ya existe */
}

// Leer con grupo
const messages = await redis.xreadgroup(
  "GROUP",
  "processors",
  "worker-1",
  "COUNT",
  10,
  "STREAMS",
  "orders",
  ">",
);

// Confirmar procesado
await redis.xack("orders", "processors", messageId);
```

## Event Bus

```typescript
class EventBus {
  constructor(private redis: Redis) {}

  async publish(topic: string, type: string, data: object): Promise<string> {
    return this.redis.xadd(
      `events:${topic}`,
      "MAXLEN",
      "~",
      "10000",
      "*",
      "type",
      type,
      "data",
      JSON.stringify(data),
      "ts",
      Date.now().toString(),
    );
  }

  async subscribe(
    topic: string,
    handler: (event: { id: string; type: string; data: any }) => Promise<void>,
    fromId = "$",
  ): Promise<void> {
    let lastId = fromId;
    while (true) {
      const result = await this.redis.xread(
        "BLOCK",
        5000,
        "STREAMS",
        `events:${topic}`,
        lastId,
      );
      if (result) {
        for (const [, messages] of result) {
          for (const [id, fields] of messages) {
            const event = this.parseFields(id, fields);
            await handler(event);
            lastId = id;
          }
        }
      }
    }
  }

  private parseFields(id: string, fields: string[]) {
    const data: Record<string, string> = {};
    for (let i = 0; i < fields.length; i += 2) data[fields[i]] = fields[i + 1];
    return { id, type: data.type, data: JSON.parse(data.data) };
  }
}
```

## Consumer Group con Recovery

```typescript
class StreamConsumer {
  constructor(
    private redis: Redis,
    private stream: string,
    private group: string,
    private consumer: string,
  ) {}

  async init(): Promise<void> {
    try {
      await this.redis.xgroup(
        "CREATE",
        this.stream,
        this.group,
        "0",
        "MKSTREAM",
      );
    } catch (e) {
      /* existe */
    }
  }

  async start(handler: (msg: any) => Promise<void>): Promise<void> {
    // Primero procesar pendientes
    await this.processPending(handler);
    // Luego nuevos
    while (true) {
      const result = await this.redis.xreadgroup(
        "GROUP",
        this.group,
        this.consumer,
        "COUNT",
        10,
        "BLOCK",
        5000,
        "STREAMS",
        this.stream,
        ">",
      );
      if (result) {
        for (const [, msgs] of result) {
          for (const [id, fields] of msgs) {
            try {
              await handler(this.parse(id, fields));
              await this.redis.xack(this.stream, this.group, id);
            } catch (e) {
              console.error(`Failed ${id}`, e);
            }
          }
        }
      }
    }
  }

  private async processPending(
    handler: (msg: any) => Promise<void>,
  ): Promise<void> {
    let startId = "0";
    while (true) {
      const result = await this.redis.xreadgroup(
        "GROUP",
        this.group,
        this.consumer,
        "COUNT",
        10,
        "STREAMS",
        this.stream,
        startId,
      );
      if (!result || result[0][1].length === 0) break;
      for (const [, msgs] of result) {
        for (const [id, fields] of msgs) {
          try {
            await handler(this.parse(id, fields));
            await this.redis.xack(this.stream, this.group, id);
          } catch (e) {
            console.error(`Pending failed ${id}`, e);
          }
          startId = id;
        }
      }
    }
  }

  private parse(id: string, fields: string[]) {
    const data: Record<string, string> = {};
    for (let i = 0; i < fields.length; i += 2) data[fields[i]] = fields[i + 1];
    return { id, ...data };
  }
}
```

## Streams vs Lists vs Pub/Sub

|                 | Streams | Lists   | Pub/Sub |
| --------------- | ------- | ------- | ------- |
| Persistencia    | ✅      | ✅      | ❌      |
| Consumer groups | ✅      | ❌      | ❌      |
| Replay/Historia | ✅      | Parcial | ❌      |
| ACK             | ✅      | Manual  | ❌      |
