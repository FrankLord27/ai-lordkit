# Versionado y Evolución de la API

---

## Por qué versionar desde el día 1

```
Sin versionar:   /api/bookings
Con versionar:   /api/v1/bookings

Cuando necesitas cambiar el contrato de la API:
Sin versionar → rompes todos los clientes existentes
Con versionar → creas /api/v2/bookings, los clientes migran a su ritmo
```

**Regla:** Siempre `/api/v1/` desde el primer endpoint. Cambiarlo después
es un breaking change que afecta a todos los integrantes.

---

## Estrategia de versionado en NestJS

```typescript
// main.ts — versionado por URL (el más claro y común)
import { VersioningType } from "@nestjs/common";

app.enableVersioning({
  type: VersioningType.URI, // /api/v1/... , /api/v2/...
  prefix: "v",
  defaultVersion: "1",
});

app.setGlobalPrefix("api");
```

```typescript
// Controller versionado
@Controller({ path: "bookings", version: "1" })
export class BookingsV1Controller {
  @Get()
  findAll() {
    /* implementación v1 */
  }
}

@Controller({ path: "bookings", version: "2" })
export class BookingsV2Controller {
  @Get()
  findAll() {
    /* implementación v2 con nuevo contrato */
  }
}

// Ambos coexisten:
// GET /api/v1/bookings → BookingsV1Controller
// GET /api/v2/bookings → BookingsV2Controller
```

---

## Breaking vs Non-Breaking Changes

### Cambios seguros — no requieren nueva versión

```typescript
// ✅ Agregar campo opcional al response
// Antes:
{ "id": "123", "status": "CONFIRMED" }
// Después — el cliente ignora los campos que no conoce:
{ "id": "123", "status": "CONFIRMED", "confirmationCode": "ABC123" }

// ✅ Agregar endpoint nuevo
GET /api/v1/bookings/123/invoice   // Nuevo — no afecta endpoints existentes

// ✅ Agregar query param opcional
GET /api/v1/bookings?includeArchived=true  // Parámetro nuevo, opcional, con default

// ✅ Hacer campo requerido → opcional
// Si antes era requerido y ahora es opcional, los clientes que lo enviaban
// siguen funcionando

// ✅ Agregar valores nuevos a un enum
// (Con cuidado — el cliente puede no manejar el nuevo valor)
BookingStatus: 'CONFIRMED' | 'CANCELLED' | 'COMPLETED' | 'ARCHIVED' // Agregar ARCHIVED
```

### Cambios que rompen — requieren nueva versión

```typescript
// ❌ Eliminar campo del response
// Antes: { "id": "123", "carModel": "Corolla" }
// Después: { "id": "123" }   ← El cliente que usaba carModel rompe

// ❌ Renombrar campo
// Antes: { "pickupDate": "2025-03-20" }
// Después: { "startDate": "2025-03-20" }   ← Rompe el cliente

// ❌ Cambiar tipo de dato
// Antes: { "price": 80.00 }        // number
// Después: { "price": "80.00" }    // string

// ❌ Cambiar semántica de un campo
// Antes: status=CANCELLED significa cancelado por el usuario
// Después: status=CANCELLED significa cancelado por cualquiera
// Aunque el campo existe, su significado cambió

// ❌ Hacer campo opcional → requerido
// Los clientes que no lo enviaban rompen

// ❌ Eliminar endpoint o cambiar su URL
// ❌ Cambiar el verbo HTTP de un endpoint
```

---

## Proceso de deprecación

```typescript
// Cuando un endpoint va a desaparecer:
// 1. Anunciarlo con headers Deprecation y Sunset
// 2. Mantenerlo funcional durante el período de deprecación
// 3. Eliminarlo después de la fecha Sunset

@Get('old-search')
@Header('Deprecation', 'true')
@Header('Sunset', 'Sat, 31 Dec 2025 23:59:59 GMT')
@Header('Link', '</api/v2/cars/search>; rel="successor-version"')
@ApiOperation({
  deprecated: true,
  summary: '[DEPRECADO] Buscar autos — usar GET /api/v2/cars/search',
  description: 'Este endpoint será eliminado el 31/12/2025. Migrar a v2.',
})
async oldSearch(@Query() dto: OldSearchDto) {
  // Loguear uso para saber cuántos clientes siguen usando el endpoint deprecado
  this.logger.warn(`Endpoint deprecado usado: GET /api/v1/old-search from ${request.ip}`);
  return this.carsService.search(dto);
}
```

---

## Changelog de la API — documentar cambios

```markdown
# API Changelog

## v2.0.0 (2025-06-01)

### Breaking Changes

- `GET /bookings` ahora retorna `items` en lugar de `data` dentro del objeto de paginación
- Campo `carModel` eliminado de BookingResponse — usar `car.model`
- `POST /bookings` ahora requiere `locationId` obligatorio

### New Features

- Nuevo endpoint `POST /bookings/:id/extension` para extender fechas
- Soporte de cursor pagination en `GET /cars`

## v1.5.0 (2025-03-01)

### Non-Breaking Changes

- Nuevo campo opcional `confirmationCode` en BookingResponse
- Nuevo query param `includeArchived` en `GET /bookings`
- Nuevo endpoint `GET /cars/:id/availability`

## v1.0.0 (2025-01-01)

- Release inicial
```

---

## Múltiples clientes — cómo comunicar cambios

```typescript
// Si la API tiene múltiples consumidores (app móvil, web, terceros):

// 1. Versionar siempre
// 2. Nunca hacer breaking changes sin incrementar la versión mayor
// 3. Mantener versiones anteriores durante el tiempo de migración acordado
//    → Mínimo 3 meses para APIs internas
//    → Mínimo 6-12 meses para APIs públicas con terceros
// 4. Header Sunset con fecha exacta de eliminación
// 5. Loguear uso de endpoints deprecados — saber cuándo dejar de darles soporte
// 6. Notificar activamente a los consumidores por email o changelog
```
