#!/usr/bin/env bash
# mem-search: busca en el historial de sesiones de Claude Code
# (~/.claude/projects/<proyecto>/<sesión>.jsonl). Solo mira lo que escribiste tú y
# lo que respondió Claude: ignora resultados de tools (pueden traer datos sensibles) y thinking.
# Sin dependencias aparte de jq. Compatible con bash 3.2 (macOS).
set -euo pipefail
# Windows (Git Bash): jq.exe termina las líneas en CRLF; se quita el \r para que `read` y las comparaciones no fallen.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; } ;; esac

usage() {
  cat <<'USO'
Uso: mem-search.sh [-p proyecto] [-d días] [-n máx] [-c chars] <patrón>
  patrón  regex, sin distinguir mayúsculas (ej: "multi.?tenant|tenantId")
  -p      solo proyectos cuya carpeta contenga este texto (ej: erp, tienda)
  -d      solo sesiones modificadas en los últimos N días
  -n      máximo de resultados, los más recientes primero (default 20)
  -c      caracteres de contexto a cada lado del match (default 160)
USO
}

proj="" days="" max=20 ctx=160
while getopts "p:d:n:c:h" o; do
  case "$o" in
    p) proj=$OPTARG ;;
    d) days=$OPTARG ;;
    n) max=$OPTARG ;;
    c) ctx=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { usage >&2; exit 2; }
pattern="$*"

for n in "$max" "$ctx" ${days:+"$days"}; do
  case "$n" in ''|*[!0-9]*) echo "mem-search: -n, -c y -d deben ser números" >&2; exit 2 ;; esac
done
command -v jq >/dev/null || { echo "mem-search: falta jq (./install.sh deps)" >&2; exit 1; }
jq -n --arg re "$pattern" '"" | test($re; "i")' >/dev/null 2>&1 \
  || { echo "mem-search: regex inválida: $pattern" >&2; exit 2; }

root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
[ -d "$root" ] || { echo "Sin historial en $root"; exit 0; }

# 1. Candidatos: filtro de texto rápido sobre los .jsonl (rg si está, si no grep).
set -- "$root" -type f -name '*.jsonl'
[ -n "$proj" ] && set -- "$@" -ipath "*${proj}*"
[ -n "$days" ] && set -- "$@" -mtime "-${days}"
if command -v rg >/dev/null; then
  grep_l() { xargs -0 rg -l -i -e "$pattern" -- 2>/dev/null || true; }
else
  grep_l() { xargs -0 grep -l -i -E -e "$pattern" -- 2>/dev/null || true; }
fi
files=$(find "$@" -print0 2>/dev/null | grep_l)
[ -n "$files" ] || { echo "Sin resultados para: $pattern"; exit 0; }

# 2. Extrae solo el texto de usuario/Claude que hace match, con un recorte alrededor.
#    fromjson? salta líneas a medio escribir de la sesión en curso.
hits=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 jq -R -r --arg re "$pattern" --argjson ctx "$ctx" '
  fromjson? // empty
  | select((.type == "user" or .type == "assistant") and (.isMeta | not) and (.isSidechain | not))
  | (.message.content // "") as $c
  | (if ($c | type) == "string" then $c
     else ([$c[]? | select(.type == "text") | .text] | join("\n")) end) as $t
  | select($t != "" and ($t | test($re; "i")))
  | ($t | match($re; "i")) as $m
  | ([$m.offset - $ctx, 0] | max) as $a
  | ($m.offset + $m.length + $ctx) as $b
  | ((if $a > 0 then "…" else "" end) + $t[$a:$b] + (if $b < ($t | length) then "…" else "" end)
     | gsub("\\s+"; " ")) as $snip
  | [(.timestamp // "")[0:16], (.cwd // "?"), (.sessionId // "?"),
     (if .type == "user" then "tú" else "claude" end), $snip]
  | @tsv' 2>/dev/null || true)
[ -n "$hits" ] || { echo "Sin resultados para: $pattern"; exit 0; }

total=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
tab="$(printf '\t')"
printf '%s\n' "$hits" | sort -r | head -n "$max" | while IFS="$tab" read -r ts cwd sid who snip; do
  printf '%s  %s  [%s]  sesión %s\n  %s\n\n' "${ts/T/ }" "${cwd/#"$HOME"/\~}" "$who" "$sid" "$snip"
done
shown=$(( total < max ? total : max ))
echo "$shown de $total coincidencias. Para retomar una: claude --resume <sesión>"
