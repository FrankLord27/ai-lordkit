# Antipatrones del Memory Bank

Casos reales (y dolorosos) de Memory Banks mal mantenidos. Sirven como checklist negativo: si tu banco se parece a alguno de estos, hay que arreglarlo antes de seguir sumando código.

---

## Antipatrón 1: "El blob inmortal"

### Síntoma

`activeContext.md` tiene 18 KB y arrastra entradas desde hace 3 meses.

```markdown
# Active Context

## Hoy: 2026-05-21

[300 líneas]

## Ayer: 2026-05-20

[280 líneas]

## La semana pasada

[800 líneas]

## El mes pasado

...
```

### Por qué duele

- La IA gasta tokens releyendo basura histórica.
- "Lost in the middle": ignora lo realmente vigente.
- El humano ya no se acuerda qué es lo de hoy.

### Fix

`activeContext.md` SOLO contiene HOY. Lo de ayer va a `progress.md` como entrada con fecha.

```markdown
# Active Context

**Tarea actual:** Implementar PostJournalEntryUseCase con TDD.
**Archivos:** src/modules/accounting/application/...
**Decisiones pendientes:** ninguna
**Bloqueos:** ninguno
```

Si ya tenés el blob, separá:

- Histórico → mover a `progress.md` ordenado por fecha.
- Patrones que aparecen recurrentemente → consolidar en `systemPatterns.md`.
- Lo de hoy → dejarlo.

---

## Antipatrón 2: "El banco fantasma"

### Síntoma

El Memory Bank existe pero nadie lo lee. El humano arranca cada sesión con: "Hola Claude, ¿te acordás del POS?".

### Por qué duele

- El agente arranca sin contexto y alucina decisiones.
- El humano repite información que ya escribió.
- El banco queda desactualizado porque nadie lo cierra.

### Fix

- Pegá el prompt de inicio en una nota fija o en `.cursorrules` / `.clinerules`.
- Hacé que sea automático: si el agente soporta archivos de bootstrap, ponelo ahí.
- Auditá cada lunes: ¿el agente está leyendo? ¿está actualizando?

---

## Antipatrón 3: "El banco mentiroso"

### Síntoma

`techContext.md` dice "NestJS 10" pero el `package.json` ya está en NestJS 11. `progress.md` lista una feature como "Completado" pero el código no compila.

### Por qué duele

- El agente sigue la mentira y propone código de NestJS 10.
- Genera tickets de bugs sobre cosas que ya estaban en backlog.
- Pierde toda credibilidad: si el banco miente, el agente lo ignora.

### Fix

- Al cerrar cada sesión, verificar `techContext.md` contra `package.json` real.
- "Completado" en `progress.md` solo cuando: (a) el código pasa tests, (b) está mergeado a `main`, (c) deployable.
- Script CI opcional que falle el build si `techContext.md` está desincronizado.

---

## Antipatrón 4: "El banco poético"

### Síntoma

`systemPatterns.md` está lleno de filosofía:

```markdown
## Sobre la arquitectura

Buscamos un diseño elegante que refleje la naturaleza del dominio, donde cada
módulo respira con autonomía mientras dialoga con sus vecinos a través de
contratos claros, en una sinfonía de responsabilidades bien delineadas...
```

### Por qué duele

- El agente no puede actuar sobre frases vagas.
- El humano no encuentra la regla concreta cuando la necesita.
- En 6 meses, nadie entiende qué significaba.

### Fix

Reescribir cada patrón con:

- Nombre concreto (verbo + objeto).
- Problema en 1-2 frases técnicas.
- Solución con snippet de código real.
- Anti-ejemplo de lo que NO hacer.

Ver `patterns-update.md` para plantilla.

---

## Antipatrón 5: "El banco duplicado"

### Síntoma

El mismo hecho aparece en 3 archivos:

- `projectbrief.md`: "Usamos Decimal.js para dinero."
- `techContext.md`: "Dep: decimal.js v10."
- `systemPatterns.md`: "Patrón Money: usar Decimal.js."

### Por qué duele

- Si se actualiza un archivo y no los otros, contradicción.
- El agente lee 3 veces lo mismo, gasta tokens.

### Fix

Una fuente de verdad por dato:

| Dato                                 | Archivo correcto                               |
| ------------------------------------ | ---------------------------------------------- |
| Stack y versiones                    | `techContext.md`                               |
| Cómo se aplica (Money VO, redondeo)  | `systemPatterns.md`                            |
| Por qué eligimos Decimal (vs BigInt) | ADR en `docs/adr/` o nota corta en techContext |

Los otros archivos linkean: `Ver techContext.md`.

---

## Antipatrón 6: "El banco infinito"

### Síntoma

`systemPatterns.md` tiene 60 KB. Cada decisión técnica está documentada, hasta la elección de prettier vs eslint.

### Por qué duele

- El agente no puede cargar todo en contexto.
- Decisiones triviales saturan las importantes.
- Mantener requiere más tiempo del que ahorra.

### Fix

- Solo patrones que cumplan los 3 criterios (general + prescriptivo + con alternativas reales).
- Convenciones de estilo → archivo `.prettierrc` / `.eslintrc`, no Memory Bank.
- Decisiones operacionales triviales → comentarios en código, no banco.

Si tu `systemPatterns.md` pasa de 5-8 KB, auditarlo. La mayoría se puede mover a ADRs en `docs/adr/`.

---

## Antipatrón 7: "El banco sin diffs"

### Síntoma

El agente sobrescribe `activeContext.md` y `progress.md` sin mostrar diff. Cada commit del banco es un `+200 -180` ilegible.

### Por qué duele

- No podés auditar qué cambió.
- Si la IA escribió mal, no te das cuenta.
- Git blame inútil.

### Fix

Regla en el prompt de cierre:

```
NO sobrescribas. Mostrame el DIFF en formato unified (--- antes, +++ después)
y esperá mi aprobación archivo por archivo.
```

Si tu agente no soporta diffs nativos, pedile que muestre las líneas que va a cambiar antes de tocar el archivo.

---

## Antipatrón 8: "El banco sin commit"

### Síntoma

El Memory Bank vive solo en tu disco. Nunca se hace `git push`.

### Por qué duele

- Si tu máquina muere, perdés todo el contexto.
- Otro dev (o vos en otra máquina) no tiene el banco.
- Sin historial de cambios, no podés volver atrás.

### Fix

```bash
# Al cerrar cada sesión:
git add memory-bank/
git commit -m "memory-bank: [resumen 1 línea de la sesión]"
git push
```

Idealmente, hooks de git que te recuerden si el banco cambió y no commiteaste.

---

## Antipatrón 9: "El banco multi-personalidad"

### Síntoma

Cada miembro del equipo escribe en estilo distinto. Algunos archivos están en español, otros en inglés, otros en spanglish. Las plantillas no se respetan.

### Por qué duele

- La IA tiene que adivinar el estilo.
- Los humanos también: "¿en qué archivo busco esto?".
- Mantenerlo se vuelve políticamente difícil.

### Fix

- Una sola convención de idioma (en proyectos LatAm: español; en internacionales: inglés). El proyecto define cuál.
- Plantillas fijas (las de `templates/` de esta skill).
- En PRs grandes, alguien (humano o IA) limpia el banco antes de mergear.

---

## Antipatrón 10: "El banco del genio incomprendido"

### Síntoma

Hay decisiones críticas en el código que no están en el banco. Cuando preguntás "¿por qué hicimos X?", la respuesta es "estaba en el chat de hace 2 meses".

### Por qué duele

- El conocimiento muere con la sesión de chat.
- Nuevos colaboradores (humanos o IA) no entienden.
- Recreás errores ya resueltos.

### Fix

Regla: cualquier decisión que afecte > 1 archivo del código va al banco antes de cerrar la sesión.

Patrón obligatorio al cerrar:

```
Antes de cerrar, ¿hubo alguna decisión técnica importante que tomamos hoy?
Si sí, documentala en systemPatterns.md o en un ADR.
```

---

## Checklist mensual del Memory Bank

Una vez al mes (o al cerrar cada sprint), auditá:

- [ ] `activeContext.md` cabe en una pantalla (< 1 KB).
- [ ] `progress.md` tiene fechas en cada entrada.
- [ ] `techContext.md` matchea `package.json`.
- [ ] `systemPatterns.md` no tiene patrones deprecated sin marcar.
- [ ] No hay duplicación entre archivos.
- [ ] Idioma consistente.
- [ ] Cada patrón tiene snippet de código real.
- [ ] Decisiones del último sprint están reflejadas.

Si fallás 2+ items, dedicale 30 min a limpiar antes de seguir.
