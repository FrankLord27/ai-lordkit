# Quality Gate Checklist

El Quality Gate asegura que un módulo o bounded context está listo para avanzar a la siguiente etapa de desarrollo o producción. **Cada módulo tiene su propio Quality Gate.**

## Veredicto del Módulo
Al evaluar un módulo, se debe emitir un veredicto usando este formato:

```text
┌────────────────────────────────────────┐
│  QUALITY GATE — Módulo: [nombre]       │
├────────────────────────────────────────┤
│  Escenarios de negocio    [PASS/FAIL]  │
│  Reglas de negocio        [PASS/FAIL]  │
│  Cobertura de pruebas     [PASS/FAIL]  │
│  Arquitectura y Código    [PASS/FAIL]  │
│  Manejo de Datos/Prisma   [PASS/FAIL]  │
│                                        │
│  VEREDICTO: [DESBLOQUEADO / BLOQUEADO] │
└────────────────────────────────────────┘
```

## Tabla de Tracking Global
Mantener este registro actualizado conforme se aprueban los módulos. Un **Gate Global** se considera PASS solo cuando **todos los módulos del MVP** están DESBLOQUEADOS.

| Módulo | Gate | Estado | Fecha |
|---|---|---|---|
| `[Nombre]` | Escenarios | `[Pendiente]` | `[Fecha]` |
| `[Nombre]` | Implementación | `[Pendiente]` | `[Fecha]` |

---

## Criterios de Evaluación por Módulo

### 1. Requisitos y Escenarios
- [ ] ¿Existe una Matriz de Escenarios de Negocio documentada para el módulo?
- [ ] ¿Se han cubierto los Happy Paths, Failure Paths y Edge Cases?
- [ ] ¿La Matriz de Autorización está claramente definida?

### 2. Diseño de Dominio y Arquitectura (NestJS)
- [ ] **Aislamiento de Lógica:** Lógica de negocio reside enteramente en `services` o `use-cases`. **Nunca en `controllers`**.
- [ ] **Inyección de Dependencias:** Todos los servicios y repositorios están correctamente inyectados, facilitando el testing.
- [ ] **Estructura Modular:** El código sigue la convención `src/modules/<módulo>/(domain|application|presentation|infrastructure)`.

### 3. Persistencia y Prisma 7
- [ ] **Manejo de Dinero:** Si el módulo maneja dinero, usa el tipo Prisma `@db.Decimal` y la librería `decimal.js` (alineado a `erp-saas-core`). No usar float o enteros para dinero.
- [ ] **Multi-tenancy:** Todas las consultas Prisma (findMany, findUnique, update, etc.) aplican correctamente el filtro por `tenantId` (verificar skill `erp-saas-core`).
- [ ] **Integridad Relacional:** Las constraints de clave foránea y borrado en cascada (o restrict) están configuradas intencionalmente.
- [ ] **Concurrencia:** Se aplican estrategias de concurrencia optimista (`@updatedAt`, campos de versión) o bloqueos transaccionales donde aplica.

### 4. Testing
- [ ] **Unit Tests:** Pruebas unitarias completas para los servicios y use cases principales (`test/unit/<módulo>/*`).
- [ ] **Integration/E2E Tests:** Pruebas E2E que cubren los endpoints expuestos verificando persistencia y códigos HTTP reales (`test/e2e/<módulo>/*`).
- [ ] **Casos Extremos Probados:** Los edge cases y failure paths están explícitamente probados.

### 5. Seguridad y Rendimiento
- [ ] **Validación de Entradas:** DTOs con Zod (`createZodDto` de `nestjs-zod`) definidos en `packages/shared-types`. ValidationPipe global con `whitelist: true`.
- [ ] **Autorización:** Guards (`JwtAuthGuard`, `RolesGuard`) aplicados en los controladores correctos.
- [ ] **Manejo de Errores:** Errores de dominio mapeados a códigos HTTP adecuados vía Exception Filters de NestJS.
- [ ] **Idempotencia:** Endpoints que mutan estado financiero tienen `idempotencyKey`.
- [ ] **Observabilidad:** Logs estructurados (JSON), request ID propagado, audit log append-only.
