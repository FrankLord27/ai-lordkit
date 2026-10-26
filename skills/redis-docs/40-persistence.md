# Redis — Persistencia

Cómo Redis guarda datos en disco para sobrevivir reinicios.

## Opciones

| Método               | Descripción          | Pérdida de datos   |
| -------------------- | -------------------- | ------------------ |
| **RDB**              | Snapshots periódicos | Hasta minutos      |
| **AOF**              | Log de operaciones   | Máximo ~1 segundo  |
| **RDB + AOF**        | Ambos (recomendado)  | Mínima             |
| **Sin persistencia** | Solo memoria         | Total al reiniciar |

## RDB (Snapshots)

```conf
# redis.conf
save 900 1      # Guardar si 1 cambio en 15 min
save 300 10     # Guardar si 10 cambios en 5 min
save 60 10000   # Guardar si 10000 cambios en 1 min

dbfilename dump.rdb
dir /var/lib/redis
rdbcompression yes
```

```bash
BGSAVE              # Crear snapshot (background)
LASTSAVE            # Ver último guardado
```

**Pros:** Archivos compactos, restauración rápida  
**Contras:** Puede perder datos entre snapshots

## AOF (Append Only File)

```conf
# redis.conf
appendonly yes
appendfilename "appendonly.aof"

# Cuándo sincronizar
appendfsync everysec    # Cada segundo (recomendado)
# appendfsync always    # Cada operación (más seguro, más lento)
# appendfsync no        # Dejar al OS

# Reescritura automática
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

```bash
BGREWRITEAOF        # Reescribir AOF (optimizar)
```

**Pros:** Pérdida mínima, log legible  
**Contras:** Archivos más grandes, restauración más lenta

## Configuración Recomendada

### Producción (balanceado)

```conf
appendonly yes
appendfsync everysec

save 900 1
save 300 10
save 60 10000
```

### Máxima durabilidad

```conf
appendonly yes
appendfsync always
```

### Cache puro (sin persistencia)

```conf
appendonly no
save ""
```

## Docker

```yaml
services:
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --appendfsync everysec
    volumes:
      - redis-data:/data
volumes:
  redis-data:
```

## Backup y Restauración

### Backup

```bash
#!/bin/bash
redis-cli BGSAVE
sleep 5
cp /var/lib/redis/dump.rdb /backups/redis-$(date +%Y%m%d).rdb
cp /var/lib/redis/appendonly.aof /backups/aof-$(date +%Y%m%d).aof
find /backups -name "*.rdb" -mtime +7 -delete
```

### Restauración

```bash
sudo systemctl stop redis
cp /backups/dump-20250325.rdb /var/lib/redis/dump.rdb
cp /backups/aof-20250325.aof /var/lib/redis/appendonly.aof
chown redis:redis /var/lib/redis/*
sudo systemctl start redis
```

## Health Check

```typescript
@Injectable()
export class RedisPersistenceHealth extends HealthIndicator {
  async isHealthy(key: string): Promise<HealthIndicatorResult> {
    const info = await this.redis.info("persistence");
    const rdbStatus = info.match(/rdb_last_bgsave_status:(\w+)/)?.[1];
    const aofStatus = info.match(/aof_last_rewrite_status:(\w+)/)?.[1];
    const lastSave = parseInt(
      info.match(/rdb_last_save_time:(\d+)/)?.[1] ?? "0",
    );
    const age = Date.now() / 1000 - lastSave;

    const healthy = rdbStatus === "ok" && aofStatus === "ok" && age < 3600;
    return this.getStatus(key, healthy, {
      rdbStatus,
      aofStatus,
      lastSaveAgo: `${Math.floor(age)}s`,
    });
  }
}
```
