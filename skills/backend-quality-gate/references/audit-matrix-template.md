# Plantilla: Matriz de Auditoría (NestJS + Prisma 7)

Esta matriz proporciona el detalle táctico para evaluar el código de un módulo durante su Quality Gate.

## Objetivo
Detectar discrepancias arquitectónicas, errores de integridad de datos y vulnerabilidades comunes en un stack NestJS + Prisma 7 + PostgreSQL.

---

## Dimensiones de Auditoría

### 1. Arquitectura NestJS y Lógica de Dominio
**Regla:** Cero lógica de negocio en controladores.
**Cómo verificar:**
- Inspeccionar `src/modules/<módulo>/presentation/controllers/*.controller.ts`.
- Si hay más de 3 líneas de código dentro de un método de controlador (ej. cálculos, asignaciones condicionales, loops), es un **Fail**.
- Todo controlador debe limitarse a recibir el request, llamar a un Use Case/Service, y retornar la respuesta.

### 2. Integridad de Datos e Integración Prisma 7
**Regla:** Restricciones de base de datos robustas y uso seguro de Prisma.
**Cómo verificar:**
- Revisar `prisma/schema.prisma`. Verificar índices (`@@index`), unicidad (`@@unique`), y restricciones correctas.
- Buscar llamadas a la base de datos sin límites. Ejecutar: `grep -r "findMany(" src/modules/<módulo>` y verificar que tengan soporte para paginación (`take`, `skip`, o cursores).
- Migraciones: Asegurar que los cambios de esquema hayan generado una migración en `prisma/migrations` y que no haya pérdida de datos destructiva sin plan de mitigación.

### 3. Aislamiento Multi-Tenant (Cross-reference: `erp-saas-core`)
**Regla:** Ninguna consulta debe filtrar o devolver datos del tenant equivocado.
**Cómo verificar:**
- Ejecutar: `grep -r "findMany" src/ | grep -v "tenantId"`. Investigar si alguna consulta carece del filtro `where: { tenantId }`.
- Asegurar que la creación de entidades asigne correctamente el `tenantId` desde el contexto del usuario autenticado (extraído del JWT).

### 4. Precisión Financiera (Cross-reference: `erp-saas-core`)
**Regla:** Representación exacta de valores monetarios.
**Cómo verificar:**
- Si el módulo toca dinero (facturación, pagos, precios), revisar `schema.prisma`. Asegurar el uso de `Decimal @db.Decimal(10,2)` u otra precisión definida, NUNCA `Float`.
- Buscar en el código TypeScript el uso de tipo numérico primitivo para el dinero. Todo cálculo debe usar `decimal.js`.

### 5. Control de Acceso y Autorización
**Regla:** Endpoints protegidos correctamente.
**Cómo verificar:**
- Revisar Controladores: Verificar que tengan decoradores de Guards (`@UseGuards(JwtAuthGuard)`) o equivalentes.
- Para endpoints que modifican recursos de otros usuarios/tenants, verificar que el servicio subyacente confirme la propiedad del recurso.

### 6. Manejo de Transacciones
**Regla:** Operaciones multi-paso garantizan atomicidad.
**Cómo verificar:**
- Buscar escrituras múltiples relacionadas (ej. crear Factura + reducir Stock).
- Ejecutar: `grep -r "prisma\." src/modules/<módulo>` buscando patrones secuenciales sin `$transaction`.
- Exigir el uso de `this.prisma.$transaction(async (tx) => { ... })` para estas operaciones.

---

## Ejecución de Auditoría
Rellena la siguiente tabla durante la revisión de un módulo:

| Dimensión | Archivos Revisados | Hallazgos | Acción Requerida | Estado |
|---|---|---|---|---|
| Arquitectura | `[archivos]` | `[descripción]` | `[Fix...]` | `[PASS/FAIL]` |
| Integridad Prisma | `[archivos]` | `[descripción]` | `[Fix...]` | `[PASS/FAIL]` |
| Multi-tenant | `[archivos]` | `[descripción]` | `[Fix...]` | `[PASS/FAIL]` |
| Precisión Financiera | `[archivos]` | `[descripción]` | `[Fix...]` | `[PASS/FAIL]` |
| Autorización | `[archivos]` | `[descripción]` | `[Fix...]` | `[PASS/FAIL]` |
| Transacciones | `[archivos]` | `[descripción]` | `[Fix...]` | `[PASS/FAIL]` |
