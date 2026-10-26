---
name: mapa-bloque
description: Genera un mapa interactivo de un bloque de código TypeScript (archivos, conexiones, variables y exports sin usar, ciclos). Solo cuando el usuario lo pida con /mapa-bloque.
disable-model-invocation: true
argument-hint: "<bloque o carpeta> [qué quieres estudiar]"
---

# Mapa de un bloque

El usuario quiere estudiar un bloque del proyecto: $ARGUMENTS

Los datos del mapa salen del compilador de TypeScript, no de ti. Tu trabajo es correr el script, leer el resultado y explicarlo. No inventes conexiones ni problemas que el JSON no diga.

## Pasos

1. **Ubica la carpeta del bloque.** Si el usuario dio un nombre ("login", "matrícula") y no una ruta, búscala con Glob (por ejemplo `**/auth/`, `**/login/`). Si hay varias candidatas, pregunta cuál. Si el proyecto tiene `docs/METODO.md`, ahí está la carpeta de cada bloque.

2. **Corre el script** (está en la carpeta `scripts/` de esta skill):

   ```bash
   node <carpeta-de-esta-skill>/scripts/mapa-bloque.mjs <carpeta-del-bloque> --nombre <bloque>
   ```

   Opciones: `--salida <dir>` (por defecto `docs/mapas/` junto al `tsconfig.json`) y `--sin-tests`.
   Si dice que falta el motor, corre el comando `pnpm install` que imprime y repite.

3. **Lee `docs/mapas/<bloque>.json`**, no el HTML. Fíjate en `resumen` y en los `problemas` de cada nodo.

4. **Responde corto:**
   - Una línea con el resumen: archivos, conexiones y cuántos problemas.
   - Los problemas que importan, con `archivo:línea`, en este orden: ciclos, variables sin usar, exports sin usar, archivos huérfanos, solo en tests.
   - Si el usuario preguntó algo concreto ("¿qué usa el servicio?", "¿quién llama al DTO?"), contéstalo con `aristas` y `declaraciones`.
   - La ruta del HTML para que lo abra en el navegador.

5. **No borres nada sin permiso.** Ofrece limpiar lo que esté sin usar; espera el sí.

## Qué significa cada problema

| Tipo | Qué es | Cuidado con |
|---|---|---|
| `sin-usar` | Variable, import, parámetro o propiedad privada que se declara y nunca se lee (TS6133 y similares) | Parámetros que exige una firma (guards, interceptores): se prefijan con `_` en vez de borrarlos |
| `export-sin-usar` | Se exporta, pero ningún archivo del `tsconfig` lo importa | Lo puede usar otra app del monorepo con otro `tsconfig`, o un framework por nombre |
| `huerfano` | Nadie importa el archivo | Entradas que el script no conoce (CLI, workers, seeds) |
| `solo-tests` | Solo lo importan los tests | Normal en helpers de test; raro en código de producción |
| `ciclo` | Imports circulares entre archivos del bloque | En NestJS suele terminar en `forwardRef`; casi siempre es mejor mover lo compartido |
| `error-ts` | Error de compilación | El análisis puede salir incompleto hasta corregirlo |

Las entradas de Next.js (`page`, `layout`, `route`, `middleware`…) y `main.ts` no cuentan como huérfanas, y sus exports reservados (`default`, `metadata`, `GET`…) salen como `framework`.

## Limitaciones

- Solo TypeScript y JavaScript. Usa su propio TypeScript 6 porque TypeScript 7 ya no trae la API que necesita.
- Un uso por `import *` o `export *` cuenta como uso de todo el archivo.
- Lo que se resuelve en tiempo de ejecución (inyección de dependencias por string, `require` dinámico) no se ve.

## Si el usuario lo quiere más vistoso

El HTML ya es interactivo y funciona sin internet. Si además pide un diagrama de arquitectura de presentación y tiene instalada la skill `archify`, pásale `docs/mapas/<bloque>.json` como fuente y pídele que use solo esos nodos y aristas, sin agregar nada.
