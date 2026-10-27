---
name: elegir-metodo
description: Úsala al arrancar un proyecto nuevo, un módulo o una feature grande, cuando el usuario pregunte cómo organizar el trabajo o cuando quiera cambiar de método. Recomienda un método (spike, bloques, spec corto o definición fuerte) con pros y contras, muestra las alternativas, el usuario escoge y la decisión queda en docs/METODO.md.
---

# Elegir el método de trabajo

Con IA no conviene construir por capas completas (toda la UI, después toda la BD, después toda la API): la sesión pierde el hilo, nada funciona hasta el final y los errores de diseño aparecen tarde. La base es construir por **bloques**: cada bloque cruza UI, datos y API, se prueba solo y queda usable. Lo que cambia según el proyecto es cuánto se define antes de empezar.

**Quien decide es el usuario.** La IA recomienda un método y dice por qué, pero muestra las otras opciones, el usuario escoge (aunque no sea la recomendada) y puede cambiar de método cuando quiera. La IA nunca impone un método ni sigue uno que el usuario no aprobó.

## Pasos

1. **Si existe `docs/METODO.md`, léelo y síguelo.** No vuelvas a preguntar. Si el usuario pide cambiar de método, ve al paso 6. Si ves que el proyecto cambió de fase (por ejemplo, el spike ya validó la idea), sugiérelo en una línea; el cambio lo decide el usuario.

2. **Averigua lo que falte.** Primero mira el repo (¿hay código?, ¿hay `docs/`?). Pregunta solo lo que no puedas deducir, en un solo mensaje:
   - ¿La idea está clara o todavía se está descubriendo?
   - ¿Hay un cliente con alcance cerrado o una norma externa (facturación fiscal, pagos, ministerio)?
   - ¿Hay código existente con patrones que seguir?
   - ¿Cuántos flujos de usuario tiene la primera versión?
   - ¿Cuántas personas van a trabajar en el código? ¿Hay alguna parte con carga o tecnología muy distinta al resto (búsqueda, tiempo real, procesamiento pesado)? Solo si hace falta para decidir la arquitectura (ver abajo).

3. **Recomienda un método de esta tabla.** Tu recomendación va primero y con argumentos, no como una lista neutral.

| Situación | Método | Por qué |
|---|---|---|
| Idea incierta | **Spike** de 1 a 3 días que se bota, luego definición de una página y bloques delgados | Escribir specs largas de algo que va a cambiar es tiempo perdido. Primero se aprende. |
| Requisitos claros, proyecto nuevo | **Definición completa → Bloque 0 → bloques con puerta** (skill `desarrollo-por-etapas`) | La definición sí paga aquí, pero se construye por bloques para ver avance y verificar cada paso. |
| Feature en un sistema que ya existe | **Un bloque** con la versión corta de `desarrollo-por-etapas` | El esqueleto ya existe: se siguen sus patrones. |
| Feature grande que toca muchos módulos | **Entrevista → `SPEC.md` de una página → partir en bloques** | Spec liviano: un archivo, no veinte. |
| Alcance cerrado por contrato o por una norma | **Definición y contrato de datos casi en cascada; implementación por bloques** | El alcance no se descubre sobre la marcha, pero construir por capas igual es mala idea con IA. |
| Bug | **Reproducir → test en rojo → causa raíz → fix** | Ver la versión para bugs en `desarrollo-por-etapas`. |

   **Arquitectura.** Junto con el método, di en una línea qué arquitectura recomiendas. Por defecto es un **monolito modular** (skill `fullstack`). Si hay dos o más señales de la skill `microservicios` (equipos que se pisan, un área con carga o tecnología muy distinta, despliegues independientes, aislar fallas como requisito), ofrece microservicios como opción y usa esa skill para el diseño. Si el usuario pide microservicios sin esas señales, dile el costo en corto: la decisión es suya. La arquitectura también la escoge el usuario y se anota en `docs/METODO.md`.

4. **Presenta la decisión al usuario** en un solo mensaje:
   - **Recomendado:** el método, 2 pros y 2 contras para ESTE proyecto (no genéricos).
   - **Otras opciones:** las 1 o 2 alternativas que también tienen sentido aquí, una línea cada una con cuándo convendrían más.
   - La pregunta: "¿Seguimos con el recomendado o prefieres otro?". El usuario también puede proponer su propia forma de trabajar.

   No escribas código ni `docs/METODO.md` hasta que el usuario escoja.

5. **Escribe `docs/METODO.md`** con el método que el usuario escogió, sea o no el recomendado, usando la plantilla de abajo. Si escogió otro, anota tu recomendación y su motivo en una línea, sin insistir. Sigue con `desarrollo-por-etapas`. Si es un spike, la regla del spike va en el archivo: se bota, no se convierte en producción.

6. **Cambiar de método después.** El usuario puede cambiarlo en cualquier momento ("ya no quiero bloques", "el spike ya validó la idea"). Entonces:
   - Di en corto qué implica el cambio para lo que ya está hecho (por ejemplo, qué bloques quedan a medias).
   - Actualiza `docs/METODO.md`: el método nuevo arriba y una línea en "Historial de cambios" con fecha, de qué a qué y por qué.
   - Ajusta `docs/ETAPAS.md` si la lista de bloques o la etapa actual cambian.

## Cómo partir en bloques

- Un bloque es **un flujo que un usuario puede completar**: "iniciar sesión", "registrar estudiante", "cobrar una factura". "Módulo académico" no es un bloque.
- Para encontrar los bloques, escribe primero los escenarios en una línea: "la contadora necesita ver los ingresos del mes para cuadrar con el banco". Cada escenario (o grupo pequeño) es un bloque. El detalle de cada escenario se escribe en C1 de `desarrollo-por-etapas`, cuando le toca a ese bloque, no todos al principio.
- Si no se puede probar con un e2e de un flujo, es muy grande: pártelo.
- **Bloque 0 siempre primero**: repo, auth base, usuario, permisos, multi-tenant si aplica, base de datos, CI, deploy y un dato que viaje de la BD a una pantalla. Deja un módulo de ejemplo que los demás bloques copien.
- Ordena por dependencias y luego por riesgo: lo más incierto va temprano.
- Cada 3 o 4 bloques, una ronda de limpieza: `/mapa-bloque` sobre lo construido y refactor de lo que salga.

## Plantilla de docs/METODO.md

```md
# Método — <proyecto>

Decidido: <fecha>
Método: <spike | bloques con definición completa | bloque único | spec corto + bloques | definición cerrada + bloques | otro que propuso el usuario>
Arquitectura: <monolito modular | monolito modular listo para extraer | microservicios (ver docs/ARQUITECTURA.md)>
Escogido por: el usuario (recomendado por la IA: <sí | no, recomendó X porque ...>)
Por qué: <2 o 3 líneas con lo que respondió el usuario>
Alternativas consideradas: <las otras opciones que se mostraron>

## Bloques planeados (el avance se lleva en docs/ETAPAS.md)
| # | Bloque | Escenario en una línea | Depende de | Carpeta |
|---|--------|------------------------|------------|---------|
| 0 | Esqueleto | — | — | — |
| 1 | ... | <quién> necesita <qué> para <para qué> | 0 | src/... |

## Reglas transversales (las verifica cada puerta)
- Permisos: ...
- Multi-tenant: ...
- Auditoría: ...

## Cuándo revisar este método
- <por ejemplo: cuando el spike responda X>

## Historial de cambios
| Fecha | De | A | Por qué |
|-------|----|---|---------|
```
