# Administración de Base de Datos — PostgreSQL + Prisma + Redis

> ⚠️ **Prisma 7:** los ejemplos con `new PrismaClient()` / `extends PrismaClient` asumen el setup v7 con **driver adapter** (`@prisma/adapter-pg`) y `prisma.config.ts` — sin adapter NO compilan. Setup completo en `prisma7-docs`.

Herramientas y procedimientos para administrar bases de datos en desarrollo y producción.

---

## Herramientas de desarrollo

### Prisma Studio — explorador visual de datos

Prisma Studio viene incluido con Prisma. Es la forma más rápida de ver y editar datos durante el desarrollo.

```bash
# Levantar Prisma Studio (abre en http://localhost:5555)
npx prisma studio

# O desde el monorepo
pnpm --filter api prisma studio
```

**Cuándo usar Prisma Studio:**

- Ver datos rápidamente durante desarrollo
- Editar registros manualmente para testing
- Explorar relaciones entre tablas
- Verificar que las migrations aplicaron correctamente

**Cuándo NO usar:**

- En producción (no tiene auth, no es seguro)
- Para queries complejas (usar psql o pgAdmin)
- Para operaciones masivas (usar scripts)

---

### pgAdmin — administración completa de PostgreSQL

Para operaciones más avanzadas que Prisma Studio no cubre.

```yaml
# docker-compose.yml — agregar pgAdmin al stack de desarrollo
services:
  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: myproject-pgadmin
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@localhost.com
      PGADMIN_DEFAULT_PASSWORD: admin123
      PGADMIN_CONFIG_SERVER_MODE: "False" # Modo desktop, sin login
    ports:
      - "5050:80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    depends_on:
      - postgres

volumes:
  pgadmin_data:
```

```bash
# Acceder en http://localhost:5050
# Agregar servidor: Host=postgres, Port=5432, User=devuser, Password=devpassword
```

**Cuándo usar pgAdmin:**

- Ejecutar queries SQL complejas
- Ver planes de ejecución (EXPLAIN ANALYZE)
- Administrar usuarios y permisos
- Crear/restaurar backups
- Monitorear conexiones activas
- Ver estadísticas de tablas e índices

---

### DBeaver — alternativa multiplataforma

Si prefieres una herramienta desktop nativa:

```bash
# macOS
brew install --cask dbeaver-community

# Ubuntu/Debian
sudo snap install dbeaver-ce

# Windows — descargar de https://dbeaver.io
```

**Ventajas de DBeaver:**

- Soporta múltiples bases de datos (PostgreSQL, MySQL, SQLite, etc.)
- Editor SQL con autocompletado
- Diagrama ER automático
- Comparación de schemas entre ambientes

---

### Redis Commander — GUI para Redis

```yaml
# docker-compose.yml — agregar Redis Commander
services:
  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: myproject-redis-commander
    environment:
      REDIS_HOSTS: local:redis:6379
    ports:
      - "8081:8081"
    depends_on:
      - redis
```

```bash
# Acceder en http://localhost:8081
```

**Alternativa: RedisInsight (oficial de Redis)**

```bash
docker run -d --name redisinsight -p 8001:8001 redislabs/redisinsight:latest
# Acceder en http://localhost:8001
```

---

## Seeding — datos iniciales y fixtures

### Estructura de seeds

```
apps/api/prisma/
├── schema.prisma
├── seed.ts              ← Archivo principal de seed
└── seeds/
    ├── users.seed.ts    ← Seeds por dominio
    ├── categories.seed.ts
    └── fixtures/
        ├── dev.ts       ← Datos para desarrollo
        ├── staging.ts   ← Datos para staging
        └── test.ts      ← Datos para tests
```

### Configuración en package.json

```json
// apps/api/package.json
{
  "prisma": {
    "seed": "ts-node --transpile-only prisma/seed.ts"
  }
}
```

### Seed principal

```typescript
// prisma/seed.ts
import { PrismaClient } from "@prisma/client";
import { seedUsers } from "./seeds/users.seed";
import { seedCategories } from "./seeds/categories.seed";

const prisma = new PrismaClient();

async function main() {
  const env = process.env.SEED_ENV ?? "dev";
  console.log(`🌱 Seeding database for environment: ${env}`);

  // Orden importa por las foreign keys
  await seedCategories(prisma);
  await seedUsers(prisma, env);

  // Seeds específicos por ambiente
  if (env === "dev") {
    const { seedDevData } = await import("./seeds/fixtures/dev");
    await seedDevData(prisma);
  }

  console.log("✅ Seed completado");
}

main()
  .catch((e) => {
    console.error("❌ Error en seed:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
```

### Seeds por dominio con @faker-js/faker

```typescript
// prisma/seeds/users.seed.ts
import { PrismaClient, UserRole } from "@prisma/client";
import { faker } from "@faker-js/faker";
import * as bcrypt from "bcrypt";

export async function seedUsers(prisma: PrismaClient, env: string) {
  console.log("  → Seeding users...");

  // Usuario admin siempre existe
  const adminPassword = await bcrypt.hash("Admin123!", 12);
  await prisma.user.upsert({
    where: { email: "admin@example.com" },
    update: {},
    create: {
      email: "admin@example.com",
      password: adminPassword,
      name: "Administrador",
      role: UserRole.ADMIN,
      emailVerified: true,
    },
  });

  // En desarrollo: crear usuarios de prueba
  if (env === "dev") {
    const testPassword = await bcrypt.hash("Test123!", 12);

    // Usuario de prueba con credenciales conocidas
    await prisma.user.upsert({
      where: { email: "test@example.com" },
      update: {},
      create: {
        email: "test@example.com",
        password: testPassword,
        name: "Usuario de Prueba",
        role: UserRole.USER,
        emailVerified: true,
      },
    });

    // Usuarios random para poblar la UI
    const usersToCreate = 20;
    for (let i = 0; i < usersToCreate; i++) {
      await prisma.user.create({
        data: {
          email: faker.internet.email().toLowerCase(),
          password: testPassword,
          name: faker.person.fullName(),
          role: UserRole.USER,
          emailVerified: faker.datatype.boolean(),
          createdAt: faker.date.past({ years: 1 }),
        },
      });
    }

    console.log(`    ✓ ${usersToCreate + 2} users created`);
  }
}
```

### Ejecutar seeds

```bash
# Seed completo (usa SEED_ENV=dev por defecto)
npx prisma db seed

# Seed para staging
SEED_ENV=staging npx prisma db seed

# Reset completo: borra todo, aplica migrations, y seed
npx prisma migrate reset
# Esto ejecuta: drop → migrate → seed automáticamente
```

---

## Migrations — estrategias por ambiente

### Desarrollo: iterate rápido

```bash
# Crear migration después de cambiar schema.prisma
npx prisma migrate dev --name add_user_avatar

# Si algo sale mal, reset completo
npx prisma migrate reset

# Solo generar el cliente sin migration (para prototipar)
npx prisma generate
```

### Staging/Producción: migrations controladas

```bash
# NUNCA usar `migrate dev` en producción
# Usar `migrate deploy` que solo aplica migrations pendientes

npx prisma migrate deploy
```

### Script de deploy con migrations

```bash
#!/bin/bash
# scripts/deploy.sh

set -e  # Fallar si cualquier comando falla

echo "🚀 Iniciando deploy..."

# 1. Aplicar migrations pendientes
echo "📦 Aplicando migrations..."
npx prisma migrate deploy

# 2. Verificar que la DB está sana
echo "🔍 Verificando conexión..."
npx prisma db execute --stdin <<< "SELECT 1"

# 3. Iniciar la aplicación
echo "🏃 Iniciando aplicación..."
node dist/main.js
```

### Rollback de migrations

Prisma no tiene rollback automático. Estrategias:

```bash
# Opción 1: Crear migration inversa manualmente
npx prisma migrate dev --name rollback_user_avatar
# Editar el SQL generado para revertir los cambios

# Opción 2: Restaurar backup antes de la migration problemática
pg_restore -h localhost -U postgres -d myapp_db backup_antes_de_migration.dump

# Opción 3: Shadow database para probar migrations antes de aplicar
# Configurar en schema.prisma:
# datasource db {
#   shadowDatabaseUrl = env("SHADOW_DATABASE_URL")
# }
```

### Migration squashing (limpiar historial)

Cuando tienes demasiadas migrations en desarrollo:

```bash
# 1. Backup del schema actual
cp prisma/schema.prisma prisma/schema.prisma.backup

# 2. Borrar todas las migrations
rm -rf prisma/migrations

# 3. Reset la tabla de migrations en la DB
npx prisma migrate reset --skip-seed

# 4. Crear una migration "inicial" limpia
npx prisma migrate dev --name init

# 5. Verificar que todo funciona
npx prisma db seed
```

⚠️ **Solo hacer squashing en desarrollo.** En producción, el historial de migrations es sagrado.

---

## Backups y restauración

### Backup manual

```bash
# Backup completo con pg_dump
pg_dump -h localhost -U postgres -d myapp_db -F c -f backup_$(date +%Y%m%d_%H%M%S).dump

# Backup solo schema (sin datos)
pg_dump -h localhost -U postgres -d myapp_db --schema-only -f schema.sql

# Backup solo datos (para migrar entre ambientes)
pg_dump -h localhost -U postgres -d myapp_db --data-only -f data.sql
```

### Restauración

```bash
# Restaurar backup completo
pg_restore -h localhost -U postgres -d myapp_db -c backup.dump
# -c = limpiar (drop) objetos antes de crear

# Restaurar en una DB nueva
createdb -h localhost -U postgres myapp_db_restored
pg_restore -h localhost -U postgres -d myapp_db_restored backup.dump
```

### Backup automatizado (cron)

```bash
#!/bin/bash
# /scripts/backup-db.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/postgres"
DB_NAME="myapp_db"
RETENTION_DAYS=30

# Crear directorio si no existe
mkdir -p $BACKUP_DIR

# Backup comprimido
pg_dump -h localhost -U postgres $DB_NAME \
  -F c \
  -f "$BACKUP_DIR/${DB_NAME}_${DATE}.dump"

# Cifrar si es necesario (producción)
if [ "$NODE_ENV" = "production" ]; then
  openssl enc -aes-256-cbc -salt \
    -in "$BACKUP_DIR/${DB_NAME}_${DATE}.dump" \
    -out "$BACKUP_DIR/${DB_NAME}_${DATE}.dump.enc" \
    -pass env:BACKUP_ENCRYPTION_KEY
  rm "$BACKUP_DIR/${DB_NAME}_${DATE}.dump"
fi

# Eliminar backups viejos
find $BACKUP_DIR -name "*.dump*" -mtime +$RETENTION_DAYS -delete

echo "✅ Backup completado: ${DB_NAME}_${DATE}"
```

```bash
# Crontab: backup diario a las 2am
0 2 * * * /scripts/backup-db.sh >> /var/log/backup.log 2>&1
```

---

## Monitoreo de base de datos

### Queries lentas

```sql
-- Habilitar log de queries lentas en postgresql.conf
-- log_min_duration_statement = 1000  -- queries > 1 segundo

-- Ver queries actualmente ejecutándose
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
  AND state != 'idle';

-- Cancelar query problemática
SELECT pg_cancel_backend(pid);

-- Forzar terminación (último recurso)
SELECT pg_terminate_backend(pid);
```

### Estadísticas de tablas

```sql
-- Tamaño de tablas
SELECT
  relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  pg_size_pretty(pg_relation_size(relid)) AS data_size,
  pg_size_pretty(pg_indexes_size(relid)) AS index_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- Índices no utilizados (candidatos a eliminar)
SELECT
  schemaname || '.' || relname AS table,
  indexrelname AS index,
  pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
  idx_scan AS scans
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE idx_scan < 50  -- menos de 50 usos
  AND NOT indisunique  -- no es unique constraint
ORDER BY pg_relation_size(i.indexrelid) DESC;

-- Tablas que necesitan VACUUM
SELECT
  relname,
  n_dead_tup AS dead_tuples,
  n_live_tup AS live_tuples,
  last_vacuum,
  last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

### Conexiones activas

```sql
-- Ver todas las conexiones
SELECT
  pid,
  usename,
  application_name,
  client_addr,
  state,
  query_start,
  query
FROM pg_stat_activity
WHERE datname = 'myapp_db';

-- Contar conexiones por estado
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname = 'myapp_db'
GROUP BY state;

-- Cerrar conexiones idle de más de 10 minutos
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'myapp_db'
  AND state = 'idle'
  AND query_start < now() - interval '10 minutes';
```

---

## Comandos útiles de Prisma

```bash
# Ver estado actual de migrations
npx prisma migrate status

# Formatear schema.prisma
npx prisma format

# Validar schema sin aplicar cambios
npx prisma validate

# Ver diferencias entre schema y DB
npx prisma migrate diff \
  --from-schema-datamodel prisma/schema.prisma \
  --to-schema-datasource prisma/schema.prisma

# Introspección: generar schema desde DB existente
npx prisma db pull

# Push directo sin migration (solo desarrollo rápido)
npx prisma db push
```

---

## Checklist por ambiente

### Desarrollo

- [ ] Docker Compose con PostgreSQL y Redis levantado
- [ ] Prisma Studio disponible para explorar datos
- [ ] Seeds ejecutados con datos de prueba
- [ ] Variables de entorno en `.env` local

### Staging

- [ ] Migrations aplicadas con `migrate deploy`
- [ ] Seeds de staging ejecutados (sin datos sensibles)
- [ ] Backups configurados (diarios)
- [ ] pgAdmin accesible solo por VPN

### Producción

- [ ] Usuario de DB con privilegios mínimos
- [ ] SSL habilitado en conexión
- [ ] Backups cifrados y automatizados
- [ ] Monitoreo de queries lentas activo
- [ ] Alertas de espacio en disco
- [ ] Connection pooling (PgBouncer si es necesario)
- [ ] pgAdmin/Prisma Studio **NO expuestos** a internet
