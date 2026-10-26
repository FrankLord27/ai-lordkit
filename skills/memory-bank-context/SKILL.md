---
name: memory-bank-context
description: >
  Sistema de retención de contexto entre sesiones de IA para proyectos de desarrollo
  largos (ERP, SaaS, monorepos). Resuelve el problema de la "amnesia" del LLM y la
  degradación cognitiva al saturar la ventana de contexto. Mantiene 6 archivos
  Markdown canónicos (projectbrief, productContext, systemPatterns, techContext,
  activeContext, progress) que el agente lee al inicio de CADA sesión y actualiza
  al final. Úsala SIEMPRE que el usuario: arranque una nueva sesión de chat para un
  proyecto que viene trabajando, mencione "Memory Bank", "perdí el contexto",
  "olvidaste lo anterior", "actualizá el contexto", "reseteá el chat", "qué estábamos
  haciendo", "dónde íbamos", "qué falta", o cuando trabaje en proyectos largos
  (POS, ERP, SaaS, sistemas escolares). Esta skill es complementaria
  a `erp-saas-core`: el core dicta las reglas inmutables del dominio, el Memory Bank
  guarda el estado vivo del avance. Activá esta skill ANTES de cualquier prompt
  sustantivo en una sesión nueva, incluso si el usuario no lo pide explícitamente,
  para prevenir que el agente alucine sobre el estado del proyecto.
compatibility:
  pairs_with:
    - erp-saas-core (reglas inmutables del dominio)
    - cualquier skill de stack específico
  works_with:
    - Claude Code
    - Cursor (.cursorrules)
    - Cline (.clinerules)
    - OpenCode / Roo Code
    - Cualquier IA conversacional con file system access
---

# Memory Bank — Retención de Contexto entre Sesiones

## El problema que resuelve

Las IAs operan con ventana de contexto finita. En proyectos largos:

- Olvidan reglas establecidas al inicio.
- Repiten errores ya corregidos.
- Pierden el hilo del estado actual.
- Inventan patrones que no son los del proyecto.
- Degradan la calidad a medida que el chat crece.

El **Memory Bank** convierte miles de tokens de conversación cruda en pocos KB de documentación consolidada que el agente puede releer al inicio de cada sesión.

> **Origen del patrón:** popularizado por la comunidad de Cline/Roo Code, ampliable a cualquier agente de codificación.

---

## Arquitectura: 6 archivos canónicos

```
memory-bank/
├── projectbrief.md        ← Constitución. No cambia casi nunca.
├── productContext.md      ← Por qué existe el producto. Cambios bajos.
├── systemPatterns.md      ← Patrones arquitectónicos descubiertos. Crece.
├── techContext.md         ← Stack vigente. Actualizar al cambiar deps.
├── activeContext.md       ← HOY. Cambia constantemente.
└── progress.md            ← Tareas hechas / pendientes. Crece linealmente.
```

| Archivo             | Volatilidad | Tamaño típico    | Quién lo actualiza               |
| ------------------- | ----------- | ---------------- | -------------------------------- |
| `projectbrief.md`   | Casi nula   | 200-500 palabras | El humano al inicio del proyecto |
| `productContext.md` | Muy baja    | 300-800 palabras | El humano + IA en milestones     |
| `systemPatterns.md` | Media       | Crece a 2-5 KB   | IA al descubrir un patrón nuevo  |
| `techContext.md`    | Baja        | 300-600 palabras | IA al cambiar dependencias       |
| `activeContext.md`  | Alta        | < 1 KB siempre   | IA al fin de cada sesión         |
| `progress.md`       | Alta        | Crece monotónico | IA al cerrar cada tarea          |

---

## Reglas inviolables del Memory Bank

1. **Leer SIEMPRE los 6 archivos al inicio de la sesión.** Sin excepción.
2. **`activeContext.md` debe caber en menos de 1 KB.** Si crece, consolidar lo viejo en `progress.md` o `systemPatterns.md`.
3. **No duplicar información entre archivos.** Cada hecho vive en uno solo.
4. **Actualización propuesta como diff, no overwrite.** Mostrar al usuario el cambio antes de aplicarlo.
5. **Una sola fuente de verdad.** Si `activeContext` y `progress` se contradicen, gana lo más reciente y se reconcilia.
6. **El Memory Bank es para humanos también.** Markdown legible, no JSON ni YAML denso.
7. **Versionado en git.** El Memory Bank vive en el repo del proyecto, no en un servicio externo.

---

## Estructura por archivo

### 1. `projectbrief.md` — La Constitución

Define el **qué** y el **por qué a largo plazo**. Si esto cambia, todo lo demás cambia.

Contenido:

- Nombre del proyecto y propósito en 1-2 frases.
- Quién es el usuario final.
- Objetivos macro (3-7 bullets).
- Restricciones inviolables (legales, técnicas, de negocio).
- Fuera de alcance (qué NO hace el sistema).

Ver `templates/projectbrief.md`.

### 2. `productContext.md` — Por qué existe

Define el problema de negocio y cómo el producto lo resuelve.

Contenido:

- Problema concreto que resuelve.
- Personas principales (1-3 personajes con sus jobs-to-be-done).
- Flujos de usuario críticos.
- Métricas de éxito.
- Diferenciación vs competencia (si aplica).

Ver `templates/productContext.md`.

### 3. `systemPatterns.md` — Patrones arquitectónicos

Define el **cómo estructural**. Crece a medida que el equipo descubre patrones útiles.

Contenido:

- Bounded contexts del proyecto.
- Convenciones de naming (carpetas, archivos, símbolos).
- Decisiones arquitectónicas (links a ADRs si existen).
- Patrones de diseño aplicados (Repository, Outbox, etc.).
- Anti-patrones rechazados (con justificación).
- Reglas de import / dependencias entre módulos.

Ver `templates/systemPatterns.md`.

### 4. `techContext.md` — Stack vigente

Define el **cómo concreto**. Versiones, librerías, infra.

Contenido:

- Stack canónico con versiones mínimas.
- Servicios externos en uso.
- Variables de entorno requeridas.
- Comandos críticos (build, test, migrate, deploy).
- Versiones de Node, pnpm, PostgreSQL, etc.

Ver `templates/techContext.md`.

### 5. `activeContext.md` — Lo de HOY

Lo único que cambia en cada sesión. **Mantenerlo corto.**

Contenido:

- Tarea actual (1 línea).
- Archivos siendo modificados.
- Decisiones pendientes que requieren al humano.
- Errores que estamos diagnosticando.
- Bloqueos.

Ver `templates/activeContext.md`.

### 6. `progress.md` — Mapa de avance

Bitácora de qué funciona, qué no, y qué viene.

Contenido:

- Hitos completados (con fecha).
- Tareas en curso.
- Backlog priorizado.
- Bugs conocidos.
- Decisiones pospuestas.

Ver `templates/progress.md`.

---

## Protocolo de uso

### A) Inicio de sesión

Primer prompt SIEMPRE:

```
Antes de cualquier acción:

1. Leé los 6 archivos del directorio `memory-bank/`.
2. Confirmame en 3-5 bullets:
   - En qué proyecto estamos
   - Qué se hizo en la última sesión (activeContext)
   - Qué está pendiente (progress)
   - Cualquier decisión bloqueante
3. NO escribas código. Esperá mi instrucción.
```

### B) Durante la sesión

El agente:

- Consulta `systemPatterns.md` antes de proponer estructura.
- Consulta `techContext.md` antes de usar una librería.
- Respeta lo definido en `projectbrief.md` como inviolable.
- Notifica al humano si propone algo que contradice un patrón existente.

### C) Cierre de sesión / Saturación de contexto

Cuando notes degradación, o al fin del sprint del día:

```
Cerramos sesión. Actualizá el Memory Bank:

1. activeContext.md → Reemplazá con el estado de AHORA (no acumular historia).
2. progress.md      → Agregar tareas completadas hoy con fecha. Mover de "En curso" a "Hecho".
3. systemPatterns.md → ¿Descubrimos un patrón nuevo? Documentarlo con ejemplo.
4. techContext.md   → ¿Cambiaron deps? Actualizar versiones.

Mostrame el DIFF de cada archivo. NO los sobrescribas sin mi aprobación.
```

### D) Reseteo (chat nuevo)

Cuando el chat actual está saturado o lento:

1. Ejecutar cierre de sesión (paso C).
2. Verificar que el commit/diff del Memory Bank se guardó.
3. Cerrar chat. Abrir uno nuevo.
4. Primer prompt = prompt de inicio de sesión (paso A).

El nuevo agente recupera contexto en segundos leyendo 6 archivos cortos.

---

## Integración con otras skills

### Con `erp-saas-core`

| Skill                 | Función                                                                      |
| --------------------- | ---------------------------------------------------------------------------- |
| `erp-saas-core`       | REGLAS inmutables (no cambian con el tiempo).                                |
| `memory-bank-context` | ESTADO mutable (qué se hizo, qué falta, decisiones del proyecto específico). |

Diferencia clave: `erp-saas-core` aplica igual a todos tus proyectos. El Memory Bank de cada uno es completamente distinto.

### Con validación arquitectural (dependency-cruiser)

`systemPatterns.md` documenta las reglas. Si el proyecto tiene dependency-cruiser configurado, este las enforce automáticamente. Cuando la validación falla, el agente lee `systemPatterns.md` para entender por qué.

### Con skills de stack (`nestjs-docs`, etc.)

`techContext.md` declara qué versión está en uso. El agente carga el skill correcto (`nestjs-docs v11`, no v10) basándose en eso.

---

## Setup inicial en un proyecto nuevo

```bash
# 1. Crear directorio en la raíz del repo
mkdir memory-bank

# 2. Copiar plantillas (ver templates/ de esta skill)
# 3. Rellenar projectbrief.md y productContext.md con el humano
# 4. Inicializar techContext.md desde package.json
# 5. Crear systemPatterns.md vacío (se llenará con el tiempo)
# 6. Crear activeContext.md y progress.md vacíos

# 7. Commit inicial
git add memory-bank/
git commit -m "Initialize Memory Bank"
```

Templates listos en: `templates/projectbrief.md`, `templates/productContext.md`, etc.

---

## Reglas para que la IA mantenga el banco saludable

### Reglas de `activeContext.md`

- Máximo 1 KB. Si crece, consolidar.
- Si una decisión se tomó hace > 3 sesiones y sigue ahí: moverla a `systemPatterns.md` o resolverla.
- Si un bloqueo lleva > 5 días: escalarlo en `progress.md`.

### Reglas de `progress.md`

- Append-only en la sección "Completado".
- Cada entrada con fecha ISO (`2026-05-21`).
- Bugs conocidos con severidad (P0/P1/P2/P3) y ETA.

### Reglas de `systemPatterns.md`

- Cada patrón tiene: nombre, problema que resuelve, solución, ejemplo de código, contra-indicación.
- Si un patrón se contradice con otro, eliminar el viejo y dejar nota.

### Reglas de `techContext.md`

- Versionar TODAS las deps críticas con versión mínima.
- Marcar deps "experimentales" o "candidatas a remoción".

---

## Variantes según tu agente

| Agente              | Archivo de inicialización                          |
| ------------------- | -------------------------------------------------- |
| Claude Code         | `.claude/CLAUDE.md` o skills personales            |
| Cursor              | `.cursorrules` referenciando `memory-bank/`        |
| Cline               | `.clinerules/memory-bank.md`                       |
| OpenCode / Roo Code | reglas globales del agente                         |
| Otros               | system prompt al inicio + read-tool del filesystem |

Plantilla de `.clinerules/memory-bank.md`:

```markdown
# Memory Bank Protocol

Before responding to ANY request:

1. Read all 6 files in `memory-bank/`:
   - projectbrief.md
   - productContext.md
   - systemPatterns.md
   - techContext.md
   - activeContext.md
   - progress.md

2. Confirm understanding in 3-5 bullets.

3. Wait for the user's task.

After completing any task:

4. Propose updates to activeContext.md and progress.md as diffs.
5. If a new pattern was discovered, propose update to systemPatterns.md.
```

---

## Antipatrones del Memory Bank

| Antipatrón                               | Síntoma                            | Fix                                                     |
| ---------------------------------------- | ---------------------------------- | ------------------------------------------------------- |
| Memory Bank gigante                      | `activeContext.md` con 30 KB       | Consolidar histórico en `progress.md`, dejar solo "hoy" |
| Duplicación de info                      | Mismo dato en 3 archivos           | Mover a un solo archivo, linkear desde los otros        |
| Outdated                                 | Memory Bank quedó atrás del código | Auditar al inicio de cada sprint                        |
| Demasiado abstracto                      | Frases vagas sin ejemplo           | Agregar bloque de código real                           |
| Solo lo lee la IA                        | El equipo humano no lo consulta    | Hacerlo parte del onboarding                            |
| Versiones desfasadas en `techContext.md` | `next: 14` cuando estás en 15      | Auto-update vía script CI                               |

---

## Archivos de referencia

- `references/protocol.md` → Protocolo detallado paso a paso + ejemplos completos
- `references/patterns-update.md` → Cómo decidir si algo va a systemPatterns o no
- `references/anti-patterns.md` → Ejemplos de Memory Banks mal mantenidos
- `templates/projectbrief.md` → Plantilla copy-paste
- `templates/productContext.md`
- `templates/systemPatterns.md`
- `templates/techContext.md`
- `templates/activeContext.md`
- `templates/progress.md`
- `templates/clinerules-example.md` → Para configurar Cline
- `templates/cursorrules-example.md` → Para configurar Cursor
