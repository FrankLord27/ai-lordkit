# Redis — Pub/Sub

Mensajería real-time publish/subscribe. Para notificaciones y eventos broadcast.

> ⚠️ **Los mensajes NO se persisten.** Si no hay suscriptores, se pierden.

## Comandos

```bash
SUBSCRIBE channel1 channel2   # Suscribirse
PSUBSCRIBE pattern*           # Suscribirse con patrón
PUBLISH channel "message"     # Publicar (retorna # suscriptores)
UNSUBSCRIBE channel           # Desuscribirse
```

## Con ioredis

```typescript
// ⚠️ IMPORTANTE: Pub/Sub requiere conexiones SEPARADAS
const publisher = new Redis();
const subscriber = new Redis();

// Suscribirse
subscriber.subscribe("notifications", (err, count) => {
  console.log(`Subscribed to ${count} channels`);
});

// Manejar mensajes
subscriber.on("message", (channel, message) => {
  console.log(`${channel}: ${message}`);
});

// Suscribirse con patrón
subscriber.psubscribe("user:*:events");
subscriber.on("pmessage", (pattern, channel, message) => {
  console.log(`Pattern ${pattern}, channel ${channel}: ${message}`);
});

// Publicar
await publisher.publish(
  "notifications",
  JSON.stringify({ type: "alert", text: "Hello" }),
);
```

## Servicio de Notificaciones

```typescript
class NotificationService {
  private publisher: Redis;
  private subscriber: Redis;
  private handlers = new Map<string, ((data: any) => void)[]>();

  constructor(redisUrl: string) {
    this.publisher = new Redis(redisUrl);
    this.subscriber = new Redis(redisUrl);
    this.setupSubscriber();
  }

  private setupSubscriber(): void {
    this.subscriber.on("pmessage", (pattern, channel, message) => {
      const handlers = this.handlers.get(pattern) ?? [];
      const data = JSON.parse(message);
      handlers.forEach((h) => h(data));
    });
  }

  async broadcast(notification: object): Promise<number> {
    return this.publisher.publish(
      "notifications:broadcast",
      JSON.stringify(notification),
    );
  }

  async notifyUser(userId: string, notification: object): Promise<number> {
    return this.publisher.publish(
      `notifications:user:${userId}`,
      JSON.stringify(notification),
    );
  }

  onUserNotification(userId: string, handler: (data: any) => void): () => void {
    const pattern = `notifications:user:${userId}`;
    this.addHandler(pattern, handler);
    this.subscriber.psubscribe(pattern);
    return () => this.removeHandler(pattern, handler);
  }

  private addHandler(pattern: string, handler: (data: any) => void): void {
    const handlers = this.handlers.get(pattern) ?? [];
    this.handlers.set(pattern, [...handlers, handler]);
  }

  private removeHandler(pattern: string, handler: (data: any) => void): void {
    const handlers = this.handlers.get(pattern) ?? [];
    this.handlers.set(
      pattern,
      handlers.filter((h) => h !== handler),
    );
  }
}
```

## Cache Invalidation Distribuida

```typescript
class DistributedCache {
  private localCache = new Map<string, { value: any; expires: number }>();
  private publisher: Redis;
  private subscriber: Redis;

  constructor(redisUrl: string) {
    this.publisher = new Redis(redisUrl);
    this.subscriber = new Redis(redisUrl);

    this.subscriber.subscribe("cache:invalidate");
    this.subscriber.on("message", (channel, message) => {
      const { key, pattern } = JSON.parse(message);
      if (key) this.localCache.delete(key);
      if (pattern) {
        const regex = new RegExp(pattern.replace(/\*/g, ".*"));
        for (const k of this.localCache.keys()) {
          if (regex.test(k)) this.localCache.delete(k);
        }
      }
    });
  }

  async invalidate(key: string): Promise<void> {
    this.localCache.delete(key);
    await this.publisher.publish("cache:invalidate", JSON.stringify({ key }));
  }

  async invalidatePattern(pattern: string): Promise<void> {
    await this.publisher.publish(
      "cache:invalidate",
      JSON.stringify({ pattern }),
    );
  }
}
```

## Chat Room Simple

```typescript
class ChatService {
  private publisher: Redis;
  private subscriber: Redis;

  constructor(redisUrl: string) {
    this.publisher = new Redis(redisUrl);
    this.subscriber = new Redis(redisUrl);
  }

  async sendMessage(
    roomId: string,
    userId: string,
    content: string,
  ): Promise<void> {
    await this.publisher.publish(
      `chat:${roomId}`,
      JSON.stringify({
        userId,
        content,
        timestamp: new Date().toISOString(),
      }),
    );
  }

  joinRoom(roomId: string, onMessage: (msg: any) => void): () => void {
    const channel = `chat:${roomId}`;
    this.subscriber.subscribe(channel);

    const handler = (ch: string, message: string) => {
      if (ch === channel) onMessage(JSON.parse(message));
    };
    this.subscriber.on("message", handler);

    return () => {
      this.subscriber.unsubscribe(channel);
      this.subscriber.off("message", handler);
    };
  }
}
```

## Pub/Sub vs Streams

|                 | Pub/Sub           | Streams        |
| --------------- | ----------------- | -------------- |
| Persistencia    | ❌                | ✅             |
| Historial       | ❌                | ✅             |
| Consumer groups | ❌                | ✅             |
| Latencia        | Mínima            | Muy baja       |
| Uso ideal       | Real-time efímero | Event sourcing |
