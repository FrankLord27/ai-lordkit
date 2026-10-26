---
name: mem-search
description: >
  Busca en el historial de sesiones anteriores de Claude Code (lo que dijo el usuario y lo
  que respondió Claude) sin gastar tokens hasta que se usa. Úsala cuando el usuario pregunte
  por algo de una sesión pasada ("¿qué decidimos de X?", "¿cómo arreglamos Y la otra vez?",
  "ya habíamos hablado de esto") y la memoria automática (MEMORY.md) no lo tenga.
---

# mem-search

Busca en `~/.claude/projects/*/*.jsonl`, que es donde Claude Code guarda cada sesión.
Solo lee los mensajes del usuario y el texto de Claude. Deja fuera los resultados de
tools, el thinking y los subagents, así no aparecen datos sensibles ni ruido.

## Cuándo

1. Primero revisa la memoria automática del proyecto, que ya está en tu contexto (`MEMORY.md`).
2. Si ahí no está, usa este script **antes** de decir "no sé" o de preguntarle de nuevo al usuario.

## Cómo

```bash
~/.claude/skills/mem-search/scripts/mem-search.sh [-p proyecto] [-d días] [-n máx] [-c chars] "<regex>"
```

- `-p erp`: solo proyectos cuya carpeta contenga "erp". Úsalo casi siempre con el nombre del repo actual.
- `-d 30`: solo sesiones de los últimos 30 días.
- `-n 10`: cuántos resultados mostrar. Salen los más recientes primero (default 20).
- `-c 300`: más contexto alrededor del match (default 160).

El patrón es una regex que no distingue mayúsculas. Si no te sale nada, prueba con sinónimos y
variantes en el mismo patrón: `"multi.?tenant|tenantId|aislamiento"`.

Cada resultado trae la fecha, la carpeta del proyecto, quién habló (`tú` o `claude`), el id de
la sesión y un recorte del texto. Para ver la conversación completa, el usuario puede correr
`claude --resume <sesión>` desde esa carpeta.

## Reglas

- Resume lo que encontraste con la fecha. No pegues los recortes completos.
- Si encontraste algo que vale para sesiones futuras (una decisión, una convención), guárdalo
  en la memoria automática para que no haga falta buscarlo otra vez.
- Las sesiones duran lo que diga `cleanupPeriodDays` en `settings.json` (el kit lo pone en 365 días).
