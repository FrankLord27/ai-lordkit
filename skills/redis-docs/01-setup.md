# Redis — Setup e Instalación

## Docker (Recomendado)

```bash
# Básico
docker run -d --name redis -p 6379:6379 redis:7-alpine

# Con persistencia
docker run -d --name redis -p 6379:6379 -v redis-data:/data \
  redis:7-alpine redis-server --appendonly yes

# Docker Compose
```

```yaml
services:
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    volumes: [redis-data:/data]
    command: redis-server --appendonly yes
volumes:
  redis-data:
```

## Cliente Node.js (ioredis)

```bash
pnpm add ioredis
```

```typescript
import Redis from "ioredis";

const redis = new Redis({
  host: process.env.REDIS_HOST ?? "localhost",
  port: parseInt(process.env.REDIS_PORT ?? "6379"),
  password: process.env.REDIS_PASSWORD,
  retryStrategy(times) {
    return Math.min(times * 50, 2000);
  },
});

redis.on("error", (err) => console.error("Redis error:", err));
redis.on("ready", () => console.log("Redis ready"));

// Uso
await redis.set("key", "value");
await redis.setex("key", 300, "value"); // Con TTL
const value = await redis.get("key");
```

## Configuración Importante (redis.conf)

```conf
bind 127.0.0.1                    # Solo localhost
requirepass your_password         # Password obligatorio en prod
maxmemory 256mb                   # Límite de memoria
maxmemory-policy allkeys-lru      # Eviction policy
appendonly yes                    # Persistencia AOF
appendfsync everysec              # Sync cada segundo
```

## Variables de Entorno

```env
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=secret
REDIS_URL=redis://:password@localhost:6379/0
```
