# Deploy y Servidores

---

## Estructura de archivos en el servidor

```
/apps/
├── production/
│   ├── docker-compose.yml    ← El compose de producción
│   ├── .env                  ← Variables de entorno (permisos 600)
│   ├── .env.db               ← Solo credenciales de PostgreSQL
│   └── .prev-tag             ← Tag del deploy anterior (para rollback)
│
└── staging/
    ├── docker-compose.yml
    ├── .env
    └── .env.db
```

```bash
# Permisos correctos para archivos de entorno
chmod 600 /apps/production/.env
chmod 600 /apps/production/.env.db
chown appuser:appuser /apps/production/.env
```

---

## Variables de entorno en producción

El archivo `.env` vive en el servidor, no en el repo.

```bash
# /apps/production/.env
# Gestionado manualmente en el servidor o via secrets manager

NODE_ENV=production
PORT=3001
FRONTEND_URL=https://tudominio.com

# Base de datos
DATABASE_URL=postgresql://appuser:PASSWORD_PROD@localhost:5432/myapp_prod

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=PASSWORD_REDIS_PROD

# JWT — generar con: openssl rand -hex 32
JWT_SECRET=SECRETO_GENERADO_CON_OPENSSL_32_BYTES_MINIMO
JWT_EXPIRES_IN=15m
REFRESH_TOKEN_EXPIRES_IN=7d

# Sentry
SENTRY_DSN=https://...@sentry.io/...

# Otros servicios
SENDGRID_API_KEY=SG....
STRIPE_SECRET_KEY=sk_live_...
```

```bash
# /apps/production/.env.db — solo para el contenedor de PostgreSQL
POSTGRES_USER=appuser
POSTGRES_PASSWORD=PASSWORD_PROD
POSTGRES_DB=myapp_prod
```

---

## Zero-downtime deploy con Docker Compose

Docker Compose v2 hace rolling update cuando el servicio tiene healthcheck.
El contenedor nuevo no recibe tráfico hasta que pasa el healthcheck.

```bash
# deploy.sh — script ejecutado por GitHub Actions vía SSH

#!/bin/bash
set -e   # Salir inmediatamente si cualquier comando falla

IMAGE_TAG=$1
APP_DIR=/apps/production

echo "🚀 Iniciando deploy: $IMAGE_TAG"

cd $APP_DIR

# Guardar tag actual para rollback
CURRENT_TAG=$(docker inspect myapp-api --format='{{.Config.Image}}' 2>/dev/null \
  | cut -d: -f2 || echo "none")
echo $CURRENT_TAG > .prev-tag
echo "Tag anterior guardado: $CURRENT_TAG"

# Pull nuevas imágenes
docker pull ghcr.io/$REPO/api:$IMAGE_TAG
docker pull ghcr.io/$REPO/web:$IMAGE_TAG

# Aplicar migraciones ANTES de actualizar el contenedor
echo "📦 Aplicando migraciones..."
docker run --rm \
  --network myapp-network \
  --env-file .env \
  ghcr.io/$REPO/api:$IMAGE_TAG \
  npx prisma migrate deploy

# Actualizar contenedores — sin downtime gracias al healthcheck
echo "🔄 Actualizando contenedores..."
IMAGE_TAG=$IMAGE_TAG docker-compose up -d --no-deps --wait api web

# Verificar health check
echo "🏥 Verificando health check..."
sleep 5
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/v1/health)

if [ "$HTTP_STATUS" != "200" ]; then
  echo "❌ Health check falló (HTTP $HTTP_STATUS). Ejecutando rollback..."
  ./rollback.sh
  exit 1
fi

echo "✅ Deploy completado exitosamente: $IMAGE_TAG"
```

```bash
# rollback.sh

#!/bin/bash
set -e

APP_DIR=/apps/production
cd $APP_DIR

PREV_TAG=$(cat .prev-tag)

if [ -z "$PREV_TAG" ] || [ "$PREV_TAG" = "none" ]; then
  echo "❌ No hay tag anterior para rollback"
  exit 1
fi

echo "⏪ Rollback a: $PREV_TAG"

IMAGE_TAG=$PREV_TAG docker-compose up -d --no-deps api web

sleep 5
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/v1/health)

if [ "$HTTP_STATUS" = "200" ]; then
  echo "✅ Rollback completado a: $PREV_TAG"
else
  echo "❌ Rollback falló también. Intervención manual requerida."
  exit 1
fi
```

---

## Migraciones de Prisma — manejo seguro

Las migraciones son el punto más delicado del deploy. Un error puede
dejar la DB en estado inconsistente.

### Reglas de migraciones seguras

```
✅ Permitido — backward compatible:
   Agregar tabla nueva
   Agregar columna opcional (con DEFAULT o nullable)
   Agregar índice

⚠️ Requiere cuidado — dos fases:
   Renombrar columna → agregar nueva, migrar datos, eliminar antigua
   Cambiar tipo de columna → idem

❌ Peligroso — puede romper la app anterior:
   Eliminar columna que usa la app actual
   Renombrar columna directamente
   Cambiar tipo de columna con datos existentes
```

### Estrategia expand-contract para cambios destructivos

```
Fase 1 (Deploy 1): Agregar nueva columna, mantener la antigua
  - La app lee de la nueva columna si existe, si no de la antigua
  - Migrar datos existentes a la nueva columna

Fase 2 (Deploy 2): La app solo usa la nueva columna

Fase 3 (Deploy 3): Eliminar la columna antigua
```

### Verificar migration antes del deploy

```bash
# Ver qué migrations pendientes hay
npx prisma migrate status

# Ver el SQL que se va a ejecutar — revisarlo antes de deploy en producción
npx prisma migrate diff \
  --from-schema-datasource prisma/schema.prisma \
  --to-schema-datamodel prisma/schema.prisma \
  --script

# Aplicar en producción — nunca prisma migrate dev en producción
npx prisma migrate deploy
```

---

## Nginx como reverse proxy — configuración de producción

```nginx
# /etc/nginx/sites-available/myapp
# Ver configuración completa en cybersecurity-web → server-security.md

# Lo específico para el proxy a Docker:
upstream api_backend {
    server 127.0.0.1:3001;
    keepalive 32;
}

upstream web_frontend {
    server 127.0.0.1:3000;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    server_name tudominio.com;

    # Proxy al frontend
    location / {
        proxy_pass http://web_frontend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Proxy al API
    location /api/ {
        proxy_pass http://api_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 30s;
    }
}
```

---

## Gestión de entornos — qué va en cada uno

| Aspecto          | Development             | Staging              | Production            |
| ---------------- | ----------------------- | -------------------- | --------------------- |
| Base de datos    | Local Docker            | Servidor staging     | Servidor producción   |
| Datos            | Seeds de desarrollo     | Seeds realistas      | Datos reales          |
| Deploy           | Manual (`pnpm dev`)     | Auto en merge a main | Manual con aprobación |
| Debug            | Activo                  | Desactivado          | Desactivado           |
| Logs             | Pretty print            | JSON estructurado    | JSON estructurado     |
| Sentry           | Desactivado             | Habilitado           | Habilitado            |
| HTTPS            | No                      | Sí                   | Sí                    |
| Rate limiting    | Relajado                | Igual a producción   | Activo                |
| Variables `.env` | Local en repo (example) | GitHub Secrets       | En el servidor        |

---

## Comandos de diagnóstico rápido en producción

```bash
# Estado general de los contenedores
docker-compose ps

# Logs del API en tiempo real
docker-compose logs -f api --tail=50

# Logs del Web
docker-compose logs -f web --tail=50

# Health check manual
curl http://localhost:3001/api/v1/health

# Ver qué imagen está corriendo exactamente
docker inspect myapp-api --format='{{.Config.Image}}'

# Uso de recursos
docker stats --no-stream

# Espacio en disco
df -h
docker system df

# Conexiones activas a la DB
docker exec myapp-postgres psql -U appuser -d myapp_prod \
  -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Limpiar logs viejos de Docker (libera espacio)
docker system prune -f
```
