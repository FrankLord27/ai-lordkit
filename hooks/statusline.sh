#!/usr/bin/env bash
# Línea de estado de Claude Code: modelo · modo/effort · carpeta · rama · costo.
# Claude Code le pasa un JSON por stdin; sin jq muestra solo la carpeta y la rama.
# El costo es una estimación a precio de lista (sirve para comparar modos, no es tu factura).

input=$(cat)
# Windows (Git Bash): jq.exe termina las líneas en CRLF; se quita el \r para que `read` y las comparaciones no fallen.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; } ;; esac
if command -v jq >/dev/null 2>&1; then
  IFS=$'\x1f' read -r model style effort dir cost < <(jq -r '[
      (.model.display_name // ""),
      (.output_style.name // ""),
      (.effort.level // ""),
      (.workspace.current_dir // .cwd // ""),
      (.cost.total_cost_usd // "" | if . == "" then "" else (. * 100 | round / 100 | tostring) end)
    ] | join("\u001f")' <<<"$input" 2>/dev/null)
fi
dir="${dir:-$PWD}"
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)

[[ "$style" == default ]] && style=""
mode="${style}${style:+${effort:+/}}${effort}"

out="${model:+$model · }${mode:+$mode · }$(basename "$dir")"
[[ -n "$branch" ]] && out="$out · $branch"
[[ -n "$cost" ]] && out="$out · \$$cost"
printf '%s' "$out"
