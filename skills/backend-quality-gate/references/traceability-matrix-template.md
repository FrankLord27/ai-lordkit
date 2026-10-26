# Plantilla: Matriz de Trazabilidad

La matriz de trazabilidad asegura que cada requerimiento o escenario de negocio se ha mapeado a un componente de código específico y a una prueba automatizada correspondiente.

Se recomienda construir y actualizar esta tabla a nivel de módulo a medida que avanza la implementación.

## Matriz de Cobertura

| Módulo | ID de Escenario | Escenario / Regla | Ubicación del Código (NestJS) | Ubicación del Test | Estado |
|---|---|---|---|---|---|
| `[Módulo]` | `[ID]` | `[Descripción breve]` | `[Rutas a use-cases/services]` | `[Rutas a test files]` | `[Implementado/Pendiente]` |

---

## Ejemplo Llenado (Módulo de Ventas / Sales)

| Módulo | ID de Escenario | Escenario / Regla | Ubicación del Código (NestJS) | Ubicación del Test | Estado |
|---|---|---|---|---|---|
| SALES | BSM-SALES-001 | Crear venta con ítems válidos (Happy Path) | `src/modules/sales/application/use-cases/create-sale.use-case.ts` <br> `src/modules/sales/presentation/controllers/sale.controller.ts` | `test/unit/sales/create-sale.use-case.spec.ts` <br> `test/e2e/sales/create-sale.e2e-spec.ts` | Implementado |
| SALES | BSM-SALES-002 | Venta falla por stock insuficiente | `src/modules/inventory/application/services/stock-check.service.ts` <br> `src/modules/sales/application/use-cases/create-sale.use-case.ts` | `test/unit/sales/create-sale.use-case.spec.ts` (línea ~45) | Implementado |
| SALES | BSM-SALES-003 | La venta bloquea el inventario temporalmente (Transacción) | `src/modules/sales/infrastructure/repositories/sale.prisma.repository.ts` (uso de `$transaction`) | `test/integration/sales/sale-transaction.spec.ts` | Pendiente |
| SALES | BSM-SALES-004 | Validación de payload de entrada | `src/modules/sales/presentation/dto/create-sale.dto.ts` | `test/e2e/sales/sale-validation.e2e-spec.ts` | Implementado |

---

## Guía de Ubicaciones NestJS

Asegúrate de que las rutas reflejen correctamente la arquitectura propuesta para NestJS:

**Para Código:**
- **Casos de Uso / Servicios:** `src/modules/<módulo>/application/use-cases/...` o `src/modules/<módulo>/application/services/...`
- **Controladores:** `src/modules/<módulo>/presentation/controllers/...`
- **DTOs:** `src/modules/<módulo>/presentation/dto/...`
- **Dominio / Entidades:** `src/modules/<módulo>/domain/entities/...`
- **Repositorios / Prisma:** `src/modules/<módulo>/infrastructure/repositories/...`

**Para Pruebas:**
- **Unit Tests:** `test/unit/<módulo>/...` (para probar la lógica de dominio o use-cases con dependencias mockeadas)
- **Integration Tests:** `test/integration/<módulo>/...` (para probar repositorios y consultas Prisma a la DB)
- **E2E Tests:** `test/e2e/<módulo>/...` (para probar desde el request HTTP al controlador hasta la base de datos)
