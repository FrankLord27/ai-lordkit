# Cline Rules — Memory Bank Protocol

> Guardar este archivo como `.clinerules/memory-bank.md` en la raíz del repo.
> Cline lo lee automáticamente al inicio de cada sesión.

---

## Antes de cualquier acción

1. **Lee el Memory Bank completo** ubicado en `memory-bank/`:
   - `projectbrief.md` — Constitución del proyecto.
   - `productContext.md` — Por qué existe el producto.
   - `systemPatterns.md` — Patrones arquitectónicos vigentes.
   - `techContext.md` — Stack y versiones actuales.
   - `activeContext.md` — Estado de HOY.
   - `progress.md` — Histórico y backlog.

2. **Lee también los skills relevantes:**
   - `erp-saas-core/SKILL.md` y references aplicables a la tarea.
   - Otros skills según `techContext.md`.

3. **Confirma comprensión** en 3-5 bullets:
   - En qué proyecto estamos.
   - Qué se hizo en la última sesión.
   - Qué está pendiente.
   - Cualquier decisión bloqueante.

4. **No escribas código** hasta recibir instrucción explícita.

---

## Durante la sesión

- Consulta `systemPatterns.md` antes de proponer estructura de carpetas o naming.
- Consulta `techContext.md` antes de sugerir una dependencia o versión.
- Respeta `projectbrief.md` como inviolable.
- Si una sugerencia contradice un patrón documentado, NOTIFICA al humano
  con 2-3 opciones de resolución.

---

## Reglas inmutables (de `erp-saas-core`)

1. `tenantId` se obtiene del JWT, jamás del body.
2. Soft delete vía `deletedAt`, no DELETE físico.
3. Dinero en `Decimal`, nunca `number`.
4. Redondeo bancario `ROUND_HALF_EVEN`.
5. Partida doble: suma = 0 validado en domain.
6. Libro mayor inmutable (triggers PG).
7. Idempotency key obligatorio en mutaciones financieras.
8. `prisma.$transaction` para operaciones multi-tabla.
9. Cero `any`, cero `ts-ignore`, cero casteos inseguros.
10. TDD primero en lógica financiera.
11. Clean Architecture: Domain → Application ← Infrastructure / Presentation.

---

## Al cerrar la tarea

1. Propón un DIFF (no overwrite) para:
   - `activeContext.md` → reemplazar con estado actual.
   - `progress.md` → append a "Completado" con fecha; reorganizar "En curso".
   - `systemPatterns.md` → solo si hubo patrón nuevo.
   - `techContext.md` → solo si cambiaron dependencias.

2. Espera aprobación archivo por archivo antes de aplicar cambios.

3. Recordá al humano hacer `git commit` del Memory Bank.

---

## Reseteo de chat

Cuando el chat se degrade:

1. Ejecutá el cierre de tarea (paso anterior).
2. Pedile al humano que commitee el Memory Bank.
3. Sugerile cerrar el chat actual y abrir uno nuevo.

El próximo agente recuperará el contexto en segundos leyendo los 6 archivos.

---

## Idioma

[Definir según proyecto: español / inglés / spanglish]

## Estilo de respuesta

- Concreto, no poético.
- Snippets de código antes que prosa.
- Si das opciones, máximo 3 con trade-offs claros.
- Cero apologetics ("disculpá la confusión..."). Acción directa.
