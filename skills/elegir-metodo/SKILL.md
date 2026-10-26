---
name: elegir-metodo
description: Úsala al arrancar un proyecto nuevo, un módulo o una feature grande, o cuando el usuario pregunte cómo organizar el trabajo. Propone UN método (spike, bloques, spec corto o definición fuerte) según qué tan clara está la idea, y lo deja en docs/METODO.md.
---

# Elegir el método de trabajo

Con IA no conviene construir por capas completas (toda la UI, después toda la BD, después toda la API): la sesión pierde el hilo, nada funciona hasta el final y los errores de diseño aparecen tarde. La base es construir por **bloques**: cada bloque cruza UI, datos y API, se prueba solo y queda usable. Lo que cambia según el proyecto es cuánto se define antes de empezar.

## Pasos

1. **Si existe `docs/METODO.md`, léelo y síguelo.** No vuelvas a preguntar. Solo propón cambiarlo si el proyecto cambió de fase (por ejemplo, el spike ya validó la idea).

2. **Averigua lo que falte.** Primero mira el repo (¿hay código?, ¿hay `docs/`?). Pregunta solo lo que no puedas deducir, en un solo mensaje:
   - ¿La idea está clara o todavía se está descubriendo?
   - ¿Hay un cliente con alcance cerrado o una norma externa (facturación fiscal, pagos, ministerio)?
   - ¿Hay código existente con patrones que seguir?
   - ¿Cuántos flujos de usuario tiene la primera versión?

3. **Recomienda UN método de esta tabla.** No des una lista neutral.

| Situación | Método | Por qué |
|---|---|---|
| Idea incierta | **Spike** de 1 a 3 días que se bota, luego definición de una página y bloques delgados | Escribir specs largas de algo que va a cambiar es tiempo perdido. Primero se aprende. |
| Requisitos claros, proyecto nuevo | **Definición completa → Bloque 0 → bloques con puerta** (skill `desarrollo-por-etapas`) | La definición sí paga aquí, pero se construye por bloques para ver avance y verificar cada paso. |
| Feature en un sistema que ya existe | **Un bloque** con la versión corta de `desarrollo-por-etapas` | El esqueleto ya existe: se siguen sus patrones. |
| Feature grande que toca muchos módulos | **Entrevista → `SPEC.md` de una página → partir en bloques** | Spec liviano: un archivo, no veinte. |
| Alcance cerrado por contrato o por una norma | **Definición y contrato de datos casi en cascada; implementación por bloques** | El alcance no se descubre sobre la marcha, pero construir por capas igual es mala idea con IA. |
| Bug | **Reproducir → test en rojo → causa raíz → fix** | Ver la versión para bugs en `desarrollo-por-etapas`. |

4. **Da 2 pros y 2 contras de ese método para ESTE proyecto**, no genéricos. Si dudas entre dos, di cuál escoges y por qué.

5. **Cuando el usuario acepte**, escribe `docs/METODO.md` con la plantilla de abajo y sigue con `desarrollo-por-etapas`. Si es un spike, la regla del spike va en el archivo: se bota, no se convierte en producción.

## Cómo partir en bloques

- Un bloque es **un flujo que un usuario puede completar**: "iniciar sesión", "registrar estudiante", "cobrar una factura". "Módulo académico" no es un bloque.
- Si no se puede probar con un e2e de un flujo, es muy grande: pártelo.
- **Bloque 0 siempre primero**: repo, auth base, usuario, permisos, multi-tenant si aplica, base de datos, CI, deploy y un dato que viaje de la BD a una pantalla. Deja un módulo de ejemplo que los demás bloques copien.
- Ordena por dependencias y luego por riesgo: lo más incierto va temprano.
- Cada 3 o 4 bloques, una ronda de limpieza: `/mapa-bloque` sobre lo construido y refactor de lo que salga.

## Plantilla de docs/METODO.md

```md
# Método — <proyecto>

Decidido: <fecha>
Método: <spike | bloques con definición completa | bloque único | spec corto + bloques | definición cerrada + bloques>
Por qué: <2 o 3 líneas con lo que respondió el usuario>

## Bloques planeados (el avance se lleva en docs/ETAPAS.md)
| # | Bloque | Depende de | Carpeta |
|---|--------|------------|---------|
| 0 | Esqueleto | — | — |
| 1 | ... | 0 | src/... |

## Reglas transversales (las verifica cada puerta)
- Permisos: ...
- Multi-tenant: ...
- Auditoría: ...

## Cuándo revisar este método
- <por ejemplo: cuando el spike responda X>
```
