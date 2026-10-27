---
name: brechas
description: Cruza las dependencias del proyecto (pnpm-lock.yaml o package-lock.json), los servidores MCP y la versión de Claude Code con avisos públicos de seguridad (OSV.dev con GitHub Advisory Database y paquetes maliciosos, CISA KEV, EPSS) y deja un reporte con links en docs/seguridad/. Úsala cuando pidan revisar brechas, CVEs, vulnerabilidades o paquetes maliciosos en las dependencias, y cuando blindar delegue la parte de dependencias.
argument-hint: "[carpeta] [noticias]"
---

# Brechas

Pedido: $ARGUMENTS

Los datos salen de las fuentes, no de ti. Corres el script, lees el JSON y explicas. No inventes avisos, versiones arregladas ni puntajes que el JSON no diga.

## Pasos

1. **Carpeta:** la que te dieron, o la raíz del proyecto (donde está `pnpm-lock.yaml`). En un monorepo, la raíz: el lockfile es uno solo.

2. **Corre el script:**

   ```bash
   ~/.claude/skills/brechas/scripts/brechas.mjs <carpeta>
   ```

   Opciones: `--salida <dir>` (por defecto `docs/seguridad/`), `--excluir <nombre o @scope/*>` (repetible), `--sin-mcp`, `--sin-claude`, `--json`.

   Código de salida: `0` sin críticos ni altos, `1` hay críticos o altos, `2` no encontró lockfile o error de uso, `3` alguna fuente falló y el reporte está incompleto.

3. **Lee `docs/seguridad/brechas-<fecha>.json`**, no el Markdown.

4. **Responde corto:**
   - Una línea: cuántas versiones revisó y cuántos hallazgos por nivel.
   - Si `fallas` no está vacío, dilo primero: el reporte está incompleto y por qué.
   - Cada crítico y cada alto: aviso, paquete, tu versión, versión que lo arregla y por qué es grave.
   - Medios y bajos como conteo, salvo que pidan el detalle.
   - La ruta del Markdown.

5. **Propón el arreglo, no lo apliques sin OK:**
   - Dependencia directa: `pnpm up <paquete>@<arreglo>` y correr la suite.
   - Transitiva: `pnpm why <paquete>` para ver quién la trae; primero subir el padre. Si no hay versión del padre que la arregle, `pnpm.overrides` en el `package.json` raíz, con un comentario en el PR de por qué.
   - **Paquete malicioso (`MAL-*`):** es urgente. Quitarlo, borrar `node_modules` y reinstalar desde el lockfile corregido, y tratar como expuestos los secretos de la máquina y del CI donde se instaló (rotarlos). Avísale al usuario antes de cualquier otra cosa.
   - Sin versión arreglada: dilo. Opciones: cambiar de paquete, aislar el uso o aceptar el riesgo en `.brechas-ignorar`.

## Niveles

| Nivel | Cuándo |
|---|---|
| Crítico | Paquete malicioso (`MAL-*`) o CVE en CISA KEV (se está explotando) |
| Alto | Severidad HIGH o CRITICAL, o EPSS ≥ 10% |
| Medio | Severidad MODERATE |
| Bajo | Severidad LOW o sin dato |

## Riesgo aceptado

`.brechas-ignorar` en la raíz del proyecto, un aviso por línea con su motivo:

```
GHSA-xxxx-xxxx-xxxx  # solo se usa en el seed de desarrollo, no llega a producción
```

Lo ignorado sale aparte en el reporte, no desaparece. Un `MAL-*` nunca se puede ignorar.

## Noticias (solo si piden `noticias`)

Aparte del reporte, busca con WebSearch incidentes de los últimos 30 días sobre: servidores MCP maliciosos o vulnerables, prompt injection contra agentes de código, ataques de supply chain en npm, y avisos de Claude Code.

- Cada noticia con fecha y link a la fuente. Sin link, no sale.
- Si nombra un paquete, búscalo en el JSON del reporte (o en el lockfile) y di si el proyecto lo usa.
- Ponlas en una sección "Noticias" separada y dilo claro: son noticias, no hallazgos verificados contra el proyecto.

## Qué sale de la máquina

Solo nombres y versiones de paquetes públicos hacia OSV.dev, y los CVE encontrados hacia FIRST.org (EPSS). Los paquetes del propio proyecto (cualquier `name` de un `package.json` del repo) y los que pases con `--excluir` no se consultan. De los archivos MCP solo se leen `command` y `args`; nunca `env` ni `headers`.

## Limitaciones

- Solo npm: `pnpm-lock.yaml` (v5, v6 y v9) y `package-lock.json` (v2 y v3). `yarn.lock` y `bun.lock` todavía no.
- Revisa todo el lockfile, sin separar dependencias de desarrollo y de producción.
- Los MCP que se ven son los de `.mcp.json` del proyecto, `mcp/servers.json` del kit y `mcp.json` de la capa privada. Los que agregaste a mano con `claude mcp add` no.
- Detrás de un proxy corporativo, corre con `NODE_USE_ENV_PROXY=1` (Node 24.5 o más nuevo).
- La cache vive en `~/.cache/ai-lordkit/brechas/` (KEV por 24 horas; cada aviso hasta que OSV lo modifique).
- "Sin hallazgos" significa sin avisos publicados hoy, no que el código sea seguro.

## Hook opcional: supply-guard

`hooks/supply-guard.sh` revisa antes de que Claude corra `pnpm add`, `npm install`, `yarn add`, `npx`, `pnpm dlx` o `bunx`:

- Versión marcada como maliciosa en OSV → bloquea.
- Versión publicada hace menos de 7 días → pide confirmación (`AI_LORDKIT_SUPPLY_DAYS` cambia los días).
- Sin red, sin `jq` o sin `curl` → deja pasar; `minimumReleaseAge` de pnpm sigue protegiendo.

Viene apagado. Se activa con `"env": { "AI_LORDKIT_SUPPLY_GUARD": "1" }` en `settings.json` (mejor en tu capa privada).
