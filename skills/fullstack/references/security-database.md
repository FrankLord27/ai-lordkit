# Seguridad en Base de Datos — PostgreSQL y Redis

---

## SQL Injection — prevención total con Prisma

Con Prisma ORM no hay interpolación de strings en queries. Las queries son
generadas con parámetros tipados. La inyección SQL es prácticamente imposible
usando el cliente tipado de Prisma correctamente.

```typescript
// ❌ Vulnerable — interpolación directa de input del usuario
const query = `SELECT * FROM users WHERE email = '${userInput}'`;
// Un atacante puede enviar: ' OR '1'='1 -- y acceder a todos los usuarios

// ✅ Prisma — parámetros tipados, imposible inyectar
const user = await prisma.user.findUnique({
  where: { email: userInput }, // ← Prisma escapa automáticamente
});
```

### Si necesitas queries raw — usa siempre parámetros

```typescript
// ❌ Vulnerable — interpolación en raw query
await prisma.$queryRawUnsafe(`SELECT * FROM items WHERE name = '${name}'`);

// ✅ Siempre con parámetros en queries raw
await prisma.$queryRaw`SELECT * FROM items WHERE name = ${name}`;
// o con array de parámetros:
await prisma.$queryRaw(
  Prisma.sql`SELECT * FROM items WHERE category = ${category} AND price < ${maxPrice}`,
);
```

---

## Configuración segura de PostgreSQL

### Usuario de base de datos con privilegios mínimos

```sql
-- Crear usuario dedicado para la aplicación — nunca usar el superuser postgres
CREATE USER appuser WITH PASSWORD 'password_seguro_aqui';

-- Dar acceso solo a la base de datos de la aplicación
GRANT CONNECT ON DATABASE myapp_db TO appuser;

-- Dar permisos solo a los schemas necesarios
GRANT USAGE ON SCHEMA public TO appuser;

-- Solo SELECT, INSERT, UPDATE, DELETE — nunca DROP, CREATE, TRUNCATE
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO appuser;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO appuser;

-- Para futuras tablas creadas con migrations
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appuser;

-- ❌ Nunca dar estos permisos al usuario de la aplicación
-- GRANT ALL PRIVILEGES ON DATABASE myapp_db TO appuser;  ← Demasiado amplio
-- GRANT SUPERUSER TO appuser;                            ← Nunca
```

### postgresql.conf — configuración de seguridad

```ini
# /etc/postgresql/16/main/postgresql.conf

# Solo escuchar en localhost — nunca exponer a internet directamente
listen_addresses = 'localhost'

# Conexiones SSL obligatorias
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'

# Límite de conexiones — previene agotamiento de recursos
max_connections = 100

# Log de queries lentas — identifica problemas de performance y accesos sospechosos
log_min_duration_statement = 1000  # queries que tarden más de 1 segundo

# Log de conexiones
log_connections = on
log_disconnections = on

# Log de intentos de auth fallidos
log_failed_login = on
```

### pg_hba.conf — quién puede conectarse

```
# /etc/postgresql/16/main/pg_hba.conf
# TYPE  DATABASE    USER      ADDRESS         METHOD

# Solo conexiones locales por socket Unix
local   all         postgres                  peer

# Conexiones locales de la app — require SSL y password
host    myapp_db    appuser   127.0.0.1/32    scram-sha-256

# Conexiones desde la red interna (si la DB está en servidor separado)
host    myapp_db    appuser   10.0.1.0/24     scram-sha-256

# Rechazar todo lo demás
host    all         all       0.0.0.0/0       reject
```

### Conexión SSL desde la aplicación

```env
# .env — siempre SSL en producción
DATABASE_URL=postgresql://appuser:password@localhost:5432/myapp_db?sslmode=require
```

```typescript
// Verificar SSL en el PrismaService
// La URL con ?sslmode=require ya fuerza SSL en Prisma
// Para certificado propio de CA:
DATABASE_URL=postgresql://appuser:password@db.host:5432/myapp_db?sslmode=verify-full&sslrootcert=/path/to/ca.crt
```

---

## Cifrado de datos sensibles en PostgreSQL

### Qué cifrar vs qué hashear

```
Hashear (irreversible):        Cifrar (reversible):
- Contraseñas                  - Números de tarjeta
- Tokens de verificación       - DNI / documentos de identidad
- PINs                         - Datos médicos
                               - Información bancaria sensible
```

### Cifrado con pgcrypto

```sql
-- Habilitar extensión
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Cifrar dato sensible al insertar
INSERT INTO users (dni, email)
VALUES (
  pgp_sym_encrypt('12345678A', current_setting('app.encryption_key')),
  'user@example.com'
);

-- Descifrar al leer
SELECT
  email,
  pgp_sym_decrypt(dni::bytea, current_setting('app.encryption_key')) as dni
FROM users
WHERE id = $1;
```

### Cifrado en la capa de aplicación (recomendado)

```typescript
// Mejor cifrar en la app — la clave no toca la base de datos
import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  scryptSync,
} from "crypto";

const ALGORITHM = "aes-256-gcm";
const ENCRYPTION_KEY = scryptSync(process.env.ENCRYPTION_SECRET, "salt", 32);

export function encrypt(text: string): string {
  const iv = randomBytes(16);
  const cipher = createCipheriv(ALGORITHM, ENCRYPTION_KEY, iv);

  let encrypted = cipher.update(text, "utf8", "hex");
  encrypted += cipher.final("hex");

  const authTag = cipher.getAuthTag();

  // Guardar iv + authTag + encrypted juntos
  return `${iv.toString("hex")}:${authTag.toString("hex")}:${encrypted}`;
}

export function decrypt(encryptedText: string): string {
  const [ivHex, authTagHex, encrypted] = encryptedText.split(":");

  const iv = Buffer.from(ivHex, "hex");
  const authTag = Buffer.from(authTagHex, "hex");
  const decipher = createDecipheriv(ALGORITHM, ENCRYPTION_KEY, iv);

  decipher.setAuthTag(authTag);

  let decrypted = decipher.update(encrypted, "hex", "utf8");
  decrypted += decipher.final("utf8");

  return decrypted;
}
```

---

## Backups seguros

```bash
# backup-db.sh — ejecutar con cron diariamente
#!/bin/bash

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/postgres"
DB_NAME="myapp_db"
RETENTION_DAYS=30

# Crear backup cifrado
pg_dump -h localhost -U postgres $DB_NAME \
  | gzip \
  | openssl enc -aes-256-cbc -salt -pass env:BACKUP_ENCRYPTION_KEY \
  > "$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz.enc"

# Eliminar backups más viejos que la retención definida
find $BACKUP_DIR -name "*.sql.gz.enc" -mtime +$RETENTION_DAYS -delete

echo "Backup completado: ${DB_NAME}_${DATE}.sql.gz.enc"
```

```bash
# Restaurar backup
openssl enc -aes-256-cbc -d -pass env:BACKUP_ENCRYPTION_KEY \
  -in backup.sql.gz.enc \
  | gunzip \
  | psql -h localhost -U postgres myapp_db
```

```
# Cron para backup diario a las 2am
0 2 * * * /scripts/backup-db.sh >> /var/log/backup.log 2>&1
```

**Regla del backup:** Probar la restauración cada mes. Un backup que nunca se ha restaurado no es un backup, es una esperanza.

---

## Auditoría de accesos en PostgreSQL

```sql
-- Tabla de auditoría — quién hizo qué y cuándo
CREATE TABLE audit_log (
  id         BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  action     TEXT NOT NULL,        -- INSERT, UPDATE, DELETE
  user_id    TEXT,                 -- ID del usuario de la aplicación
  record_id  TEXT,
  old_data   JSONB,
  new_data   JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Función trigger de auditoría
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (table_name, action, record_id, old_data, new_data)
  VALUES (
    TG_TABLE_NAME,
    TG_OP,
    CASE TG_OP WHEN 'DELETE' THEN OLD.id::TEXT ELSE NEW.id::TEXT END,
    CASE TG_OP WHEN 'INSERT' THEN NULL ELSE row_to_json(OLD) END,
    CASE TG_OP WHEN 'DELETE' THEN NULL ELSE row_to_json(NEW) END
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar a tablas sensibles
CREATE TRIGGER users_audit
  AFTER INSERT OR UPDATE OR DELETE ON users
  FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();
```

---

## Redis — configuración segura

### redis.conf — hardening

```ini
# /etc/redis/redis.conf

# Contraseña obligatoria — mínimo 32 caracteres aleatorios
requirepass "TU_PASSWORD_REDIS_32_CHARS_MIN_AQUI"

# Solo escuchar en localhost — nunca exponer a internet
bind 127.0.0.1

# Desactivar comandos peligrosos
rename-command FLUSHALL ""       # Borra toda la DB — desactivar en prod
rename-command FLUSHDB  ""       # Borra la DB actual — desactivar en prod
rename-command CONFIG   ""       # Acceso a configuración — desactivar en prod
rename-command DEBUG    ""       # Información de debug — desactivar en prod
rename-command KEYS     "KEYS_DISABLED"  # Bloquea enumeración de keys

# Límite de memoria — previene que Redis consuma toda la RAM
maxmemory 256mb
maxmemory-policy allkeys-lru    # Elimina las keys menos usadas cuando llega al límite

# TLS en producción (Redis 6+)
tls-port 6380
tls-cert-file /etc/ssl/redis/redis.crt
tls-key-file /etc/ssl/redis/redis.key
tls-ca-cert-file /etc/ssl/redis/ca.crt
```

### Conexión segura a Redis desde la aplicación

```typescript
// redis/redis.service.ts
import Redis from 'ioredis';

onModuleInit() {
  this.client = new Redis({
    host: process.env.REDIS_HOST ?? 'localhost',
    port: Number(process.env.REDIS_PORT ?? 6379),
    password: process.env.REDIS_PASSWORD, // ← Siempre password en producción
    // TLS en producción
    tls: process.env.NODE_ENV === 'production' ? {} : undefined,
    // Reconexión automática
    retryStrategy: (times) => Math.min(times * 50, 2000),
    // Timeout de conexión
    connectTimeout: 5000,
    lazyConnect: true,
  });

  this.client.on('error', (err) => {
    this.logger.error('Redis connection error:', err.message);
  });
}
```

### Nunca almacenar en Redis

```
❌ Contraseñas (ni hasheadas)
❌ Números de tarjeta
❌ Datos médicos
❌ Documentos de identidad
✅ Refresh tokens (strings opacos con TTL)
✅ Sesiones
✅ Cache de queries (datos ya sanitizados)
✅ Rate limiting counters
✅ Locks distribuidos
```
