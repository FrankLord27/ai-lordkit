#!/usr/bin/env bash
# Tests de skills/brechas (reporte) y hooks/supply-guard.sh con respuestas grabadas, sin red.
# BRECHAS_RED=1 agrega una prueba contra OSV.dev de verdad (la corre el CI).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/../.."
B="$root/skills/brechas/scripts/brechas.mjs"
H="$root/hooks/supply-guard.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export AI_LORDKIT_DIR="$tmp/sin-kit" AI_LORDKIT_PRIVATE="$tmp/sin-privado" XDG_CACHE_HOME="$tmp/cache"

fail=0
check() { # check <descripción> <texto> <esperado> [no]
  if [ "${4:-}" = no ]; then
    if grep -qF -- "$3" <<<"$2"; then echo "FALLA: $1 (no debía salir '$3')"; fail=1; else echo "ok: $1"; fi
  else
    if grep -qF -- "$3" <<<"$2"; then echo "ok: $1"; else echo "FALLA: $1 (falta '$3')"; echo "$2" | head -40; fail=1; fi
  fi
}
codigo() { # codigo <descripción> <esperado> <obtenido>
  if [ "$2" = "$3" ]; then echo "ok: $1 (exit $3)"; else echo "FALLA: $1 (exit $3, se esperaba $2)"; fail=1; fi
}

# ── brechas.mjs ────────────────────────────────────────────────────────────
cp -r "$here/fixtures" "$tmp/fx"
set +e
out="$(BRECHAS_FIXTURES="$tmp/fx" "$B" "$here/proyecto" --salida "$tmp/out" --sin-claude)"; rc=$?
set -e
md="$(cat "$tmp"/out/brechas-*.md)"
json="$(cat "$tmp"/out/brechas-*.json)"
enviado="$(cat "$tmp/fx/enviado.json")"

codigo "sale con 1 si hay críticos o altos" 1 "$rc"
check "resumen por niveles" "$out" "crítico 3 · alto 1 · medio 0 · bajo 0 · ignorados 1"
check "paquete malicioso es crítico" "$md" "[MAL-2026-0001](https://osv.dev/vulnerability/MAL-2026-0001) | \`evil-pkg\`"
check "CVE en KEV sube a crítico" "$md" "se está explotando (CISA KEV)"
check "EPSS en las razones" "$md" "EPSS 50.0%"
check "versión que lo arregla, en el rango correcto" "$md" "| 3.23.8 | 3.23.9 |"
check "alto con su arreglo" "$md" "| \`lodash\` | 4.17.20 | 4.17.21 |"
check "escapa | en las celdas" "$md" "Aviso de prueba \\| con barra"
check "MCP sin versión: solo MAL" "$md" "MAL-2026-0002"
check "MCP sin versión: no muestra avisos que no son MAL" "$md" "GHSA-old0" no
check "MCP sin versión listado como no verificado" "$md" "sin-version (some-mcp)"
check "ignorado sale aparte con su motivo" "$md" "GHSA-xvch-5gv4-984h en \`minimist@1.2.5\`: solo lo usa el script de seed"
check "un MAL no se puede ignorar" "$json" "\"motivo\": \"un MAL" no
check "dependencia de git como no verificada" "$md" "left-pad@https://codeload.github.com"
check "no envía paquetes propios del workspace" "$enviado" "@miapp/utils" no
check "no envía el nombre del proyecto" "$enviado" "mi-proyecto" no
check "envía paquetes con scope público" "$enviado" "\"@types/node\""
check "envía el MCP con versión fijada" "$enviado" "\"@x/mcp-server\",\"ecosystem\":\"npm\"},\"version\":\"2.0.0\""
check "ningún MCP remoto (http) se consulta" "$enviado" "example.com" no
check "MAL primero dentro de crítico" "$(grep -n 'MAL-2026-0001\|GHSA-aaaa' <<<"$md" | head -1)" "MAL-2026-0001"

# --excluir
set +e
BRECHAS_FIXTURES="$tmp/fx" "$B" "$here/proyecto" --salida "$tmp/out2" --sin-claude --sin-mcp --excluir 'evil-*' --excluir lodash >/dev/null; rc=$?
set -e
enviado="$(cat "$tmp/fx/enviado.json")"
check "--excluir con comodín" "$enviado" "evil-pkg" no
check "--excluir exacto" "$enviado" "lodash" no
check "--sin-mcp" "$enviado" "some-mcp" no
codigo "zod sigue crítico por KEV" 1 "$rc"

# fuente caída → reporte incompleto (exit 3 si no hay críticos ni altos)
mkdir -p "$tmp/limpio" && cp "$here/proyecto/package.json" "$tmp/limpio/"
printf "lockfileVersion: '9.0'\n\npackages:\n\n  zod@3.23.8:\n    resolution: {integrity: x}\n" > "$tmp/limpio/pnpm-lock.yaml"
rm "$tmp/fx/kev.json" "$tmp/fx/epss.json"  # sin EPSS, el aviso de zod queda en medio
set +e
out="$(BRECHAS_FIXTURES="$tmp/fx" "$B" "$tmp/limpio" --sin-claude --sin-mcp)"; rc=$?
set -e
check "avisa que KEV falló" "$out" "FUENTE FALLÓ: CISA KEV"
check "avisa que EPSS falló" "$out" "FUENTE FALLÓ: EPSS"
check "sin KEV ni EPSS, zod queda en medio" "$out" "medio 1"
check "el reporte dice que está incompleto" "$(cat "$tmp"/limpio/docs/seguridad/brechas-*.md)" "Reporte incompleto"
codigo "fuente caída y sin altos: exit 3" 3 "$rc"

# sin hallazgos → exit 0
printf "lockfileVersion: '9.0'\n\npackages:\n\n  '@types/node@24.0.0':\n    resolution: {integrity: x}\n" > "$tmp/limpio/pnpm-lock.yaml"
set +e
out="$(BRECHAS_FIXTURES="$tmp/fx" "$B" "$tmp/limpio" --sin-claude --sin-mcp)"; rc=$?
set -e
codigo "sin avisos: exit 0" 0 "$rc"
check "sin avisos no consulta KEV" "$out" "FUENTE FALLÓ" no

# lockfile pnpm v6 y package-lock v3
printf "lockfileVersion: '6.0'\n\npackages:\n\n  /@babel/core@7.24.0(supports-color@5.5.0):\n    resolution: {integrity: x}\n  /lodash@4.17.20:\n    dev: false\n" > "$tmp/limpio/pnpm-lock.yaml"
set +e; BRECHAS_FIXTURES="$tmp/fx" "$B" "$tmp/limpio" --sin-claude --sin-mcp --json >/dev/null; set -e
check "pnpm v6: lee scope y quita sufijo de peers" "$(cat "$tmp/fx/enviado.json")" "\"@babel/core\",\"ecosystem\":\"npm\"},\"version\":\"7.24.0\""
rm "$tmp/limpio/pnpm-lock.yaml"
echo '{"lockfileVersion":3,"packages":{"":{"name":"x"},"node_modules/lodash":{"version":"4.17.20"},"node_modules/a/node_modules/@s/b":{"version":"1.0.0"},"packages/web":{"link":true}}}' > "$tmp/limpio/package-lock.json"
set +e; BRECHAS_FIXTURES="$tmp/fx" "$B" "$tmp/limpio" --sin-claude --sin-mcp >/dev/null; set -e
enviado="$(cat "$tmp/fx/enviado.json")"
check "package-lock v3: paquete anidado con scope" "$enviado" "\"@s/b\""
check "package-lock v3: ignora links" "$enviado" "packages/web" no

set +e; "$B" "$tmp/sin-proyecto" >/dev/null 2>&1; rc=$?; set -e
codigo "sin lockfile: exit 2" 2 "$rc"

# ── supply-guard.sh ────────────────────────────────────────────────────────
export SUPPLY_GUARD_FIXTURES="$here/guard"
SUPPLY_GUARD_NOW=$(date -u -d '2026-10-27T00:00:00Z' +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-10-27T00:00:00Z' +%s)
export SUPPLY_GUARD_NOW
hook() { # hook <comando> → "rc|salida"
  local o rc
  set +e
  o="$("$H" 2>&1 <<<"$(jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')")"; rc=$?
  set -e
  echo "$rc|$o"
}

r="$(AI_LORDKIT_SUPPLY_GUARD=0 hook 'pnpm add evil-pkg@1.0.0')"
check "apagado no hace nada" "$r" "0|"
export AI_LORDKIT_SUPPLY_GUARD=1
r="$(hook 'pnpm add evil-pkg@1.0.0')";               check "bloquea paquete malicioso" "$r" "2|supply-guard BLOQUEÓ"
r="$(hook 'cd api && pnpm --filter api add -D zod evil-pkg@^1')"; check "bloquea con --filter antes del subcomando y rango" "$r" "2|"
r="$(hook 'npm i -w web evil-pkg')";                 check "npm -w con valor" "$r" "2|"
r="$(hook 'pnpm add -D left-pad')";                  check "deja pasar paquete viejo y limpio" "$r" "0|"
r="$(hook 'pnpm add left-pad')";                     check "sin salida si todo está bien" "$r" "0|" ; [[ "$r" == "0|" ]] || { echo "FALLA: salida inesperada: $r"; fail=1; }
r="$(hook 'npx -y @nuevo/pkg init evil-pkg')";      check "npx: versión nueva pide confirmación" "$r" '"permissionDecision":"ask"'
check "npx: solo el primer argumento es paquete" "$r" "BLOQUEÓ" no
check "dice cuándo se publicó" "$r" "@nuevo/pkg@2.0.0 (publicada el 2026-10-25)"
r="$(hook 'pnpm dlx @nuevo/pkg@next')";              check "dlx con tag sin datos: deja pasar" "$r" "0|"
r="$(hook 'git commit -m "add install i npx"')";     check "ignora comandos que no instalan" "$r" "0|"
r="$(hook 'npx ./scripts/local.js')";                check "ignora rutas locales" "$r" "0|"
r="$(hook 'pnpm add github:user/repo file:../x')";   check "ignora git y file:" "$r" "0|"
r="$(hook 'pnpm i')";                                check "pnpm i sin paquetes" "$r" "0|"
r="$(SUPPLY_GUARD_FIXTURES="$tmp/vacio" hook 'pnpm add evil-pkg')"; check "sin red deja pasar" "$r" "0|"

# ── red real (CI) ──────────────────────────────────────────────────────────
if [ "${BRECHAS_RED:-0}" = 1 ]; then
  unset SUPPLY_GUARD_FIXTURES SUPPLY_GUARD_NOW
  mkdir -p "$tmp/red"
  printf "lockfileVersion: '9.0'\n\npackages:\n\n  lodash@4.17.20:\n    resolution: {integrity: x}\n" > "$tmp/red/pnpm-lock.yaml"
  set +e; out="$("$B" "$tmp/red" --sin-claude --sin-mcp)"; rc=$?; set -e
  check "red: OSV responde" "$out" "FUENTE FALLÓ: OSV" no
  check "red: KEV y EPSS responden" "$out" "FUENTE FALLÓ" no
  check "red: aviso real de lodash 4.17.20" "$(cat "$tmp"/red/docs/seguridad/brechas-*.md)" "GHSA-35jh-r3h4-6jhm"
  codigo "red: lodash 4.17.20 es alto" 1 "$rc"
  r="$(hook 'pnpm add lodash@4.17.21')"; check "red: hook deja pasar lodash" "$r" "0|"
  r="$(AI_LORDKIT_SUPPLY_DAYS=100000 hook 'pnpm add lodash@4.17.21')"; check "red: deps.dev da la fecha (pide confirmar con un umbral enorme)" "$r" '"permissionDecision":"ask"'
fi

exit "$fail"
