# Protocolo Detallado del Memory Bank

## Las 4 ceremonias

El Memory Bank funciona con 4 ceremonias bien definidas. Cada agente IA debe ejecutarlas en el orden correcto.

```
[A] Inicio de sesión   → leer todo, confirmar
[B] Durante el trabajo → consultar, no alucinar
[C] Cierre de sesión   → actualizar diffs
[D] Reseteo de chat    → commit + chat nuevo
```

---

## A) Inicio de sesión — Lectura obligatoria

### Prompt humano (copy-paste al primer mensaje)

```
Antes de cualquier acción:

1. Leé los 6 archivos del directorio `memory-bank/`:
   - projectbrief.md
   - productContext.md
   - systemPatterns.md
   - techContext.md
   - activeContext.md
   - progress.md

2. También leé el SKILL.md de `erp-saas-core` y los references relevantes
   según mi tarea.

3. Confirmame en 3-5 bullets:
   - En qué proyecto estamos.
   - Qué se hizo en la última sesión (activeContext).
   - Qué está pendiente (próximos 1-3 ítems de progress).
   - Cualquier decisión bloqueante esperando mi input.

4. NO escribas código. Esperá mi instrucción.
```

### Respuesta esperada del agente

```
He leído el Memory Bank. Estamos en:

• Proyecto: Mi POS — POS multi-tenant para R.D., en construcción del
  módulo `accounting`.
• Última sesión: Se cerró el ERD del módulo accounting y se generó la
  primera migración Prisma con Account, JournalEntry, JournalLine.
• Pendiente: Implementar PostJournalEntryUseCase con TDD; falta crear los
  triggers de inmutabilidad en PostgreSQL.
• Bloqueo: Necesito confirmación tuya sobre si los códigos contables siguen
  el plan DGII o un plan custom (mencionado en activeContext línea 12).

Listo. ¿Qué hacemos hoy?
```

Este formato cumple 3 reglas:

1. Compacto (no recita los archivos completos).
2. Específico (cita líneas y archivos cuando hay duda).
3. Cierra preguntando, no escribiendo código.

---

## B) Durante la sesión — Consulta selectiva

El agente NO recita el Memory Bank cada vez. Consulta cuando:

| Disparador                             | Archivo a releer                        |
| -------------------------------------- | --------------------------------------- |
| "¿Cómo nombramos esta carpeta?"        | `systemPatterns.md`                     |
| "¿Qué versión de Prisma estás usando?" | `techContext.md`                        |
| "¿Esta dependencia ya está aprobada?"  | `techContext.md`                        |
| "¿Esto contradice algo del proyecto?"  | `projectbrief.md` + `systemPatterns.md` |
| "¿Quién es el usuario final aquí?"     | `productContext.md`                     |
| "¿Esto ya lo intentamos?"              | `progress.md`                           |

Si el agente "no recuerda" → reread, no improvise.

### Patrón de notificación al humano

Si el agente detecta una contradicción entre el código actual y un patrón documentado:

```
⚠️ Esto contradice systemPatterns.md sección 3.2: "Cero imports inversos
entre Bounded Contexts; comunicación vía eventos BullMQ".

Tu request actual importa `pos/domain/entities/sale.entity.ts` desde
`accounting/`. Tres opciones:

A) Mover la lógica de Sale a un evento `SaleCompleted` con payload completo.
B) Crear un Shared Kernel con un value-object `SaleSummary` compartido.
C) Actualizar systemPatterns.md para permitir esta excepción (justificación).

¿Cuál?
```

---

## C) Cierre de sesión — Diffs propuestos

### Prompt humano

```
Vamos a cerrar sesión. Actualizá el Memory Bank.

1. Releé los 6 archivos actuales (state of the world).
2. Proponeme un DIFF para cada archivo que necesita cambios:
   - activeContext.md → reemplazar completo con el estado de AHORA.
   - progress.md → APPEND a "Completado" con fecha; reorganizar "En curso".
   - systemPatterns.md → solo si descubrimos un patrón nuevo.
   - techContext.md → solo si cambiaron dependencias.
   - productContext.md / projectbrief.md → casi nunca cambian.

3. NO los sobrescribas. Mostrame el diff en formato:

   --- archivo.md (antes)
   +++ archivo.md (después)
   @@ ...

4. Esperá mi aprobación archivo por archivo.
```

### Ejemplo de diff bien hecho

```diff
--- memory-bank/activeContext.md (antes)
+++ memory-bank/activeContext.md (después)
@@ -1,10 +1,8 @@
 # Active Context

-**Tarea actual:** Cerrar ERD del módulo accounting.
-**Archivos siendo modificados:** prisma/schema.prisma, docs/modules/accounting/erd.md
-**Decisiones pendientes:** ¿Plan contable DGII o custom? → respuesta del humano: DGII
-**Errores en diagnóstico:** ninguno
-**Bloqueos:** esperando confirmación del plan contable
+**Tarea actual:** Implementar PostJournalEntryUseCase con TDD.
+**Archivos siendo modificados:** src/modules/accounting/application/use-cases/, test/unit/accounting/
+**Decisiones pendientes:** ninguna
+**Errores en diagnóstico:** ninguno
+**Bloqueos:** ninguno
```

```diff
--- memory-bank/progress.md (antes)
+++ memory-bank/progress.md (después)
@@ -18,6 +18,9 @@
 ## Completado

+- **2026-05-21** ERD del módulo accounting finalizado. Migración Prisma
+  inicial aplicada con Account, JournalEntry, JournalLine. Triggers de
+  inmutabilidad documentados (pendientes de migración SQL).
 - **2026-05-19** Setup inicial Turborepo, NestJS 11, Next.js 15, Prisma 7.
 - **2026-05-18** Decisión arquitectónica: Clean Architecture estricta.

@@ -28,7 +31,7 @@
 ## En Curso

-- [P1] ERD módulo accounting (esperando confirmación plan contable)
+- [P1] PostJournalEntryUseCase con TDD (próximo)
+- [P1] Migración SQL de triggers de inmutabilidad

 ## Backlog
```

> Notá: `activeContext.md` se reemplaza completo (corto, vive en el presente). `progress.md` se appendea (es histórico).

---

## D) Reseteo de chat

Cuando el chat actual se degrada (lento, repite errores, alucina):

1. Ejecutar paso C (cerrar sesión).
2. Confirmar que el commit del Memory Bank fue exitoso:
   ```bash
   git add memory-bank/
   git commit -m "memory-bank: sesión 2026-05-21 — accounting ERD + migración inicial"
   git push
   ```
3. Cerrar el chat actual.
4. Abrir chat nuevo.
5. Primer mensaje = prompt de inicio (paso A).

El nuevo agente, en menos de 30 segundos de lectura, tiene todo el contexto que el viejo construyó en horas.

**Frecuencia recomendada:** cada 30-50 mensajes intensivos, o cuando notes degradación.

---

## Reglas anti-degradación

| Síntoma                                                      | Acción inmediata                                |
| ------------------------------------------------------------ | ----------------------------------------------- |
| El agente repite una pregunta ya respondida en activeContext | "Releé activeContext.md, ahí está la respuesta" |
| El agente sugiere un patrón rechazado                        | "Releé systemPatterns.md sección X"             |
| El agente usa una versión vieja del stack                    | "Releé techContext.md"                          |
| El agente inventa archivos/funciones                         | Reset de chat                                   |
| El agente da respuestas más cortas/vagas                     | Reset de chat                                   |
| El agente ignora reglas críticas                             | Reset de chat + verificar prompt de inicio      |

---

## Cuándo NO actualizar el Memory Bank

- Cambios menores en código (refactor de 1 archivo).
- Comentarios o renombres triviales.
- Experimentos descartados.
- Sesiones de exploración sin decisiones tomadas.

El Memory Bank es para **decisiones y estado**, no para una transcripción del chat.

---

## Métricas de un Memory Bank saludable

- `activeContext.md` siempre cabe en una pantalla (< 1 KB).
- `progress.md` crece monotónicamente (nunca se borra historia).
- `systemPatterns.md` tiene al menos 1 patrón nuevo cada 2-3 semanas en proyectos activos.
- `techContext.md` cambia solo cuando hay un PR de upgrade.
- `projectbrief.md` y `productContext.md` cambian < 1 vez por trimestre.

Si tu Memory Bank no cumple esto, está mal mantenido. Ver `anti-patterns.md`.
