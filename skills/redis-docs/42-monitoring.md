# Redis — Monitoreo y Debugging

## Comandos de Diagnóstico

### INFO

```bash
redis-cli INFO              # Todo
redis-cli INFO memory       # Solo memoria
redis-cli INFO clients      # Clientes
redis-cli INFO stats        # Estadísticas
redis-cli INFO persistence  # Estado RDB/AOF
redis-cli INFO replication  # Replicación
```

### Métricas Clave

```
# Memoria
used_memory_human           # Memoria usada
used_memory_peak_human      # Pico de memoria
maxmemory_human             # Límite configurado
mem_fragmentation_ratio     # Ideal: 1.0-1.5

# Clientes
connected_clients           # Clientes conectados
blocked_clients             # Bloqueados (BLPOP, etc.)

# Stats
instantaneous_ops_per_sec   # Operaciones/segundo
keyspace_hits               # Cache hits
keyspace_misses             # Cache misses
# Hit rate = hits / (hits + misses)

# Persistencia
rdb_last_bgsave_status      # ok/err
aof_last_rewrite_status     # ok/err
```

### MONITOR (debugging)

```bash
redis-cli MONITOR    # Ver comandos en tiempo real (¡NO en prod con alto tráfico!)
# 1679000001.123 [0 127.0.0.1:52345] "GET" "user:123"
```

### SLOWLOG

```bash
redis-cli SLOWLOG GET 10              # Ver queries lentas
CONFIG SET slowlog-log-slower-than 10000  # Umbral: 10ms
SLOWLOG RESET                         # Limpiar
```

### CLIENT LIST

```bash
redis-cli CLIENT LIST     # Ver clientes conectados
redis-cli CLIENT KILL ADDR 127.0.0.1:52345  # Matar cliente
```

### MEMORY

```bash
MEMORY USAGE mykey        # Bytes de una key
MEMORY DOCTOR             # Diagnóstico
redis-cli --bigkeys       # Encontrar keys grandes
```

## Health Check NestJS

```typescript
@Injectable()
export class RedisHealthIndicator extends HealthIndicator {
  constructor(@Inject(REDIS_CLIENT) private redis: Redis) {
    super();
  }

  async isHealthy(key: string): Promise<HealthIndicatorResult> {
    try {
      const start = Date.now();
      const info = await this.redis.info();
      const latency = Date.now() - start;

      const getValue = (name: string) =>
        info.match(new RegExp(`${name}:(.+)`))?.[1]?.trim();

      const hits = parseInt(getValue("keyspace_hits") ?? "0");
      const misses = parseInt(getValue("keyspace_misses") ?? "0");
      const hitRate =
        hits + misses > 0 ? Math.round((hits / (hits + misses)) * 100) : 100;

      return this.getStatus(key, true, {
        latency: `${latency}ms`,
        clients: getValue("connected_clients"),
        memory: getValue("used_memory_human"),
        opsPerSec: getValue("instantaneous_ops_per_sec"),
        hitRate: `${hitRate}%`,
      });
    } catch (error) {
      throw new HealthCheckError("Redis failed", this.getStatus(key, false));
    }
  }
}
```

## Métricas Prometheus

```typescript
@Injectable()
export class RedisMetricsService {
  private connectedClients = new Gauge({
    name: "redis_connected_clients",
    help: "Connected clients",
  });
  private usedMemory = new Gauge({
    name: "redis_used_memory_bytes",
    help: "Used memory",
  });
  private hitRate = new Gauge({
    name: "redis_hit_rate",
    help: "Cache hit rate",
  });
  private opsPerSecond = new Gauge({
    name: "redis_ops_per_second",
    help: "Ops/sec",
  });

  constructor(@Inject(REDIS_CLIENT) private redis: Redis) {
    setInterval(() => this.collect(), 15000);
  }

  private async collect() {
    const info = await this.redis.info();
    const getValue = (n: string) =>
      parseFloat(info.match(new RegExp(`${n}:(.+)`))?.[1] ?? "0");

    this.connectedClients.set(getValue("connected_clients"));
    this.usedMemory.set(getValue("used_memory"));
    this.opsPerSecond.set(getValue("instantaneous_ops_per_sec"));

    const hits = getValue("keyspace_hits"),
      misses = getValue("keyspace_misses");
    if (hits + misses > 0) this.hitRate.set(hits / (hits + misses));
  }
}
```

## Alertas Recomendadas

| Métrica                   | Warning          | Critical         |
| ------------------------- | ---------------- | ---------------- |
| `used_memory`             | > 80% maxmemory  | > 95%            |
| `connected_clients`       | > 80% maxclients | > 95%            |
| `mem_fragmentation_ratio` | > 1.5            | < 1.0 (swapping) |
| `rdb_last_bgsave_status`  | -                | ≠ ok             |
| `aof_last_rewrite_status` | -                | ≠ ok             |
| Cache hit rate            | < 80%            | < 50%            |
| Latency                   | > 10ms           | > 100ms          |

## Redis Insight (GUI)

```bash
docker run -d --name redis-insight -p 8001:8001 redislabs/redisinsight:latest
```

Acceder en `http://localhost:8001`

Features: Browser visual, monitoreo real-time, análisis de memoria, CLI integrado, profiler.

## Benchmark

```bash
redis-benchmark -h localhost -p 6379 -c 50 -n 100000
redis-benchmark -t get,set -n 100000 -q
```

## Checklist de Monitoreo

- [ ] Health check endpoint implementado
- [ ] SLOWLOG configurado (umbral 10ms)
- [ ] Alertas para memoria, persistencia, latencia
- [ ] Métricas exportadas a Prometheus/similar
- [ ] Redis Insight o GUI para debugging
- [ ] Backups verificados periódicamente
