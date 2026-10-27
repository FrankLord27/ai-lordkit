---
name: blindar
description: Auditoría de seguridad del código propio. Obligatoria al cerrar cada bloque o módulo (puerta C5 de desarrollo-por-etapas); completa de 12 fases con /blindar todo cuando el proyecto está avanzado o antes de producción. Revisa validación de inputs, rate limit por usuario e IP, errores que filtran info, tokens y sesiones, CORS y rutas sin auth; reporta con archivo:línea, corrige y lo prueba.
argument-hint: "[bloque | carpeta | todo]"
---

# Blindar

Alcance pedido: $ARGUMENTS

No se queda en recomendaciones: investiga el código real, demuestra cada hallazgo con `archivo:línea`, lo corrige sin romper la app, lo prueba y entrega un informe verificable.

## Dos alcances

| | Cierre de bloque (`/blindar`, `/blindar <bloque>`) | Auditoría completa (`/blindar todo`) |
|---|---|---|
| Cuándo | **Obligatorio** al cerrar cada bloque o módulo (C5 de `desarrollo-por-etapas`) | Etapa D. Endurecimiento, proyecto avanzado o terminado, antes de producción |
| Qué se lee | Lo que cambió en el bloque (`git diff --name-only <base>...HEAD` o la carpeta) + lo global: `main.ts`, `app.module.ts`, `proxy.ts`/`middleware.ts`, config de auth y CORS | Todo el repositorio |
| Qué se revisa | Los 6 chequeos sobre esas rutas, inputs y auth → `references/chequeos.md` | Las 12 fases → `references/auditoria-completa.md` (incluye los 6 chequeos) |
| Puerta | Bloque cerrado solo con 0 críticos y 0 altos abiertos | Evaluación final: NO APTO / APTO CON RESERVAS / SIN HALLAZGOS CRÍTICOS PENDIENTES EN EL ALCANCE AUDITADO |

Sin argumento: el bloque actual de `docs/ETAPAS.md`; si no hay, lo que cambió desde `main`. Lee solo el archivo de referencia que toca.

## Profundidad según el modo

El modo activo (`/output-style`) decide cuánto se lee y cómo se reporta. Sin modo, intermedio. **Los chequeos de seguridad no se saltan en ningún modo.**

| | Ahorro | Intermedio | Completo |
|---|---|---|---|
| Lectura | Grep primero; solo lo que el grep marca y su flujo | Archivos del alcance + lo global | Todo el alcance y lo que importa |
| Reporte | Críticos y altos, una línea cada uno; medios y bajos como conteo | Todos los hallazgos | Todos, con escenario de explotación |
| Corrige | Críticos y altos | Críticos, altos y medios | Todo lo seguro de corregir |
| Pruebas | Un test por arreglo | Un test por arreglo + suite | Tests positivos y negativos + suite |
| Segunda pasada | No | No | Sí: revisa de nuevo lo que cambió (con `security-auditor` si hay agents) |

## Procedimiento

1. **Estado**: `git status`. Respeta los cambios que ya había; no los pises ni los reviertas.
2. **Mapa**: stack, auth, puntos de entrada e inventario de rutas del alcance. Variables solo desde `.env.example`.
3. **Revisar**: los chequeos o las fases que tocan, siguiendo cada dato desde la entrada hasta la respuesta. Un grep no es un hallazgo; un hallazgo sin código o prueba que lo respalde, tampoco.
4. **Resumen inicial**: los riesgos principales en pocas líneas, antes de tocar código.
5. **Corregir**: en orden de severidad, dentro del mecanismo que ya existe. Pide el OK antes de: cambiar el mecanismo de auth, agregar una dependencia, crear una migración, cambiar un contrato de API o algo que el usuario va a notar (sesiones más cortas, un 429 nuevo). Lo demás se corrige directo.
6. **Probar**: test por arreglo con las herramientas del proyecto; corre la suite. Lo que no se pudo correr se dice con su motivo.
7. **Informe** con el formato de `references/informe.md`, en `docs/seguridad/`.
8. **Registrar** en `docs/ETAPAS.md`, en la evidencia del bloque: link al informe y "blindar: N críticos, N altos abiertos".

Severidad: **crítico** = explotable hoy sin credenciales o con cualquier usuario. **Alto** = explotable con condiciones razonables. **Medio** = debilita una defensa. **Bajo** = endurecimiento extra. No infles ni bajes severidades.

## Qué no duplica

| Herramienta | Qué hace | Relación |
|---|---|---|
| Plugin `security-guidance` | Avisa de patrones inseguros mientras se edita | Complementa: es en el momento; blindar es al cerrar |
| `nestjs-security-hardening` | Estándar y código de referencia NestJS | Blindar lo usa para corregir: cita su sección, no reescribe distinto |
| `/brechas` (si está instalada) | Dependencias: CVEs, paquetes maliciosos | La auditoría completa le delega la parte de dependencias |
| Agent `security-auditor` | Auditoría OWASP con contexto limpio | Hace la segunda pasada en modo completo |

## Reglas

1. No asumas que algo es seguro porque usa un framework moderno o una librería de auth.
2. No inventes hallazgos. Si no lo puedes confirmar leyendo el código, es "requiere revisión", con qué habría que mirar.
3. No digas que un test pasó si no lo corriste y viste el resultado.
4. Nunca declares la app "segura". Di qué se revisó, qué se corrigió y qué falta.
5. Nada destructivo: ni producción, ni datos reales, ni sistemas externos, ni migraciones destructivas.
6. No quites funcionalidad ni desactives auth, CORS o validaciones para que algo pase.
7. Nunca leas `.env` reales ni llaves. Un secreto en el código se reporta sin mostrar su valor. No metas secretos nuevos en el código.
8. Describe el riesgo; no escribas exploits funcionales.
9. Si dudas de la API de una librería, consulta Context7 antes de corregir.
10. Bugs que no son de seguridad: una línea al final, sin arreglarlos.
