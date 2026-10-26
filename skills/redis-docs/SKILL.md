---
name: redis-docs
description: >
  Documentación completa de Redis para aplicaciones NestJS. Usa esta skill siempre que
  trabajes con: cache de API, sesiones de usuario, rate limiting, colas de trabajo (BullMQ),
  pub/sub, leaderboards, datos geoespaciales, o cualquier uso de Redis. Cubre todas las
  estructuras de datos (Strings, Hashes, Lists, Sets, Sorted Sets, Streams, JSON, Geo),
  patrones de cache, integración con NestJS, y configuración de producción.
---

# Redis Skill — Referencia Completa

> **Redis** = Remote Dictionary Server  
> Base de datos en memoria ultra-rápida (~1ms latencia) con estructuras de datos avanzadas.

---

## Navegación Rápida

### Fundamentos

| Archivo                 | Contenido                                         |
| ----------------------- | ------------------------------------------------- |
| `01-setup.md`           | Instalación, CLI, configuración, clientes Node.js |
| `02-keys-expiration.md` | Keys, TTL, namespacing, expiración                |
| `03-transactions.md`    | MULTI/EXEC, Lua scripts, pipelines                |

### Estructuras de Datos

| Archivo             | Estructura  | Caso de uso                |
| ------------------- | ----------- | -------------------------- |
| `10-strings.md`     | Strings     | Cache, contadores, flags   |
| `11-hashes.md`      | Hashes      | Objetos, sesiones, configs |
| `12-lists.md`       | Lists       | Colas, feeds, logs         |
| `13-sets.md`        | Sets        | Tags, relaciones, dedup    |
| `14-sorted-sets.md` | Sorted Sets | Rankings, scheduling       |
| `15-streams.md`     | Streams     | Event sourcing, mensajería |
| `16-pubsub.md`      | Pub/Sub     | Real-time, notificaciones  |

### Patrones y Producción

| Archivo                    | Contenido                                      |
| -------------------------- | ---------------------------------------------- |
| `20-cache-patterns.md`     | Cache-aside, invalidación, stampede protection |
| `23-queues-bullmq.md`      | Colas con @nestjs/bullmq                       |
| `30-nestjs-integration.md` | Integración completa NestJS                    |
| `40-persistence.md`        | RDB, AOF, backups                              |
| `42-monitoring.md`         | INFO, SLOWLOG, health checks, métricas         |

---

## Instalación Rápida

```bash
# Docker
docker run -d --name redis -p 6379:6379 redis:7-alpine

# Verificar
docker exec -it redis redis-cli ping  # → PONG

# Node.js
pnpm add ioredis
```

```typescript
import Redis from "ioredis";
const redis = new Redis({ host: "localhost", port: 6379 });

await redis.set("key", "value");
const value = await redis.get("key");
```

---

## Comandos Esenciales

```bash
SET key "value"              # Guardar
GET key                      # Obtener
DEL key                      # Eliminar
EXPIRE key 60                # TTL 60 segundos
TTL key                      # Ver tiempo restante
KEYS pattern*                # Buscar (¡no en prod!)
SCAN 0 MATCH pattern*        # Buscar seguro
INFO                         # Estadísticas
```

---

## Convención de Keys

```
{tipo}:{entidad}:{id}:{campo}

cache:user:123               # Cache de usuario
session:abc123               # Sesión
lock:order:456               # Lock distribuido
queue:emails                 # Cola de trabajo
ratelimit:ip:192.168.1.1     # Rate limit
```

---

## Documentación oficial (Context7)

Para la doc oficial y actualizada de Redis, consulta el MCP **Context7** (`resolve-library-id` → `query-docs`) antes de generar código con APIs que no domines al 100%. Si contradice esta skill en una regla del estándar, gana la skill; si es un detalle de API, gana Context7.

