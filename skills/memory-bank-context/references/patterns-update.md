# Cómo Decidir si Algo va a `systemPatterns.md`

Esta es la pregunta más frecuente al mantener un Memory Bank. La respuesta corta: **un patrón merece systemPatterns.md cuando se va a repetir en otro lugar del código.**

---

## Test de los 3 criterios

Una decisión va a `systemPatterns.md` SI cumple los 3:

1. **Es general:** se aplicará a más de un módulo / carpeta / archivo.
2. **Es prescriptivo:** el equipo (humano + IA) debe seguirlo en el futuro.
3. **Tiene alternativas reales:** rechazamos otras opciones por razones explícitas.

Si solo cumple 1 o 2, probablemente va en otro lado:

| ¿Cumple?                                                     | Va en                                                      |
| ------------------------------------------------------------ | ---------------------------------------------------------- |
| Solo 1 (general): "el stack es NestJS 11"                    | `techContext.md`                                           |
| Solo 2 (prescriptivo): "no usar Tailwind"                    | Puede ir en `projectbrief.md` si es identidad del proyecto |
| Solo 3 (con alternativas): "elegimos PostgreSQL sobre Mongo" | ADR en `docs/adr/` (más formal)                            |
| Es transitorio: "hoy estoy resolviendo X"                    | `activeContext.md`                                         |
| Es histórico: "ayer terminamos Y"                            | `progress.md`                                              |

---

## Estructura canónica de un patrón

Cada patrón en `systemPatterns.md` sigue esta plantilla:

````markdown
## [Nombre del patrón]

**Problema:** [1-2 frases. ¿Qué fricción aparece sin este patrón?]

**Solución:** [1-3 frases. ¿Cómo se resuelve?]

**Ejemplo:**

```typescript
// snippet de código real del proyecto, NO inventado
```
````

**Cuándo NO usarlo:** [casos en que el patrón es contraproducente]

**Alternativas consideradas y rechazadas:**

- [Opción B]: rechazada porque [razón].
- [Opción C]: rechazada porque [razón].

**Visto en:** `src/modules/accounting/`, `src/modules/pos/`

````

---

## Ejemplos reales

### Ejemplo 1: SÍ va a systemPatterns

```markdown
## Outbox Pattern para Eventos Confiables

**Problema:** Publicar a BullMQ directo después de un `prisma.$transaction`
crea dos puntos de fallo: la DB puede commitear y BullMQ caer (perdés el
evento), o BullMQ acepta y la DB rollbacka (evento sin sustento).

**Solución:** Guardar el evento en una tabla `OutboxEvent` dentro de la misma
transacción DB. Un worker separado lee la outbox y publica a BullMQ con retry.

**Ejemplo:**
```typescript
await prisma.$transaction(async (tx) => {
  const sale = await tx.sale.create({ data: cmd });
  await tx.outboxEvent.create({
    data: { eventName: 'SaleCompleted', payload: { saleId: sale.id } },
  });
});
// El OutboxPublisher (cron job) lee y publica.
````

**Cuándo NO usarlo:** Eventos de UI puramente in-process (mismo módulo).

**Alternativas consideradas y rechazadas:**

- Two-phase commit: complejidad operacional alta, requiere XA transactions.
- Pub directo a BullMQ tras commit: race condition entre commit y publish.

**Visto en:** `src/modules/pos/`, `src/modules/purchasing/`

````

✓ Cumple los 3 criterios: general, prescriptivo, con alternativas rechazadas.

### Ejemplo 2: NO va a systemPatterns (va a activeContext)

```markdown
## Estoy debuggeando un memory leak en el worker de fiscal-dgii
````

Esto es transitorio. Va a `activeContext.md`, no a `systemPatterns.md`.

### Ejemplo 3: NO va a systemPatterns (va a techContext)

```markdown
## Usamos Decimal.js v10.4.3
```

Esto es stack, no patrón. Va a `techContext.md`.

### Ejemplo 4: NO va a systemPatterns (va a projectbrief)

```markdown
## El sistema debe operar offline para POS
```

Esto es un requerimiento de producto inviolable. Va a `projectbrief.md`.

### Ejemplo 5: límite difuso (va a systemPatterns si lo justificás)

```markdown
## Nombres de Use Cases: <Verb><Entity>UseCase

**Problema:** Si cada quien nombra como quiere, navegar el código es lento.
**Solución:** Patrón <Verb><Entity>UseCase. Ej: PostJournalEntryUseCase, CloseFiscalPeriodUseCase.
**Visto en:** todos los módulos
```

Aquí "alternativas reales" es débil (es solo una convención), pero si la repetís en N módulos, ahorra debate. Va a systemPatterns con menos formalidad.

---

## Patrones que casi todo proyecto ERP debería tener

Si no aparecen en tu `systemPatterns.md` después de 2-3 semanas, falta documentar:

- [ ] Multi-tenant via Prisma Client Extension (no a mano)
- [ ] Soft delete con `deletedAt`
- [ ] Idempotency Key obligatorio en mutaciones financieras
- [ ] Outbox Pattern para eventos cross-context
- [ ] Validación de partida doble en domain (no en DB)
- [ ] Triggers PG para inmutabilidad del libro mayor
- [ ] Locking pattern para secuencias (NCF, asientos)
- [ ] Naming de Use Cases / Commands / Events
- [ ] Estructura de carpetas por Bounded Context
- [ ] Reglas de import (no Domain → Infra)

---

## Cuándo retirar un patrón

Si un patrón en `systemPatterns.md` ya no aplica:

1. **No lo borres.** Marcalo como deprecated.

```markdown
## ~~Patrón X~~ ⚠️ DEPRECATED 2026-05-21

**Reemplazado por:** [Nuevo Patrón Y]
**Razón:** [Por qué se cambió]
**Migración:** [Cómo migrar código existente]

[contenido original conservado abajo]
```

2. Cuando el código viejo se haya migrado completamente, eliminá la sección y dejá nota:

```markdown
## Historial de cambios

- 2026-05-21: Eliminado "Patrón X" (deprecated 2026-05-21, migración completada).
```

---

## Anti-checklist: cosas que NO van a systemPatterns

| Cosa                                          | Por qué no                         | Dónde sí                           |
| --------------------------------------------- | ---------------------------------- | ---------------------------------- |
| "Esta función usa async/await"                | Convención del lenguaje, no patrón | Ningún lado                        |
| "El test pasa con coverage 85%"               | Métrica, no patrón                 | `progress.md`                      |
| "Cambié 3 nombres de variables"               | Refactor cosmético                 | Ningún lado                        |
| "TODO: revisar performance del query X"       | TODO transitorio                   | `activeContext.md` o issue tracker |
| "El cliente pidió cambiar el color del botón" | Cambio de UI puntual               | Ticket en issue tracker            |
| "Decidimos no usar Redis Sentinel todavía"    | Decisión técnica con alternativas  | ✓ Sí, este SÍ va a systemPatterns  |
