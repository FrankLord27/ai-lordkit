#!/usr/bin/env bash
# Prueba de mapa-bloque: corre el script sobre el proyecto de ejemplo y compara el resumen.
# Requiere: node y las dependencias de skills/mapa-bloque/scripts (pnpm install ahí).
set -euo pipefail
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
SALIDA="$(mktemp -d)"
trap 'rm -rf "$SALIDA"' EXIT

node "$RAIZ/skills/mapa-bloque/scripts/mapa-bloque.mjs" "$RAIZ/tests/mapa-bloque/proyecto/src/auth" --salida "$SALIDA" >/dev/null

esperado='{"archivos":7,"sinUsar":1,"exportsSinUsar":2,"soloTests":1,"huerfanos":1,"ciclos":1,"erroresTs":0}'
obtenido="$(node -e '
  const r = require(process.argv[1]).resumen;
  const k = ["archivos","sinUsar","exportsSinUsar","soloTests","huerfanos","ciclos","erroresTs"];
  console.log(JSON.stringify(Object.fromEntries(k.map((x) => [x, r[x]]))));
' "$SALIDA/auth.json")"

if [[ "$obtenido" != "$esperado" ]]; then
  echo "✗ mapa-bloque: resumen distinto"
  echo "  esperado: $esperado"
  echo "  obtenido: $obtenido"
  exit 1
fi
for f in auth.html auth.json auth.md; do
  [[ -s "$SALIDA/$f" ]] || { echo "✗ mapa-bloque: falta $f"; exit 1; }
done
grep -qF 'intentos\" se declara pero nunca se usa' "$SALIDA/auth.json" || { echo "✗ no detectó la variable sin usar"; exit 1; }
echo "✓ mapa-bloque: $obtenido"
