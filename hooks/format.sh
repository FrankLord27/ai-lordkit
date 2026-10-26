#!/usr/bin/env bash
# Hook PostToolUse (Edit|Write): formatea el archivo editado con el Prettier DEL PROYECTO.
# Nunca usa `npx prettier`: en un proyecto sin Prettier eso lo descarga de npm en cada
# edición (lento y riesgo de supply chain). Si el proyecto no lo tiene instalado, no hace nada.

command -v jq >/dev/null 2>&1 || exit 0
f=$(jq -r '.tool_input.file_path // empty')
[[ -n "$f" && -f "$f" ]] || exit 0

case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.md|*.mdx|*.yml|*.yaml) ;;
  *) exit 0 ;;
esac

# Busca node_modules/.bin/prettier subiendo desde la carpeta del archivo (sirve en monorepos).
dir=$(cd "$(dirname "$f")" && pwd)
while [[ "$dir" != "/" ]]; do
  if [[ -x "$dir/node_modules/.bin/prettier" ]]; then
    "$dir/node_modules/.bin/prettier" --write --log-level silent "$f" >/dev/null 2>&1 || true
    exit 0
  fi
  [[ -e "$dir/.git" ]] && break  # no salir del repo
  dir=$(dirname "$dir")
done
exit 0
