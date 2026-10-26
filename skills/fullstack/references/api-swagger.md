# Swagger y Documentación de la API

---

## Configuración completa en main.ts

```typescript
import { SwaggerModule, DocumentBuilder } from "@nestjs/swagger";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Solo en desarrollo y staging — nunca exponer en producción sin auth
  if (process.env.NODE_ENV !== "production") {
    const config = new DocumentBuilder()
      .setTitle("MyApp API")
      .setDescription(
        `
        API REST de MyApp.

        ## Autenticación
        La mayoría de endpoints requieren un Bearer Token JWT.
        Obtener el token con POST /auth/login y usarlo en el botón Authorize.

        ## Paginación
        Todos los endpoints de listado aceptan: page (default: 1), limit (default: 20, max: 100)

        ## Errores
        Todos los errores siguen el formato: { statusCode, error, message, timestamp, path }
      `,
      )
      .setVersion("1.0")
      .addBearerAuth(
        { type: "http", scheme: "bearer", bearerFormat: "JWT" },
        "access-token", // Nombre del esquema de auth
      )
      .addTag("auth", "Autenticación y gestión de sesión")
      .addTag("users", "Gestión de usuarios")
      .addTag("cars", "Catálogo de vehículos")
      .addTag("bookings", "Reservas")
      .build();

    const document = SwaggerModule.createDocument(app, config);
    SwaggerModule.setup("docs", app, document, {
      swaggerOptions: {
        persistAuthorization: true, // Mantiene el token entre recargas
        docExpansion: "none", // Colapsa los endpoints por defecto
        filter: true, // Buscador de endpoints
      },
    });
  }
}
```

---

## Decorar Controllers y DTOs

```typescript
// modules/bookings/bookings.controller.ts
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiParam,
  ApiQuery,
  ApiBody,
} from "@nestjs/swagger";

@ApiTags("bookings") // Agrupa el controller en Swagger
@ApiBearerAuth("access-token") // Todos los endpoints requieren JWT
@Controller("bookings")
export class BookingsController {
  @Get()
  @ApiOperation({
    summary: "Listar reservas",
    description: "Retorna las reservas del usuario autenticado con paginación.",
  })
  @ApiQuery({ name: "page", required: false, type: Number, example: 1 })
  @ApiQuery({ name: "limit", required: false, type: Number, example: 20 })
  @ApiQuery({
    name: "status",
    required: false,
    enum: BookingStatus,
    description: "Filtrar por estado de la reserva",
  })
  @ApiResponse({
    status: 200,
    description: "Lista de reservas",
    type: PaginatedBookingResponseDto,
  })
  @ApiResponse({ status: 401, description: "No autenticado" })
  findAll(@Query() query: FindBookingsDto) {}

  @Get(":id")
  @ApiOperation({ summary: "Obtener reserva por ID" })
  @ApiParam({
    name: "id",
    description: "UUID de la reserva",
    example: "550e8400-e29b-41d4-a716-446655440000",
  })
  @ApiResponse({
    status: 200,
    description: "Reserva encontrada",
    type: BookingResponseDto,
  })
  @ApiResponse({ status: 404, description: "Reserva no encontrada" })
  findOne(@Param("id") id: string) {}

  @Post()
  @ApiOperation({ summary: "Crear reserva" })
  @ApiBody({ type: CreateBookingDto })
  @ApiResponse({
    status: 201,
    description: "Reserva creada",
    type: BookingResponseDto,
  })
  @ApiResponse({ status: 400, description: "Datos inválidos" })
  @ApiResponse({ status: 409, description: "Fechas no disponibles" })
  create(@Body() dto: CreateBookingDto) {}

  @Post(":id/cancellation")
  @ApiOperation({ summary: "Cancelar reserva" })
  @ApiResponse({ status: 200, description: "Reserva cancelada" })
  @ApiResponse({
    status: 409,
    description: "La reserva no puede cancelarse (ya completada o cancelada)",
  })
  cancel(@Param("id") id: string, @Body() dto: CancelBookingDto) {}

  @Delete(":id")
  @HttpCode(204)
  @ApiOperation({ summary: "Eliminar reserva" })
  @ApiResponse({ status: 204, description: "Reserva eliminada" })
  @ApiResponse({
    status: 403,
    description: "Sin permiso para eliminar esta reserva",
  })
  remove(@Param("id") id: string) {}
}
```

---

## Documentar DTOs — properties y ejemplos

```typescript
// dto/create-booking.dto.ts
import { ApiProperty, ApiPropertyOptional } from "@nestjs/swagger";

export class CreateBookingDto {
  @ApiProperty({
    description: "UUID del vehículo a reservar",
    example: "550e8400-e29b-41d4-a716-446655440000",
  })
  @IsUUID()
  carId: string;

  @ApiProperty({
    description: "Fecha y hora de recogida en ISO 8601",
    example: "2025-06-01T10:00:00Z",
  })
  @IsISO8601()
  pickupDate: string;

  @ApiProperty({
    description: "Fecha y hora de devolución en ISO 8601",
    example: "2025-06-05T10:00:00Z",
  })
  @IsISO8601()
  returnDate: string;

  @ApiPropertyOptional({
    description: "Notas adicionales para la reserva",
    example: "Necesito silla para bebé",
    maxLength: 500,
  })
  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;
}

// dto/booking-response.dto.ts — lo que la API retorna
export class BookingResponseDto {
  @ApiProperty({ example: "550e8400-e29b-41d4-a716-446655440000" })
  id: string;

  @ApiProperty({ example: "2025-06-01T10:00:00.000Z" })
  pickupDate: string;

  @ApiProperty({ example: "2025-06-05T10:00:00.000Z" })
  returnDate: string;

  @ApiProperty({ enum: BookingStatus, example: BookingStatus.CONFIRMED })
  status: BookingStatus;

  @ApiProperty({ description: "Precio total en USD", example: 400.0 })
  totalPrice: number;

  @ApiProperty({ type: CarSummaryDto })
  car: CarSummaryDto;
}
```

---

## Documentar endpoints públicos vs privados

```typescript
// Endpoint público — sin @ApiBearerAuth
@Get('featured')
@ApiOperation({ summary: 'Obtener autos destacados (público)' })
async getFeatured() {}

// Endpoint privado — con @ApiBearerAuth en el controller o en el método
@Get('my-bookings')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard)
@ApiOperation({ summary: 'Mis reservas (requiere autenticación)' })
async getMyBookings() {}

// Endpoint de admin — documentar el rol requerido
@Delete(':id')
@ApiBearerAuth('access-token')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(Role.ADMIN)
@ApiOperation({
  summary: 'Eliminar usuario (solo ADMIN)',
  description: 'Requiere rol ADMIN. Elimina permanentemente el usuario y todos sus datos.',
})
async deleteUser() {}
```

---

## Swagger en producción — acceso restringido

```typescript
// Si necesitas Swagger en producción, protegerlo con autenticación básica
import * as basicAuth from "express-basic-auth";

// Antes del setup de Swagger
app.use(
  "/docs",
  basicAuth({
    users: { [process.env.SWAGGER_USER]: process.env.SWAGGER_PASSWORD },
    challenge: true,
  }),
);

SwaggerModule.setup("docs", app, document);
```
