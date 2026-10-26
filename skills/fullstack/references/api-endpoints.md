# Convenciones de Endpoints REST

---

## Nomenclatura de URLs

```
✅ Correcto                          ❌ Incorrecto
─────────────────────────────────    ─────────────────────────────────
/api/v1/users                        /api/v1/User
/api/v1/rental-cars                  /api/v1/rentalCars
/api/v1/bookings                     /api/v1/rental_cars
/api/v1/bookings/123                 /api/v1/getBookings
/api/v1/users/123/bookings           /api/v1/booking_list
```

**Reglas de nomenclatura:**

- Siempre **plural**: `/users`, no `/user`
- Siempre **kebab-case**: `/rental-cars`, no `/rentalCars` ni `/rental_cars`
- Siempre **minúsculas**: `/bookings`, no `/Bookings`
- Sustantivos, no verbos: `/bookings`, no `/getBookings`
- IDs como segmento: `/bookings/123`, no `/bookings?id=123`

---

## Verbos HTTP — cuándo usar cada uno

| Verbo    | Uso                           | Idempotente | Body |
| -------- | ----------------------------- | ----------- | ---- |
| `GET`    | Obtener recurso(s)            | Sí          | No   |
| `POST`   | Crear recurso                 | No          | Sí   |
| `PUT`    | Reemplazar recurso completo   | Sí          | Sí   |
| `PATCH`  | Actualizar campos específicos | No          | Sí   |
| `DELETE` | Eliminar recurso              | Sí          | Raro |

```typescript
// Mapeo completo de CRUD a HTTP

@Controller("bookings")
export class BookingsController {
  @Get() // GET /bookings — listado con paginación y filtros
  findAll(@Query() query: FindBookingsDto) {}

  @Get(":id") // GET /bookings/123 — obtener uno
  findOne(@Param("id") id: string) {}

  @Post() // POST /bookings — crear
  create(@Body() dto: CreateBookingDto) {}

  @Patch(":id") // PATCH /bookings/123 — actualizar campos
  update(@Param("id") id: string, @Body() dto: UpdateBookingDto) {}

  @Put(":id") // PUT /bookings/123 — reemplazar todo
  replace(@Param("id") id: string, @Body() dto: ReplaceBookingDto) {}

  @Delete(":id") // DELETE /bookings/123 — eliminar
  remove(@Param("id") id: string) {}
}

// ¿PATCH o PUT?
// PATCH → actualizar campos específicos (lo más común)
//   Body: { status: 'CANCELLED' }  ← solo los campos que cambian
// PUT → reemplazar el recurso completo (menos común)
//   Body: { ...todos los campos del recurso... }
```

---

## Jerarquía de recursos — relaciones

```typescript
// Recurso anidado — cuando siempre necesitas el padre para acceder al hijo
// El booking siempre pertenece a un user
GET / users / 123 / bookings; // Bookings del usuario 123
GET / users / 123 / bookings / 456; // Booking específico del usuario 123
POST / users / 123 / bookings; // Crear booking para usuario 123

// ⚠️ Cuidado con el anidamiento profundo — máximo 2 niveles
// ✅ /users/123/bookings
// ❌ /users/123/bookings/456/payments/789/receipts  ← Demasiado profundo

// Recurso independiente — cuando se accede directamente por ID
// Un booking puede obtenerse directamente si conoces su ID
GET / bookings / 456; // ← También válido para acceso directo

// La regla práctica:
// Si necesitas el contexto del padre para encontrar al hijo → anidado
// Si el recurso tiene su propio ID único global → también exponer raíz
```

---

## Acciones que no son CRUD

A veces una acción no encaja en el CRUD estándar.
Usar un sub-recurso que represente el estado o la acción.

```typescript
// ✅ Acciones como sub-recursos — expresan cambio de estado
POST /bookings/123/confirmation    // Confirmar una reserva
POST /bookings/123/cancellation    // Cancelar una reserva
POST /bookings/123/extension       // Extender fechas
POST /payments/123/refund          // Procesar reembolso
POST /users/123/password-reset     // Solicitar reset de password
POST /users/123/email-verification // Reenviar verificación

// ✅ Alternativa con PATCH — cambio de estado explícito
PATCH /bookings/123
Body: { "status": "CONFIRMED" }

// ❌ Verbos en la URL
POST /bookings/123/confirm         // 'confirm' es un verbo
POST /cancelBooking/123            // Verbo en la raíz
GET  /bookings/getActive           // Usar GET /bookings?status=ACTIVE
```

```typescript
// NestJS — implementar acciones especiales
@Controller("bookings")
export class BookingsController {
  @Post(":id/confirmation")
  async confirm(@Param("id") id: string, @CurrentUser() user: UserPayload) {
    return this.bookingsService.confirm(id, user.sub);
  }

  @Post(":id/cancellation")
  async cancel(
    @Param("id") id: string,
    @Body() dto: CancelBookingDto,
    @CurrentUser() user: UserPayload,
  ) {
    return this.bookingsService.cancel(id, dto.reason, user.sub);
  }
}
```

---

## Query parameters — filtros, ordenamiento y búsqueda

```typescript
// Convenciones de query params
GET /cars?status=AVAILABLE              // Filtro por campo
GET /cars?status=AVAILABLE&category=SUV // Múltiples filtros (AND implícito)
GET /cars?category=SUV,ECONOMY          // Múltiples valores (OR implícito)
GET /cars?minPrice=50&maxPrice=200       // Rango
GET /cars?q=toyota                      // Búsqueda de texto
GET /cars?sort=price                    // Ordenar ascendente
GET /cars?sort=-price                   // Ordenar descendente (prefijo -)
GET /cars?sort=-createdAt,price         // Múltiples criterios
GET /cars?page=2&limit=20              // Paginación offset
GET /cars?cursor=abc123&limit=20        // Paginación cursor
GET /cars?fields=id,model,price         // Proyección de campos (avanzado)
```

```typescript
// DTO de query params estándar
export class FindCarsDto {
  // Paginación
  @IsOptional()
  @IsInt()
  @Min(1)
  @Type(() => Number)
  page?: number = 1;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  @Type(() => Number)
  limit?: number = 20;

  // Filtros
  @IsOptional()
  @IsEnum(CarStatus)
  status?: CarStatus;

  @IsOptional()
  @IsEnum(CarCategory)
  category?: CarCategory;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  minPrice?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Type(() => Number)
  maxPrice?: number;

  // Búsqueda de texto
  @IsOptional()
  @IsString()
  @MaxLength(100)
  q?: string;

  // Ordenamiento — validar que sea un campo válido
  @IsOptional()
  @Matches(/^-?(id|price|createdAt|model)$/, {
    message:
      "sort debe ser: id, price, createdAt, model (con - para descendente)",
  })
  sort?: string;
}
```

---

## Códigos de estado HTTP — cuándo usar cada uno

```typescript
// 2xx — Éxito
200 OK              // GET exitoso, PATCH/PUT exitoso con body de respuesta
201 Created         // POST exitoso — incluir Location header con URL del recurso
204 No Content      // DELETE exitoso, PATCH sin respuesta de body

// 3xx — Redirección
301 Moved Permanently  // El recurso cambió de URL permanentemente
304 Not Modified       // Cache válido — usar con ETag/Last-Modified

// 4xx — Error del cliente
400 Bad Request     // Datos inválidos, validación fallida
401 Unauthorized    // No autenticado (sin token o token inválido)
403 Forbidden       // Autenticado pero sin permiso para este recurso
404 Not Found       // Recurso no existe
409 Conflict        // Conflicto de estado (email ya registrado, reserva solapada)
410 Gone            // Recurso existió pero fue eliminado permanentemente
422 Unprocessable   // Datos válidos en formato pero semánticamente incorrectos
429 Too Many Req.   // Rate limit excedido

// 5xx — Error del servidor
500 Internal Error  // Error no manejado — nunca debería llegar al cliente
503 Unavailable     // Servicio caído (health check falla)
```

```typescript
// NestJS — usar las excepciones correctas
throw new BadRequestException('El email ya está registrado');      // 400
throw new UnauthorizedException('Token inválido o expirado');     // 401
throw new ForbiddenException('No tienes acceso a este recurso');  // 403
throw new NotFoundException('Booking no encontrado');             // 404
throw new ConflictException('Ya existe una reserva en esas fechas'); // 409
throw new UnprocessableEntityException('La fecha de retorno debe ser posterior a la de recogida'); // 422
throw new TooManyRequestsException('Demasiados intentos, espera 15 minutos'); // 429

// POST exitoso — 201 con Location header
@Post()
@HttpCode(201)
async create(
  @Body() dto: CreateBookingDto,
  @Res({ passthrough: true }) res: Response,
) {
  const booking = await this.bookingsService.create(dto);
  res.setHeader('Location', `/api/v1/bookings/${booking.id}`);
  return booking;
}

// DELETE exitoso — 204 sin body
@Delete(':id')
@HttpCode(204)
async remove(@Param('id') id: string) {
  await this.bookingsService.delete(id);
  // No retornar nada — 204 No Content
}
```
