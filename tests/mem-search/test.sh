#!/usr/bin/env bash
# Tests de skills/mem-search/scripts/mem-search.sh contra un historial falso
# con el mismo formato que Claude Code escribe en ~/.claude/projects/.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../../skills/mem-search/scripts/mem-search.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export CLAUDE_CONFIG_DIR="$tmp"

erp="$tmp/projects/-srv-erp"
web="$tmp/projects/-srv-tienda"
mkdir -p "$erp" "$web"

cat > "$erp/aaaa1111.jsonl" <<'JSONL'
{"type":"user","sessionId":"aaaa1111","cwd":"/srv/erp","timestamp":"2026-10-20T10:00:00.000Z","message":{"role":"user","content":"¿Cómo aislamos el tenantId en Prisma?"}}
{"type":"assistant","sessionId":"aaaa1111","cwd":"/srv/erp","timestamp":"2026-10-20T10:00:05.000Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"tenantId secreto del razonamiento"},{"type":"text","text":"Usa una extensión de Prisma que inyecte el tenantId en cada query."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"echo tenantId"}}]}}
{"type":"user","sessionId":"aaaa1111","cwd":"/srv/erp","timestamp":"2026-10-20T10:00:06.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"TOKEN_FALSO tenantId"}]}}
{"type":"user","isMeta":true,"sessionId":"aaaa1111","cwd":"/srv/erp","timestamp":"2026-10-20T10:00:07.000Z","message":{"role":"user","content":"<system-reminder>tenantId meta</system-reminder>"}}
{"type":"assistant","isSidechain":true,"sessionId":"aaaa1111","cwd":"/srv/erp","timestamp":"2026-10-20T10:00:08.000Z","message":{"role":"assistant","content":[{"type":"text","text":"tenantId desde un subagent"}]}}
{"type":"user","sessionId":"aaaa1111","cwd":"/srv/erp","timestamp":"2026-10-20T10:01
JSONL

cat > "$web/bbbb2222.jsonl" <<'JSONL'
{"type":"user","sessionId":"bbbb2222","cwd":"/srv/tienda","timestamp":"2026-10-25T09:00:00.000Z","message":{"role":"user","content":"Decidimos usar MinIO para las fotos de los productos"}}
JSONL

fail=0
check() { # check <descripción> <salida> <texto esperado> [no]
  if [ "${4:-}" = no ]; then
    if grep -qF -- "$3" <<<"$2"; then echo "FALLA: $1 (no debía salir '$3')"; fail=1; else echo "ok: $1"; fi
  else
    if grep -qF -- "$3" <<<"$2"; then echo "ok: $1"; else echo "FALLA: $1 (falta '$3')"; echo "$2"; fail=1; fi
  fi
}

out="$("$S" tenantid)"
check "encuentra el mensaje del usuario sin distinguir mayúsculas" "$out" "aislamos el tenantId"
check "encuentra el texto de Claude" "$out" "extensión de Prisma"
check "marca quién habló" "$out" "[tú]"
check "ignora tool_result" "$out" "TOKEN_FALSO" no
check "ignora thinking" "$out" "razonamiento" no
check "ignora tool_use" "$out" "echo tenantId" no
check "ignora mensajes meta" "$out" "tenantId meta" no
check "ignora subagents" "$out" "desde un subagent" no
check "aguanta una línea cortada al final" "$out" "2 de 2 coincidencias"
check "muestra el id de sesión" "$out" "sesión aaaa1111"

out="$("$S" -p tienda "minio|tenant")"
check "-p filtra por proyecto" "$out" "fotos de los productos"
check "-p deja fuera otros proyectos" "$out" "tenantId" no

out="$("$S" -n 1 "minio|tenantid")"
check "-n limita y ordena por lo más reciente" "$out" "MinIO"
check "-n reporta el total" "$out" "1 de 3 coincidencias"

out="$("$S" -c 5 "Prisma que")"
check "-c recorta el contexto" "$out" "…n de Prisma que inye…"

out="$("$S" nadaquever)"
check "sin resultados no falla" "$out" "Sin resultados"

if "$S" "(" >/dev/null 2>&1; then echo "FALLA: regex inválida debía fallar"; fail=1; else echo "ok: regex inválida sale con error"; fi
if "$S" -n x foo >/dev/null 2>&1; then echo "FALLA: -n no numérico debía fallar"; fail=1; else echo "ok: valida -n"; fi

exit $fail
