# Observabilidad — Monitoreo, Métricas y Alertas

Este documento expande el monitoreo básico (Sentry + health check) a un sistema de observabilidad completo.

---

## Los tres pilares de observabilidad

| Pilar        | Qué es                                    | Herramientas                     |
| ------------ | ----------------------------------------- | -------------------------------- |
| **Logs**     | Eventos discretos con contexto            | Pino, Winston → Loki, CloudWatch |
| **Métricas** | Valores numéricos agregados               | Prometheus, Datadog, CloudWatch  |
| **Traces**   | Flujo de una request a través del sistema | Jaeger, Zipkin, Datadog APM      |

**Regla:** Empezar con logs estructurados y Sentry. Agregar métricas y traces cuando el proyecto crece.

---

## Nivel 1: Logs estructurados (implementar siempre)

### Configuración de Pino en NestJS

```bash
pnpm add nestjs-pino pino-http pino-pretty
```

```typescript
// app.module.ts
import { LoggerModule } from "nestjs-pino";

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        // Nivel de log según ambiente
        level: process.env.NODE_ENV === "production" ? "info" : "debug",

        // Formato legible en desarrollo, JSON en producción
        transport:
          process.env.NODE_ENV !== "production"
            ? { target: "pino-pretty", options: { colorize: true } }
            : undefined,

        // Redactar campos sensibles automáticamente
        redact: {
          paths: [
            "req.headers.authorization",
            "req.headers.cookie",
            "req.body.password",
            "req.body.token",
            "req.body.creditCard",
            'res.headers["set-cookie"]',
          ],
          censor: "[REDACTED]",
        },

        // Campos personalizados en cada log
        customProps: (req) => ({
          tenantId: req.tenantId,
          userId: req.user?.sub,
          correlationId: req.headers["x-correlation-id"],
        }),

        // Serializar solo lo necesario del request
        serializers: {
          req: (req) => ({
            method: req.method,
            url: req.url,
            query: req.query,
            // No incluir body completo en producción
            ...(process.env.NODE_ENV !== "production" && { body: req.body }),
          }),
          res: (res) => ({
            statusCode: res.statusCode,
          }),
        },
      },
    }),
  ],
})
export class AppModule {}
```

### Usar el logger en services

```typescript
// modules/bookings/services/booking.service.ts
import { Injectable, Logger } from "@nestjs/common";

@Injectable()
export class BookingService {
  private readonly logger = new Logger(BookingService.name);

  async createBooking(tenantId: string, dto: CreateBookingDto, userId: string) {
    this.logger.log({
      event: "booking.create.started",
      tenantId,
      userId,
      carId: dto.carId,
      dates: { pickup: dto.pickupDate, return: dto.returnDate },
    });

    try {
      const booking = await this.bookingRepository.create(
        tenantId,
        dto,
        userId,
      );

      this.logger.log({
        event: "booking.create.success",
        bookingId: booking.id,
        tenantId,
        totalPrice: booking.totalPrice,
      });

      return booking;
    } catch (error) {
      this.logger.error({
        event: "booking.create.failed",
        tenantId,
        userId,
        carId: dto.carId,
        error: error.message,
      });
      throw error;
    }
  }
}
```

### Centralizar logs en producción

```yaml
# docker-compose.prod.yml — enviar logs a Loki
services:
  api:
    logging:
      driver: loki
      options:
        loki-url: "http://loki:3100/loki/api/v1/push"
        loki-batch-size: "400"
        labels: "app=api,env=production"

# O con Fluentd
services:
  api:
    logging:
      driver: fluentd
      options:
        fluentd-address: "localhost:24224"
        tag: "api.{{.Name}}"
```

---

## Nivel 2: Sentry mejorado (errores + performance)

### Configuración completa

```typescript
// apps/api/src/instrument.ts — cargar ANTES de cualquier import
import * as Sentry from "@sentry/nestjs";
import { nodeProfilingIntegration } from "@sentry/profiling-node";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.APP_VERSION, // Para tracking de releases

  // Solo en producción
  enabled: process.env.NODE_ENV === "production",

  // Performance monitoring
  tracesSampleRate: 0.1, // 10% de requests para traces
  profilesSampleRate: 0.1, // 10% de traces para profiling

  integrations: [nodeProfilingIntegration()],

  // No enviar datos sensibles
  beforeSend(event) {
    if (event.request?.headers) {
      delete event.request.headers["authorization"];
      delete event.request.headers["cookie"];
    }
    if (event.request?.data) {
      // Redactar campos sensibles del body
      const sensitiveFields = ["password", "token", "creditCard"];
      sensitiveFields.forEach((field) => {
        if (event.request!.data[field]) {
          event.request!.data[field] = "[REDACTED]";
        }
      });
    }
    return event;
  },

  // Ignorar errores de red del cliente
  ignoreErrors: [
    "Network request failed",
    "Failed to fetch",
    "Load failed",
    "ECONNREFUSED",
  ],
});

export { Sentry };
```

```typescript
// main.ts — cargar instrument primero
import "./instrument"; // ← Debe ser el primer import
import { NestFactory } from "@nestjs/core";
// ...
```

### Agregar contexto de usuario y tenant

```typescript
// common/interceptors/sentry-context.interceptor.ts
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from "@nestjs/common";
import { Observable } from "rxjs";
import * as Sentry from "@sentry/nestjs";

@Injectable()
export class SentryContextInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const request = context.switchToHttp().getRequest();

    Sentry.setUser({
      id: request.user?.sub,
      email: request.user?.email,
    });

    Sentry.setTag("tenant_id", request.tenantId);
    Sentry.setTag("tenant_slug", request.tenant?.slug);

    return next.handle();
  }
}

// Registrar globalmente en main.ts
app.useGlobalInterceptors(new SentryContextInterceptor());
```

### Crear transacciones para operaciones importantes

```typescript
// Transacciones manuales para operaciones de negocio críticas
async function processPayment(bookingId: string, amount: number) {
  return Sentry.startSpan(
    {
      op: "payment.process",
      name: `Process payment for booking ${bookingId}`,
    },
    async (span) => {
      span.setAttribute("booking_id", bookingId);
      span.setAttribute("amount", amount);

      try {
        const result = await stripeService.charge(amount);
        span.setStatus({ code: 1, message: "ok" });
        return result;
      } catch (error) {
        span.setStatus({ code: 2, message: error.message });
        throw error;
      }
    },
  );
}
```

---

## Nivel 3: Métricas de aplicación (cuando escala)

### Prometheus + NestJS

```bash
pnpm add @willsoto/nestjs-prometheus prom-client
```

```typescript
// app.module.ts
import { PrometheusModule } from "@willsoto/nestjs-prometheus";

@Module({
  imports: [
    PrometheusModule.register({
      path: "/metrics", // Endpoint para Prometheus
      defaultMetrics: { enabled: true },
    }),
  ],
})
export class AppModule {}
```

### Métricas de negocio personalizadas

```typescript
// common/metrics/business.metrics.ts
import { Injectable } from "@nestjs/common";
import { InjectMetric } from "@willsoto/nestjs-prometheus";
import { Counter, Histogram, Gauge } from "prom-client";

@Injectable()
export class BusinessMetrics {
  constructor(
    @InjectMetric("bookings_created_total")
    private readonly bookingsCreated: Counter<string>,

    @InjectMetric("booking_duration_seconds")
    private readonly bookingDuration: Histogram<string>,

    @InjectMetric("active_users_total")
    private readonly activeUsers: Gauge<string>,
  ) {}

  incrementBookings(tenantId: string, status: "success" | "failed") {
    this.bookingsCreated.inc({ tenant_id: tenantId, status });
  }

  observeBookingDuration(tenantId: string, durationSeconds: number) {
    this.bookingDuration.observe({ tenant_id: tenantId }, durationSeconds);
  }

  setActiveUsers(tenantId: string, count: number) {
    this.activeUsers.set({ tenant_id: tenantId }, count);
  }
}

// Registrar métricas en el módulo
import {
  makeCounterProvider,
  makeHistogramProvider,
  makeGaugeProvider,
} from "@willsoto/nestjs-prometheus";

@Module({
  providers: [
    BusinessMetrics,
    makeCounterProvider({
      name: "bookings_created_total",
      help: "Total de reservas creadas",
      labelNames: ["tenant_id", "status"],
    }),
    makeHistogramProvider({
      name: "booking_duration_seconds",
      help: "Duración del proceso de reserva",
      labelNames: ["tenant_id"],
      buckets: [0.1, 0.5, 1, 2, 5, 10],
    }),
    makeGaugeProvider({
      name: "active_users_total",
      help: "Usuarios activos por tenant",
      labelNames: ["tenant_id"],
    }),
  ],
  exports: [BusinessMetrics],
})
export class MetricsModule {}
```

### Usar métricas en services

```typescript
// modules/bookings/services/booking.service.ts
@Injectable()
export class BookingService {
  constructor(
    private readonly metrics: BusinessMetrics,
    // ...
  ) {}

  async createBooking(tenantId: string, dto: CreateBookingDto) {
    const startTime = Date.now();

    try {
      const booking = await this.bookingRepository.create(tenantId, dto);
      this.metrics.incrementBookings(tenantId, "success");
      return booking;
    } catch (error) {
      this.metrics.incrementBookings(tenantId, "failed");
      throw error;
    } finally {
      const duration = (Date.now() - startTime) / 1000;
      this.metrics.observeBookingDuration(tenantId, duration);
    }
  }
}
```

### Grafana dashboards

```yaml
# docker-compose.monitoring.yml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin

volumes:
  grafana_data:
```

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "api"
    static_configs:
      - targets: ["api:3001"]
    metrics_path: "/metrics"
```

---

## Nivel 4: Distributed Tracing (microservicios)

### OpenTelemetry setup

```bash
pnpm add @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node
pnpm add @opentelemetry/exporter-trace-otlp-http @opentelemetry/exporter-metrics-otlp-http
```

```typescript
// tracing.ts — cargar antes de cualquier import
import { NodeSDK } from "@opentelemetry/sdk-node";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { OTLPMetricExporter } from "@opentelemetry/exporter-metrics-otlp-http";
import { PeriodicExportingMetricReader } from "@opentelemetry/sdk-metrics";

const sdk = new NodeSDK({
  serviceName: process.env.SERVICE_NAME ?? "api",
  traceExporter: new OTLPTraceExporter({
    url:
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT ?? "http://jaeger:4318/v1/traces",
  }),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter({
      url:
        process.env.OTEL_EXPORTER_OTLP_ENDPOINT ??
        "http://jaeger:4318/v1/metrics",
    }),
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      "@opentelemetry/instrumentation-http": { enabled: true },
      "@opentelemetry/instrumentation-express": { enabled: true },
      "@opentelemetry/instrumentation-pg": { enabled: true },
      "@opentelemetry/instrumentation-redis": { enabled: true },
    }),
  ],
});

sdk.start();
process.on("SIGTERM", () => sdk.shutdown());
```

### Jaeger para visualizar traces

```yaml
# docker-compose.monitoring.yml
services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686" # UI
      - "4318:4318" # OTLP HTTP
    environment:
      COLLECTOR_OTLP_ENABLED: true
```

---

## Alertas

### Alertas básicas con Prometheus Alertmanager

```yaml
# alert.rules.yml
groups:
  - name: api_alerts
    rules:
      # Error rate alto
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate > 5%"
          description: "{{ $value | humanizePercentage }} de requests fallando"

      # Latencia alta
      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P95 latency > 1s"

      # DB connections agotándose
      - alert: DatabaseConnectionsHigh
        expr: pg_stat_activity_count / pg_settings_max_connections > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "DB connections > 80%"

      # Health check fallando
      - alert: ServiceDown
        expr: up{job="api"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "API is down"
```

### Notificaciones a Slack

```yaml
# alertmanager.yml
global:
  slack_api_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

route:
  receiver: "slack-notifications"
  routes:
    - match:
        severity: critical
      receiver: "slack-critical"
    - match:
        severity: warning
      receiver: "slack-warnings"

receivers:
  - name: "slack-critical"
    slack_configs:
      - channel: "#alerts-critical"
        title: "🚨 {{ .CommonAnnotations.summary }}"
        text: "{{ .CommonAnnotations.description }}"
        send_resolved: true

  - name: "slack-warnings"
    slack_configs:
      - channel: "#alerts-warnings"
        title: "⚠️ {{ .CommonAnnotations.summary }}"
        text: "{{ .CommonAnnotations.description }}"
```

---

## Checklist por fase del proyecto

### MVP / Pre-launch

- [ ] Logs estructurados con Pino
- [ ] Sentry para errores (tracesSampleRate: 0)
- [ ] Health check endpoint
- [ ] Alertas de health check (uptime robot o similar)

### Post-launch / Crecimiento

- [ ] Sentry con performance monitoring (tracesSampleRate: 0.1)
- [ ] Métricas básicas con Prometheus
- [ ] Grafana dashboard con métricas clave
- [ ] Alertas de error rate y latencia

### Escala / Múltiples servicios

- [ ] OpenTelemetry + Jaeger para distributed tracing
- [ ] Métricas de negocio por tenant
- [ ] Log aggregation (Loki, ELK, Datadog)
- [ ] SLIs/SLOs definidos
- [ ] Runbooks para cada alerta

---

## Métricas clave a monitorear

| Métrica          | Qué indica              | Alerta si                                       |
| ---------------- | ----------------------- | ----------------------------------------------- |
| Request rate     | Tráfico actual          | Caída súbita (problema) o pico (posible ataque) |
| Error rate (5xx) | Salud del sistema       | > 1% sostenido                                  |
| Latency P95      | Experiencia del usuario | > 1 segundo                                     |
| DB connections   | Recursos de DB          | > 80% del pool                                  |
| Memory usage     | Memory leaks            | > 85% RAM del contenedor                        |
| CPU usage        | Carga de procesamiento  | > 80% sostenido                                 |
| Disk usage       | Espacio disponible      | > 85%                                           |
| Bookings/hour    | Métrica de negocio      | Caída vs baseline                               |
| Active users     | Engagement              | Tendencia decreciente                           |
