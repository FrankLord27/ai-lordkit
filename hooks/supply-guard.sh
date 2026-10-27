#!/usr/bin/env bash
# Hook PreToolUse (Bash), opcional: antes de instalar o ejecutar un paquete de npm
# (pnpm add, npm install, yarn add, bun add, npx, pnpm dlx, bunx) revisa cada paquete pedido:
#   - versión marcada como maliciosa en OSV.dev (MAL-*)  → bloquea (exit 2)
#   - versión publicada hace menos de N días (7)          → pide confirmación
#   - sin red, sin jq o sin curl                          → deja pasar (pnpm minimumReleaseAge sigue)
# Se activa con AI_LORDKIT_SUPPLY_GUARD=1 en "env" de settings.json. Apagado no hace nada.
# Fuentes: registry.npmjs.org (dist-tags), deps.dev (fecha de publicación), OSV.dev (avisos).

[[ "${AI_LORDKIT_SUPPLY_GUARD:-0}" == 1 ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[[ -n "${SUPPLY_GUARD_FIXTURES:-}" ]] || command -v curl >/dev/null 2>&1 || exit 0

dias="${AI_LORDKIT_SUPPLY_DAYS:-7}"
input=$(cat)
[[ "$(jq -r '.tool_name // empty' <<<"$input")" == Bash ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
grep -Eq '(^|[^A-Za-z0-9_-])(npx|pnpx|bunx|dlx|add|install|i|exec)([^A-Za-z0-9_-]|$)' <<<"$cmd" || exit 0

# ── paquetes pedidos ────────────────────────────────────────────────────────
specs=()
spec_ok() { [[ -n "$1" && "$1" != [./~]* && "$1" != *:* ]]; }
set -f
while IFS= read -r seg; do
  read -r -a w <<<"$seg"
  i=0
  while [[ ${i} -lt ${#w[@]} && ( "${w[$i]}" == *=* || "${w[$i]}" == sudo ) ]]; do i=$((i+1)); done  # FOO=1 cmd, sudo cmd
  prog="${w[$i]:-}"; prog="${prog##*/}"
  # Opciones antes del subcomando (pnpm --filter api add x, npm -w web i x)
  j=$((i+1))
  while (( j < ${#w[@]} )) && [[ "${w[$j]}" == -* ]]; do
    case "${w[$j]}" in
      --filter|-F|--dir|-C|--prefix|--workspace|--cwd) j=$((j+1)) ;;
      -w) [[ "$prog" == npm ]] && j=$((j+1)) ;;  # en npm -w lleva valor; en pnpm no
    esac
    j=$((j+1))
  done
  sub="${w[$j]:-}"
  modo=""
  case "$prog" in
    npx|pnpx|bunx) modo=uno; i=$((i+1)) ;;
    pnpm|yarn)
      case "$sub" in
        dlx) modo=uno ;;
        add|install|i) modo=todos ;;
      esac
      i=$((j+1)) ;;
    npm)
      case "$sub" in
        exec|x) modo=uno ;;
        install|i|add|isntall) modo=todos ;;
      esac
      i=$((j+1)) ;;
    bun)
      case "$sub" in add|install|i) modo=todos ;; esac
      i=$((j+1)) ;;
  esac
  [[ -n "$modo" ]] || continue
  while (( i < ${#w[@]} )); do
    a="${w[$i]}"
    case "$a" in
      --) ;;
      -p|--package) i=$((i+1)); spec_ok "${w[$i]:-}" && specs+=("${w[$i]}") ;;
      --package=*) spec_ok "${a#--package=}" && specs+=("${a#--package=}") ;;
      --filter|-F|--dir|-C|--registry|--prefix|--workspace|--config|--cwd) i=$((i+1)) ;;
      -w) [[ "$prog" == npm ]] && i=$((i+1)) ;;
      -*) ;;
      *)
        spec_ok "$a" && specs+=("$a")
        [[ "$modo" == uno ]] && break ;;
    esac
    i=$((i+1))
  done
done < <(sed -E 's/(&&|\|\||;|\|)/\n/g' <<<"$cmd")
set +f
(( ${#specs[@]} )) || exit 0

# ── red (o fixtures en tests) ──────────────────────────────────────────────
safe() { local s="${1//\//__}"; echo "${s//@/_}"; }
dist_tags() {
  if [[ -n "${SUPPLY_GUARD_FIXTURES:-}" ]]; then cat "$SUPPLY_GUARD_FIXTURES/tags-$(safe "$1").json" 2>/dev/null
  else curl -fsS -m 6 "https://registry.npmjs.org/-/package/${1/\//%2f}/dist-tags" 2>/dev/null; fi
}
publicado() {
  if [[ -n "${SUPPLY_GUARD_FIXTURES:-}" ]]; then cat "$SUPPLY_GUARD_FIXTURES/depsdev-$(safe "$1")-$2.json" 2>/dev/null
  else curl -fsS -m 6 "https://api.deps.dev/v3/systems/npm/packages/${1/\//%2F}/versions/$2" 2>/dev/null; fi
}
osv() {
  if [[ -n "${SUPPLY_GUARD_FIXTURES:-}" ]]; then cat "$SUPPLY_GUARD_FIXTURES/osv-$(safe "$1")-$2.json" 2>/dev/null
  else
    curl -fsS -m 6 -H 'content-type: application/json' https://api.osv.dev/v1/query \
      -d "$(jq -cn --arg n "$1" --arg v "$2" '{package:{name:$n,ecosystem:"npm"},version:$v}')" 2>/dev/null
  fi
}

ahora="${SUPPLY_GUARD_NOW:-$(date +%s)}"
malos=(); nuevos=()
for s in "${specs[@]:0:10}"; do
  if [[ "$s" == @* ]]; then rest="${s:1}"; name="@${rest%%@*}"; [[ "$rest" == *@* ]] && ver="${rest#*@}" || ver=""
  else name="${s%%@*}"; [[ "$s" == *@* ]] && ver="${s#*@}" || ver=""; fi
  # Rango o tag → la versión del tag (o latest). Un rango se aproxima con latest.
  if ! [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]]; then
    tag="$ver"; [[ "$tag" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]] || tag=latest
    ver=$(dist_tags "$name" | jq -r --arg t "$tag" '.[$t] // .latest // empty' 2>/dev/null)
    [[ -n "$ver" ]] || continue
  fi
  ids=$(osv "$name" "$ver" | jq -r '[.vulns[]?.id | select(startswith("MAL-"))] | join(", ")' 2>/dev/null)
  [[ -n "$ids" ]] && malos+=("$name@$ver ($ids)")
  ts=$(publicado "$name" "$ver" | jq -r '.publishedAt // empty | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601' 2>/dev/null)
  if [[ "$ts" =~ ^[0-9]+$ ]] && (( ahora - ts < dias * 86400 )); then
    nuevos+=("$name@$ver (publicada el $(jq -rn --argjson t "$ts" '$t | todate[0:10]'))")
  fi
done

if (( ${#malos[@]} )); then
  printf 'supply-guard BLOQUEÓ este comando: OSV.dev marca como malicioso %s. No lo instales; revisa https://osv.dev y corre /brechas.\n' "$(IFS=';'; echo "${malos[*]}")" >&2
  exit 2
fi
if (( ${#nuevos[@]} )); then
  razon="supply-guard: versión publicada hace menos de $dias días: $(IFS=';'; echo "${nuevos[*]}"). Los paquetes recién publicados son el vector típico de ataques de supply chain. ¿Seguro que la quieres ya?"
  jq -cn --arg r "$razon" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
fi
exit 0
