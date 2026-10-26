# Contratos de Request y Response

---

## Formato de respuesta estándar

Toda la API usa el mismo envoltorio. El cliente sabe siempre qué esperar.

```typescript
// ✅ Respuesta exitosa — envuelta en { data }
// TransformInterceptor en main.ts lo hace automáticamente
{
  "data": {
    "id": "uuid-123",
    "model": "Corolla",
    "brand": "Toyota",
    "dailyRate": 80.00
  }
}

// ✅ Listado paginado
{
  "data": {
    "items": [...],
    "pagination": {
      "total": 243,
      "page": 2,
      "limit": 20,
      "totalPages": 13,
      "hasNextPage": true,
      "hasPreviousPage": true
    }
  }
}

// ✅ Error — siempre el mismo formato
{
  "statusCode": 404,
  "error": "NOT_FOUND",
  "message": "Booking no encontrado",
  "timestamp": "2025-03-20T14:30:00.000Z",
  "path": "/api/v1/bookings/uuid-inexistente"
}
```

---

## TransformInterceptor — envolver respuestas en { data }

```typescript
// common/interceptors/transform.interceptor.ts
import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
} from "@nestjs/common";
import { Observable } from "rxjs";
import { map } from "rxjs/operators";

export interface ApiResponse<T> {
  data: T;
}

@Injectable()
export class TransformInterceptor<T> implements NestInterceptor<
  T,
  ApiResponse<T>
> {
  intercept(
    context: ExecutionContext,
    next: CallHandler,
  ): Observable<ApiResponse<T>> {
    return next.handle().pipe(map((data) => ({ data })));
  }
}
```

---

## Paginación — implementación completa

```typescript
// common/dto/pagination.dto.ts — reutilizar en cualquier módulo
import { IsInt, IsOptional, Max, Min } from "class-validator";
import { Type } from "class-transformer";
import { ApiPropertyOptional } from "@nestjs/swagger";

export class PaginationDto {
  @ApiPropertyOptional({ default: 1, minimum: 1 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Type(() => Number)
  page?: number = 1;

  @ApiPropertyOptional({ default: 20, minimum: 1, maximum: 100 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  @Type(() => Number)
  limit?: number = 20;
}

// common/dto/paginated-response.dto.ts — response de listados
export class PaginationMeta {
  total: number;
  page: number;
  limit: number;
  totalPages: number;
  hasNextPage: boolean;
  hasPreviousPage: boolean;
}

export class PaginatedResponseDto<T> {
  items: T[];
  pagination: PaginationMeta;

  static of<T>(
    items: T[],
    total: number,
    { page, limit }: PaginationDto,
  ): PaginatedResponseDto<T> {
    const totalPages = Math.ceil(total / limit);
    return {
      items,
      pagination: {
        total,
        page,
        limit,
        totalPages,
        hasNextPage: page < totalPages,
        hasPreviousPage: page > 1,
      },
    };
  }
}
```

```typescript
// Uso en el Service
async findAll(dto: FindCarsDto): Promise<PaginatedResponseDto<CarResponseDto>> {
  const { page, limit, status, sort } = dto;
  const skip = (page - 1) * limit;

  const orderBy = this.parseSort(sort); // { price: 'asc' } o { createdAt: 'desc' }

  const [cars, total] = await Promise.all([
    this.prisma.car.findMany({
      where: { status },
      orderBy,
      skip,
      take: limit,
    }),
    this.prisma.car.count({ where: { status } }),
  ]);

  return PaginatedResponseDto.of(
    cars.map(CarMapper.toDto),
    total,
    dto,
  );
}

private parseSort(sort?: string): Prisma.CarOrderByWithRelationInput {
  if (!sort) return { createdAt: 'desc' }; // Default

  const descending = sort.startsWith('-');
  const field = descending ? sort.slice(1) : sort;
  return { [field]: descending ? 'desc' : 'asc' };
}
```

---

## Manejo de errores consistente

```typescript
// common/filters/http-exception.filter.ts
// Un solo filter maneja TODOS los errores de la API

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request>();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    // Extraer mensaje — HttpException puede tener objeto o string
    const exceptionResponse =
      exception instanceof HttpException ? exception.getResponse() : null;

    const message =
      typeof exceptionResponse === "object"
        ? (exceptionResponse as any).message
        : (exceptionResponse ?? "Error interno del servidor");

    // Loguear 5xx — los 4xx son errores del cliente, no del sistema
    if (status >= 500) {
      this.logger.error(`${req.method} ${req.url}`, exception);
    }

    // Formato de error uniforme
    res.status(status).json({
      statusCode: status,
      error: HttpStatus[status],
      // Aplanar arrays de errores de validación
      message: Array.isArray(message) ? message[0] : message,
      // En desarrollo: mostrar todos los errores de validación
      ...(process.env.NODE_ENV === "development" && Array.isArray(message)
        ? { errors: message }
        : {}),
      timestamp: new Date().toISOString(),
      path: req.url,
    });
  }
}
```

### Errores de validación — formato detallado en desarrollo

```typescript
// ValidationPipe genera mensajes como:
// ["name must be a string", "price must be a positive number"]

// En producción: mostrar solo el primer error (no revelar demasiado)
// En desarrollo: mostrar todos para facilitar el debug

// Configuración del ValidationPipe en main.ts:
app.useGlobalPipes(
  new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
    exceptionFactory: (errors) => {
      const messages = errors.map((e) =>
        Object.values(e.constraints ?? {}).join(", "),
      );
      return new BadRequestException(messages);
    },
  }),
);
```

---

## Campos de respuesta — convenciones de nombres

```typescript
// ✅ camelCase en JSON — estándar para APIs JSON
{
  "id": "uuid-123",
  "dailyRate": 80.00,       // camelCase
  "pickupDate": "2025-03-20T10:00:00Z",  // ISO 8601 para fechas
  "totalPrice": 400.00,     // Siempre number, no string
  "isAvailable": true,      // Booleanos con prefijo is/has/can
  "createdAt": "2025-01-15T12:00:00Z",
  "updatedAt": "2025-02-10T08:30:00Z"
}

// ❌ Inconsistencias comunes
{
  "daily_rate": 80,          // snake_case — usar solo si toda la API es snake_case
  "pickup_date": "20/03/25", // Formato de fecha no estándar
  "total": "400.00",         // Precio como string
  "available": 1,            // Booleano como número
  "created": "Jan 15"        // Fecha no ISO 8601
}
```

### Tipos de datos en respuestas

```typescript
// Dinero: siempre number con 2 decimales
"price": 80.00    // ✅
"price": "80.00"  // ❌ String

// Fechas: siempre ISO 8601 en UTC
"createdAt": "2025-03-20T14:30:00.000Z"  // ✅
"createdAt": "20/03/2025"                 // ❌

// IDs: siempre string (UUID)
"id": "550e8400-e29b-41d4-a716-446655440000"  // ✅
"id": 123                                      // ❌ Número como ID

// Booleanos: true/false, nunca 0/1
"isActive": true   // ✅
"active": 1        // ❌

// Arrays vacíos: [], nunca null
"images": []   // ✅
"images": null // ❌
```

---

## Headers importantes en responses

```typescript
// Location — al crear un recurso (201)
res.setHeader("Location", `/api/v1/bookings/${booking.id}`);

// X-Total-Count — número total de registros en listados
// Útil cuando el cliente necesita el total sin el body completo
res.setHeader("X-Total-Count", total.toString());

// ETag — para cache condicional
res.setHeader("ETag", `"${hash(resource)}"`);

// Cache-Control — controlar cache del browser y CDN
res.setHeader("Cache-Control", "public, max-age=300"); // 5 min para datos públicos
res.setHeader("Cache-Control", "no-store"); // Sin cache para datos privados
```
