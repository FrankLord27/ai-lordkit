# 11 — Flujo de Trabajo con IA

## Principio rector

> La IA no debe perder el contexto, no debe romper las reglas del dominio, y no debe escribir código sin un plan aprobado.

Para lograrlo, tres mecanismos:

1. **Skill `erp-saas-core`** = reglas inmutables (este conjunto de archivos).
2. **Skill `memory-bank-context`** = estado vivo del proyecto.
3. **Protocolo de fragmentación por capa** = pedir a la IA una capa a la vez.

---

## Flujo estándar (5 pasos)

```
1. CONTEXTO   → "Leé erp-saas-core + memory-bank-context"
2. PLAN       → IA propone pasos + archivos a tocar. NO escribe código.
3. APROBACIÓN → Vos confirmás o ajustás.
4. EJECUCIÓN  → IA implementa una capa a la vez (Domain → App → Infra → Pres)
5. CIERRE     → Actualizar activeContext.md + progress.md
```

---

## Prompt maestro: arranque de sesión

Copiá esto al inicio de CADA sesión con cualquier agente (Claude, Cursor, Cline, OpenCode):

```
Antes de cualquier acción:

1. Leé el SKILL.md de `erp-saas-core` y los references relevantes según mi tarea.
2. Leé `memory-bank-context/` completo: projectbrief, productContext, systemPatterns,
   techContext, activeContext, progress.
3. Confirmá que entendiste:
   - El stack (NestJS 11, Prisma 7, PostgreSQL 16+, Next.js 15+, TanStack Query 5, Zustand 5)
   - Las 11 reglas inmutables (multi-tenant, soft delete, Decimal, partida doble, etc.)
   - El estado actual del proyecto (qué se hizo, qué falta)
4. NO escribas código todavía. Esperá mi instrucción.

Mi tarea de hoy: [describir tarea concreta]
```

---

## Prompt: pedir un plan (no código)

```
Para esta tarea, dame:

1. LISTA DE ARCHIVOS a crear / modificar (rutas completas).
2. ORDEN de ejecución por capa: Domain → Application → Infrastructure → Presentation.
3. CASOS DE TEST que deberíamos escribir primero (nombre + qué prueban).
4. RIESGOS o decisiones arquitectónicas que requieran mi aprobación.
5. MIGRACIONES de schema necesarias (Prisma).
6. SKILLS adicionales que vas a consultar.

No escribas código todavía. Solo el plan.
```

---

## Prompt: ejecutar una capa específica

```
Implementá SOLO la capa de [Domain / Application / Infrastructure / Presentation]
para [feature].

Reglas estrictas:
1. Cero `any`, cero `ts-ignore`, cero casteos inseguros.
2. Dinero en `Decimal` (importado desde `@/shared/kernel/decimal.config`).
3. Imports respetan la dirección de Clean Architecture.
4. Si es Domain, NO importes NestJS, Prisma, ni nada externo.
5. Si es Infrastructure, implementá las interfaces del Domain.
6. Cada archivo nuevo en la ubicación canónica (ver erp-saas-core).
7. Devolvé los tests que escribirías para cubrir esta capa.

NO toques otras capas. NO modifiques tests existentes.
```

---

## Prompt: AI-TDD estricto

```
Aquí están los tests:

[pegar tests]

Implementá el código de producción para que pasen TODOS los tests.

Reglas inviolables:
1. NO modifiques los tests. Si pensás que un test está mal, decímelo en lenguaje natural ANTES de tocar nada.
2. NO uses any, ts-ignore, ni casteos `as Tipo`.
3. Devolveme SOLO el archivo de implementación. Cero explicaciones.
4. Si necesitás un archivo auxiliar (ej. un error de dominio), creálo en su carpeta canónica.
```

---

## Prompt: code review

```
Revisá este código contra las 11 reglas inmutables de erp-saas-core:

[pegar código]

Para cada regla, decime PASA / FALLA y por qué. Si FALLA, mostrame el fix
exacto. No reescribas todo el archivo: solo los diffs necesarios.
```

---

## Prompt: cierre de sesión (actualizar Memory Bank)

```
Vamos a actualizar el Memory Bank antes de cerrar.

1. activeContext.md → ¿en qué estamos AHORA? archivos tocados, decisiones pendientes.
2. progress.md      → marcar tareas completadas, agregar nuevas que surgieron.
3. systemPatterns.md → ¿descubrimos algún patrón nuevo que el equipo deba seguir?
4. techContext.md    → ¿agregamos / quitamos dependencias?

Releé los archivos actuales antes de proponer cambios. Mostrame el diff propuesto
de cada archivo y esperá mi confirmación antes de aplicar.
```

---

## Antipatrones en el prompting (cosas a NO hacer)

| Antipatrón                                      | Por qué falla                                         | Reemplazo                                       |
| ----------------------------------------------- | ----------------------------------------------------- | ----------------------------------------------- |
| "Implementá el módulo completo de contabilidad" | La IA mezcla capas, olvida tenantId, alucina patrones | Pedir una capa a la vez                         |
| "Hacé los cambios que creas necesarios"         | La IA reescribe medio proyecto                        | Especificar archivos exactos                    |
| "Olvidá lo anterior y empezá de cero"           | Pierde contexto valioso                               | Actualizar Memory Bank explícitamente           |
| Adjuntar 30 archivos al prompt                  | Lost in the middle                                    | Solo lo que toca + interfaces relacionadas      |
| "Esto debería funcionar igual"                  | La IA inventa equivalencias falsas                    | Tests primero, código después                   |
| Pegar errores sin contexto                      | La IA adivina                                         | Pegar error + archivo afectado + qué intentabas |
| "Refactorizá esto pero no rompas nada"          | Garantizado: rompe algo                               | Tests cubriendo lo actual ANTES de refactor     |
| Aceptar `any` "temporal"                        | Nunca se elimina                                      | Rechazar el código, pedir el tipo correcto      |

---

## Cómo manejar errores

Cuando un test falla o el código revienta:

```
El test [nombre del test] falla con este output:

[pegar stack trace completo, NO resumir]

Archivo afectado: [ruta]
Qué intentaba hacer: [una frase]

Diagnosticá. Si necesitás ver otro archivo, decímelo. NO modifiques el test.
```

---

## Cuando la IA se "desvía"

Síntomas de degradación de contexto:

- Vuelve a sugerir patrones que ya rechazamos.
- Olvida el tenantId en queries.
- Importa Prisma en Domain.
- Usa `number` para dinero.
- Inventa nombres de archivos / funciones que no existen.
- Genera respuestas más cortas o más vagas.

Acción:

```
STOP. Olvidaste [X regla inmutable]. Releé:
- erp-saas-core/SKILL.md
- erp-saas-core/references/[archivo relevante].md
- memory-bank-context/systemPatterns.md

Después confirmá que entendiste la regla y replanteá el código.
```

Si persiste, **resetear el chat** (nuevo hilo) y reiniciar con el prompt maestro. El Memory Bank preserva el contexto entre resets.

---

## Reseteo planificado (cuando el chat se hace lento)

Cada 30-50 mensajes o cuando notes degradación:

```
Vamos a cerrar este chat. Actualizá el Memory Bank con lo que hicimos hoy:
[ejecutar prompt de cierre]

Luego abro un chat nuevo y reiniciamos con el prompt maestro.
```

Esto convierte horas de contexto crudo en pocos KB de Memory Bank consolidado.

---

## Patrón de subagentes (Claude Code / Cline)

Si tu herramienta soporta subagentes:

| Subagente     | Modelo | Cuándo                                                  |
| ------------- | ------ | ------------------------------------------------------- |
| `architect`   | Opus   | Plan, decisiones arquitectónicas, refactor cross-module |
| `implementer` | Sonnet | Implementación de capa única según plan                 |
| `reviewer`    | Sonnet | Code review contra reglas inmutables                    |
| `tester`      | Haiku  | Escribir tests siguiendo patrones existentes            |
| `documenter`  | Haiku  | Actualizar Memory Bank, READMEs, ADRs                   |

Convenciones de handoff:

```
[architect] → [implementer]: pasa el plan completo + skills a leer
[implementer] → [reviewer]: pasa los archivos modificados + tests pasados
[reviewer] → [implementer]: pasa los FAIL con fix exacto
[implementer] → [documenter]: pasa el resumen al cerrar la tarea
```

---

## Plantillas listas para copiar

### A) Nuevo módulo desde cero

```
Vamos a crear el módulo `purchasing` (Compras y Proveedores).

Paso 1 — Diagramas:
Antes de cualquier código, generá en docs/modules/purchasing/:
1. erd.md con Mermaid (entidades: Supplier, PurchaseOrder, PurchaseOrderItem,
   GoodsReceipt, SupplierInvoice)
2. state-purchase-order.md con Mermaid (DRAFT → SUBMITTED → APPROVED → RECEIVED → CLOSED)

Esperá mi aprobación antes de pasar a código.
```

### B) Bug fix con TDD

```
Bug reportado: [descripción del bug]
Pasos para reproducir: [pasos]
Comportamiento esperado: [X]
Comportamiento actual: [Y]

Paso 1: Escribí un test que reproduzca el bug y FALLE.
Paso 2: Mostrame el test.
Esperá mi aprobación antes de tocar código de producción.
```

### C) Migración Prisma

```
Necesito agregar [campo / tabla / relación] a [modelo].

Paso 1: Mostrame el diff propuesto del schema.prisma.
Paso 2: Listame las consideraciones de:
  - Multi-tenant (¿hay tenantId? ¿índices?)
  - Soft delete (¿necesita deletedAt?)
  - Inmutabilidad (¿necesita trigger PG?)
  - Restricciones únicas con tenantId
  - Migraciones de datos existentes
Paso 3: Esperá mi aprobación. Después generá la migración con
  `pnpm prisma migrate dev --name [descripción] --create-only`
  y mostrame el SQL para revisarlo antes de aplicar.
```

### D) Integración entre módulos

```
Quiero que el módulo `accounting` reaccione cuando `pos` cierra una venta.

Reglas:
- NO podés importar `pos` desde `accounting` ni viceversa.
- Comunicación SOLO vía eventos (BullMQ + Outbox pattern).
- El handler en accounting debe ser idempotente (key = saleId).

Paso 1: Diagrama de secuencia del flujo.
Paso 2: Definición del evento (interface + payload) en `shared/events/`.
Paso 3: Implementar el handler en `accounting/infrastructure/queue/`.
```
