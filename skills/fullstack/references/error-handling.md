# Manejo de Errores — Sistema Unificado

Este documento integra el manejo de errores entre las tres capas del stack:
**NestJS (API)** → **TanStack Query (fetch)** → **Next.js (UI)**

---

## Principio central

> Un error debe capturarse una sola vez, en el lugar correcto, y propagarse de forma predecible hasta la UI.

```
NestJS HttpExceptionFilter
    ↓ JSON normalizado
apiClient (fetch wrapper)
    ↓ ApiClientError tipado
TanStack Query
    ↓ error state + callbacks
React Error Boundary / UI
    ↓ Toast, modal, o página de error
Usuario ve feedback claro
```

---

## Capa 1: NestJS — Errores normalizados

El `HttpExceptionFilter` ya existe en tu stack. Este es el contrato de errores:

```typescript
// Estructura de error que SIEMPRE retorna la API
interface ApiErrorResponse {
  statusCode: number; // 400, 401, 403, 404, 500, etc.
  error: string; // 'BAD_REQUEST', 'UNAUTHORIZED', etc.
  message: string; // Mensaje legible para el usuario
  code?: string; // Código interno opcional: 'AUTH_001', 'BOOKING_OVERLAP'
  details?: unknown; // Detalles adicionales (validación, debug en dev)
  timestamp: string; // ISO 8601
  path: string; // URL del request
}
```

### Códigos de error internos (opcional pero recomendado)

Para proyectos medianos/grandes, usar códigos internos facilita el debugging y la documentación:

```typescript
// common/errors/error-codes.ts
export const ErrorCodes = {
  // Auth
  AUTH_INVALID_CREDENTIALS: "AUTH_001",
  AUTH_TOKEN_EXPIRED: "AUTH_002",
  AUTH_REFRESH_FAILED: "AUTH_003",
  AUTH_INSUFFICIENT_PERMISSIONS: "AUTH_004",

  // Recursos
  RESOURCE_NOT_FOUND: "RES_001",
  RESOURCE_ALREADY_EXISTS: "RES_002",
  RESOURCE_CONFLICT: "RES_003",

  // Validación
  VALIDATION_FAILED: "VAL_001",

  // Negocio (específicos del dominio)
  BOOKING_DATE_OVERLAP: "BKG_001",
  BOOKING_CAR_UNAVAILABLE: "BKG_002",
  PAYMENT_INSUFFICIENT_FUNDS: "PAY_001",
} as const;

// Uso en el service
throw new ConflictException({
  message: "El auto ya está reservado en esas fechas",
  code: ErrorCodes.BOOKING_DATE_OVERLAP,
});
```

### HttpExceptionFilter mejorado

```typescript
// common/filters/http-exception.filter.ts
import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
} from "@nestjs/common";
import { Request, Response } from "express";
import * as Sentry from "@sentry/nestjs";

interface ExceptionPayload {
  message: string | string[];
  code?: string;
  details?: unknown;
}

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request>();

    const status = this.getStatus(exception);
    const payload = this.getPayload(exception);

    // Solo loguear y reportar errores del servidor (5xx)
    if (status >= 500) {
      this.logger.error(`${req.method} ${req.url}`, exception);
      Sentry.captureException(exception, {
        extra: { path: req.url, method: req.method, body: req.body },
      });
    }

    // Log de errores 4xx en desarrollo para debug
    if (
      status >= 400 &&
      status < 500 &&
      process.env.NODE_ENV === "development"
    ) {
      this.logger.warn(
        `${req.method} ${req.url} → ${status}: ${payload.message}`,
      );
    }

    res.status(status).json({
      statusCode: status,
      error: HttpStatus[status],
      message: Array.isArray(payload.message)
        ? payload.message[0]
        : payload.message,
      code: payload.code,
      // Solo en desarrollo: mostrar todos los errores de validación
      ...(process.env.NODE_ENV === "development" &&
      Array.isArray(payload.message)
        ? { details: payload.message }
        : {}),
      timestamp: new Date().toISOString(),
      path: req.url,
    });
  }

  private getStatus(exception: unknown): number {
    if (exception instanceof HttpException) {
      return exception.getStatus();
    }
    return HttpStatus.INTERNAL_SERVER_ERROR;
  }

  private getPayload(exception: unknown): ExceptionPayload {
    if (exception instanceof HttpException) {
      const response = exception.getResponse();
      if (typeof response === "object") {
        return response as ExceptionPayload;
      }
      return { message: response as string };
    }
    return { message: "Error interno del servidor" };
  }
}
```

---

## Capa 2: apiClient — Errores tipados

El `apiClient` transforma las respuestas de error en excepciones tipadas que TanStack Query puede manejar.

```typescript
// lib/api-client.ts
const BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001/api/v1";

// Tipos de error que el cliente puede manejar
export type ErrorCode =
  | "NETWORK_ERROR" // Sin conexión o timeout
  | "AUTH_ERROR" // 401, 403
  | "VALIDATION_ERROR" // 400
  | "NOT_FOUND" // 404
  | "CONFLICT" // 409
  | "SERVER_ERROR" // 500+
  | "UNKNOWN";

export class ApiClientError extends Error {
  constructor(
    public override message: string,
    public statusCode: number,
    public errorCode: ErrorCode,
    public code?: string, // Código interno de la API (AUTH_001, etc.)
    public details?: unknown,
  ) {
    super(message);
    this.name = "ApiClientError";
  }

  // Helpers para la UI
  get isAuthError(): boolean {
    return this.errorCode === "AUTH_ERROR";
  }

  get isValidationError(): boolean {
    return this.errorCode === "VALIDATION_ERROR";
  }

  get isNetworkError(): boolean {
    return this.errorCode === "NETWORK_ERROR";
  }

  get isRetryable(): boolean {
    return (
      this.errorCode === "NETWORK_ERROR" || this.errorCode === "SERVER_ERROR"
    );
  }
}

function categorizeError(status: number): ErrorCode {
  if (status === 401 || status === 403) return "AUTH_ERROR";
  if (status === 400) return "VALIDATION_ERROR";
  if (status === 404) return "NOT_FOUND";
  if (status === 409) return "CONFLICT";
  if (status >= 500) return "SERVER_ERROR";
  return "UNKNOWN";
}

async function apiFetch<T>(
  endpoint: string,
  options?: RequestInit,
): Promise<T> {
  let response: Response;

  try {
    response = await fetch(`${BASE_URL}${endpoint}`, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...options?.headers,
      },
      credentials: "include",
    });
  } catch (error) {
    // Error de red: sin conexión, DNS, timeout, CORS
    throw new ApiClientError(
      "No se pudo conectar con el servidor. Verifica tu conexión.",
      0,
      "NETWORK_ERROR",
    );
  }

  if (!response.ok) {
    let errorData: { message?: string; code?: string; details?: unknown } = {};

    try {
      errorData = await response.json();
    } catch {
      // La respuesta no es JSON (error de proxy, Nginx, etc.)
      errorData = { message: "Error inesperado del servidor" };
    }

    throw new ApiClientError(
      errorData.message ?? "Error desconocido",
      response.status,
      categorizeError(response.status),
      errorData.code,
      errorData.details,
    );
  }

  // Respuesta exitosa
  const result = await response.json();
  return result.data ?? result;
}

export const apiClient = {
  get: <T>(url: string, options?: RequestInit) =>
    apiFetch<T>(url, { ...options, method: "GET" }),

  post: <T>(url: string, body: unknown, options?: RequestInit) =>
    apiFetch<T>(url, {
      ...options,
      method: "POST",
      body: JSON.stringify(body),
    }),

  put: <T>(url: string, body: unknown, options?: RequestInit) =>
    apiFetch<T>(url, { ...options, method: "PUT", body: JSON.stringify(body) }),

  patch: <T>(url: string, body: unknown, options?: RequestInit) =>
    apiFetch<T>(url, {
      ...options,
      method: "PATCH",
      body: JSON.stringify(body),
    }),

  delete: <T>(url: string, options?: RequestInit) =>
    apiFetch<T>(url, { ...options, method: "DELETE" }),
};
```

---

## Capa 3: TanStack Query — Manejo global de errores

### QueryClient con manejo de errores global

```typescript
// lib/query-client.ts
import { QueryClient, QueryCache, MutationCache } from "@tanstack/react-query";
import { ApiClientError } from "./api-client";
import { toast } from "sonner"; // o tu sistema de toasts preferido

// Handler global para errores de queries
function handleQueryError(error: unknown) {
  if (!(error instanceof ApiClientError)) {
    console.error("Error no manejado en query:", error);
    return;
  }

  // Errores de auth: redirigir al login
  if (error.isAuthError) {
    // No mostrar toast — el redirect es suficiente feedback
    window.location.href = "/login?expired=true";
    return;
  }

  // Errores de red: toast con opción de reintentar
  if (error.isNetworkError) {
    toast.error("Sin conexión", {
      description: "Verifica tu conexión a internet",
      action: { label: "Reintentar", onClick: () => window.location.reload() },
    });
    return;
  }

  // Errores 5xx: toast genérico
  if (error.errorCode === "SERVER_ERROR") {
    toast.error("Error del servidor", {
      description: "Estamos trabajando para solucionarlo",
    });
  }
}

// Handler global para errores de mutations
function handleMutationError(error: unknown) {
  if (!(error instanceof ApiClientError)) {
    console.error("Error no manejado en mutation:", error);
    toast.error("Error inesperado");
    return;
  }

  // Los errores de auth en mutations también redirigen
  if (error.isAuthError) {
    window.location.href = "/login?expired=true";
    return;
  }

  // Errores de validación: el formulario debe manejarlos, no el global
  if (error.isValidationError) {
    // No hacer nada aquí — el onError de la mutation específica lo maneja
    return;
  }

  // Errores de negocio (409 Conflict, etc.): mostrar mensaje de la API
  if (error.errorCode === "CONFLICT" || error.errorCode === "NOT_FOUND") {
    toast.error(error.message);
    return;
  }

  // Errores de red y servidor
  if (error.isNetworkError) {
    toast.error("Sin conexión", { description: "El cambio no se guardó" });
    return;
  }

  if (error.errorCode === "SERVER_ERROR") {
    toast.error("Error al guardar", {
      description: "Intenta de nuevo en unos segundos",
    });
  }
}

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutos
      retry: (failureCount, error) => {
        // Solo reintentar errores de red o servidor, máximo 2 veces
        if (error instanceof ApiClientError && error.isRetryable) {
          return failureCount < 2;
        }
        return false;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 10000),
      refetchOnWindowFocus: false,
    },
    mutations: {
      retry: false, // Las mutations no se reintentan automáticamente
    },
  },
  queryCache: new QueryCache({
    onError: handleQueryError,
  }),
  mutationCache: new MutationCache({
    onError: handleMutationError,
  }),
});
```

### Manejo de errores en mutations específicas

```typescript
// features/booking/api/use-create-booking.ts
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { ApiClientError } from "@/lib/api-client";
import { toast } from "sonner";

export const useCreateBooking = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (data: CreateBookingInput) =>
      apiClient.post<Booking>("/bookings", data),

    onSuccess: (booking) => {
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast.success("Reserva creada", {
        description: `Confirmación #${booking.confirmationCode}`,
      });
    },

    onError: (error) => {
      // Manejar errores específicos del dominio
      if (error instanceof ApiClientError) {
        // Error de negocio específico
        if (error.code === "BOOKING_DATE_OVERLAP") {
          toast.error("Fechas no disponibles", {
            description: "El vehículo ya está reservado en esas fechas",
          });
          return;
        }

        // Errores de validación: mostrar en el formulario, no toast
        if (error.isValidationError) {
          // El formulario debe usar form.setError() con los detalles
          return;
        }
      }

      // El handler global de MutationCache maneja el resto
    },
  });
};
```

---

## Capa 4: React — Error Boundaries

### Error Boundary global para Client Components

```tsx
// components/providers/ErrorBoundary.tsx
"use client";

import { Component, ReactNode } from "react";
import { Button } from "@/components/ui/Button";

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error?: Error;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    // Reportar a Sentry
    console.error("ErrorBoundary caught:", error, errorInfo);
  }

  handleReset = () => {
    this.setState({ hasError: false, error: undefined });
  };

  render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="error-boundary">
          <h2>Algo salió mal</h2>
          <p>Ha ocurrido un error inesperado.</p>
          <Button onClick={this.handleReset}>Intentar de nuevo</Button>
          <Button variant="secondary" onClick={() => window.location.reload()}>
            Recargar página
          </Button>
        </div>
      );
    }

    return this.props.children;
  }
}
```

### QueryErrorResetBoundary para TanStack Query

```tsx
// components/providers/QueryErrorBoundary.tsx
"use client";

import { QueryErrorResetBoundary } from "@tanstack/react-query";
import { ErrorBoundary } from "./ErrorBoundary";
import { Button } from "@/components/ui/Button";

interface Props {
  children: React.ReactNode;
}

export function QueryErrorBoundary({ children }: Props) {
  return (
    <QueryErrorResetBoundary>
      {({ reset }) => (
        <ErrorBoundary
          fallback={
            <div className="query-error">
              <h3>Error al cargar los datos</h3>
              <Button onClick={reset}>Reintentar</Button>
            </div>
          }
        >
          {children}
        </ErrorBoundary>
      )}
    </QueryErrorResetBoundary>
  );
}
```

### Integración en el layout

```tsx
// app/layout.tsx
"use client";

import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "@/lib/query-client";
import { ErrorBoundary } from "@/components/providers/ErrorBoundary";
import { Toaster } from "sonner";

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html>
      <body>
        <ErrorBoundary>
          <QueryClientProvider client={queryClient}>
            {children}
            <Toaster position="top-right" richColors />
          </QueryClientProvider>
        </ErrorBoundary>
      </body>
    </html>
  );
}
```

### error.tsx de Next.js (Server Components)

```tsx
// app/error.tsx — Error boundary automático de Next.js para Server Components
"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/Button";

interface Props {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function GlobalError({ error, reset }: Props) {
  useEffect(() => {
    // Reportar a Sentry
    console.error("Global error:", error);
  }, [error]);

  return (
    <div className="global-error">
      <h1>Error</h1>
      <p>Ha ocurrido un error inesperado.</p>
      {error.digest && (
        <p className="error-digest">Código de error: {error.digest}</p>
      )}
      <Button onClick={reset}>Intentar de nuevo</Button>
      <Button variant="secondary" onClick={() => (window.location.href = "/")}>
        Ir al inicio
      </Button>
    </div>
  );
}
```

---

## Resumen: Qué error se maneja dónde

| Tipo de error             | Dónde se maneja              | Acción                       |
| ------------------------- | ---------------------------- | ---------------------------- |
| 401/403 Unauthorized      | QueryClient global           | Redirect a `/login`          |
| 400 Validation            | Mutation específica          | `form.setError()`            |
| 404 Not Found             | Mutation específica o global | Toast con mensaje            |
| 409 Conflict              | Mutation específica          | Toast con mensaje de negocio |
| 500+ Server Error         | QueryClient global           | Toast genérico               |
| Network Error             | QueryClient global           | Toast + retry automático     |
| Error de rendering        | React ErrorBoundary          | Fallback UI + reset          |
| Error en Server Component | Next.js error.tsx            | Página de error              |

---

## Checklist de implementación

- [ ] Actualizar `HttpExceptionFilter` con códigos de error internos
- [ ] Actualizar `apiClient` con `ApiClientError` tipado
- [ ] Configurar `QueryClient` con `QueryCache` y `MutationCache`
- [ ] Crear `ErrorBoundary` y `QueryErrorBoundary`
- [ ] Agregar sistema de toasts (sonner, react-hot-toast, etc.)
- [ ] Crear `app/error.tsx` para Server Components
- [ ] Agregar códigos de error específicos del dominio según el proyecto
