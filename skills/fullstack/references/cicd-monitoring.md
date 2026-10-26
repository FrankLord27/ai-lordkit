# Monitoreo Post-Deploy

---

## Sentry — captura de errores en producción

```bash
pnpm add @sentry/nestjs @sentry/nextjs
```

### NestJS

```typescript
// apps/api/src/main.ts
import * as Sentry from "@sentry/nestjs";

// Inicializar ANTES de cualquier otra cosa
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  // No enviar en desarrollo ni test
  enabled: process.env.NODE_ENV === "production",
  // Porcentaje de transacciones a tracear (performance)
  tracesSampleRate: 0.1,
  // No loguear datos sensibles
  beforeSend(event) {
    if (event.request?.headers) {
      delete event.request.headers["authorization"];
      delete event.request.headers["cookie"];
    }
    return event;
  },
});
```

```typescript
// common/filters/http-exception.filter.ts — capturar en Sentry
import * as Sentry from "@sentry/nestjs";

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    // Solo capturar errores 5xx — los 4xx son del usuario, no del sistema
    if (status >= 500) {
      Sentry.captureException(exception);
    }

    // ... resto del filter
  }
}
```

### Next.js

```javascript
// apps/web/sentry.client.config.js
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  enabled: process.env.NODE_ENV === "production",
  tracesSampleRate: 0.1,
  // Ignorar errores de red que no son del sistema
  ignoreErrors: ["Network request failed", "Failed to fetch", "Load failed"],
});
```

---

## Health check endpoint — qué debe verificar

```typescript
// modules/health/health.controller.ts
@Controller("health")
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  @Get()
  async check() {
    const startTime = Date.now();

    // Verificar todas las dependencias críticas en paralelo
    const [dbCheck, redisCheck] = await Promise.allSettled([
      this.prisma.$queryRaw`SELECT 1 as ok`,
      this.redis.set("health:check", "ok", 10), // TTL 10s
    ]);

    const isHealthy =
      dbCheck.status === "fulfilled" && redisCheck.status === "fulfilled";

    const response = {
      status: isHealthy ? "ok" : "degraded",
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      responseTime: `${Date.now() - startTime}ms`,
      services: {
        database: dbCheck.status === "fulfilled" ? "ok" : "error",
        cache: redisCheck.status === "fulfilled" ? "ok" : "error",
      },
      version: process.env.APP_VERSION ?? "unknown",
    };

    // Retornar 503 si algún servicio crítico está caído
    // Nginx y el health check del docker-compose usan el status code
    if (!isHealthy) {
      throw new ServiceUnavailableException(response);
    }

    return response;
  }
}
```

---

## Logs estructurados — qué loguear y cómo

### Qué loguear siempre

```typescript
// ✅ Loguear: eventos de negocio importantes
this.logger.log({
  event: "booking.created",
  bookingId: booking.id,
  userId: user.id,
  totalPrice: booking.totalPrice,
});

// ✅ Loguear: errores con contexto suficiente para reproducir
this.logger.error({
  event: "payment.failed",
  userId: user.id,
  amount: payment.amount,
  provider: "stripe",
  error: error.message,
  // ❌ Nunca loguear: número de tarjeta, CVV, contraseñas, tokens
});

// ✅ Loguear: requests lentos (ya lo hace pino-http automáticamente)
// ✅ Loguear: errores 5xx (ya lo hace el ExceptionFilter)
// ✅ Loguear: intentos de auth fallidos
this.logger.warn({
  event: "auth.failed_login",
  email: dto.email, // OK loguear el email
  ip: request.ip,
  attempts: failedAttempts,
});
```

### Qué NUNCA loguear

```typescript
// ❌ Contraseñas
// ❌ Tokens JWT completos
// ❌ Números de tarjeta o datos bancarios
// ❌ Datos de salud o información médica
// ❌ Números de documento de identidad
// ❌ Claves API de terceros
```

### Pino con redacción automática de campos sensibles

```typescript
// app.module.ts
LoggerModule.forRoot({
  pinoHttp: {
    redact: {
      paths: [
        "req.headers.authorization",
        "req.headers.cookie",
        "req.body.password",
        "req.body.creditCard",
        'res.headers["set-cookie"]',
      ],
      censor: "[REDACTED]",
    },
  },
});
```

---

## Qué vigilar después de cada deploy — los primeros 10 minutos

```
Minuto 0-2: Health check
  □ El endpoint /health retorna 200
  □ La DB responde
  □ Redis responde

Minuto 2-5: Logs del API
  □ No hay errores nuevos 5xx en los logs
  □ El tiempo de respuesta es normal (< 200ms para queries simples)
  □ No hay errores de conexión a DB o Redis

Minuto 5-10: Sentry
  □ No hay nuevos issues abiertos
  □ El rate de errores no aumentó respecto al baseline
  □ No hay errores de "undefined" o "null reference" nuevos

Si algo está mal:
  → Rollback inmediato
  → Investigar en staging con los logs
  → No intentar hotfix directo en producción
```

---

## Alertas básicas — cuándo notificar

```bash
# Script simple de monitoreo — ejecutar con cron cada 5 minutos
#!/bin/bash

HEALTH_URL="http://localhost:3001/api/v1/health"
SLACK_WEBHOOK=$SLACK_WEBHOOK_URL

check_health() {
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_URL)

  if [ "$HTTP_STATUS" != "200" ]; then
    curl -X POST $SLACK_WEBHOOK \
      -H 'Content-type: application/json' \
      --data "{\"text\":\"🚨 Health check falló en producción (HTTP $HTTP_STATUS). Revisar inmediatamente.\"}"
  fi
}

check_disk() {
  USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
  if [ "$USAGE" -gt 85 ]; then
    curl -X POST $SLACK_WEBHOOK \
      -H 'Content-type: application/json' \
      --data "{\"text\":\"⚠️ Disco al ${USAGE}% en producción. Limpiar logs o aumentar almacenamiento.\"}"
  fi
}

check_health
check_disk
```

```
# Crontab — verificar cada 5 minutos
*/5 * * * * /scripts/monitor.sh >> /var/log/monitor.log 2>&1
```

---

## Rotación de logs — evitar que llenen el disco

```bash
# /etc/logrotate.d/docker-logs
/var/lib/docker/containers/*/*.log {
  daily
  rotate 7          # Mantener 7 días de logs
  compress
  missingok
  notifempty
  copytruncate
}
```

```json
// /etc/docker/daemon.json — límite de logs por contenedor
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```

```bash
# Aplicar cambio al daemon de Docker
systemctl reload docker
```
