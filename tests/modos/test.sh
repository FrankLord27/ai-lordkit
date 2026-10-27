#!/usr/bin/env bash
# Prueba `claude --modo X` (bash y zsh si está) y que la statusline muestre el modo.
# Uso: ./tests/modos/test.sh  (sale con 1 si algo falla)
set -u
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FALLA $1"; echo "  esperado: $3"; echo "  salió:    $2"; fail=1; fi; }

# claude y claude-kimi de mentira: imprimen sus argumentos entre corchetes
for b in claude claude-kimi; do
  printf '#!/bin/sh\nprintf "%s:"\nfor a in "$@"; do printf "[%%s]" "$a"; done\necho\n' "$b" > "$T/$b"
  chmod +x "$T/$b"
done

shells=(bash); command -v zsh >/dev/null && shells+=(zsh)
for sh in "${shells[@]}"; do
  r() { PATH="$T:$PATH" "$sh" -c '. "$0/bin/shell-init.sh"; claude "$@"' "$KIT" "$@" 2>&1; }
  check "$sh: sin modo no agrega nada"   "$(r -p 'hola mundo')" 'claude:[-p][hola mundo]'
  check "$sh: ahorro = low + Sonnet"     "$(r --modo ahorro -p x)" 'claude:[--settings][{"outputStyle":"ahorro"}][--effort][low][--model][sonnet][-p][x]'
  check "$sh: completo = xhigh"          "$(r --modo=completo)" 'claude:[--settings][{"outputStyle":"completo"}][--effort][xhigh]'
  check "$sh: intermedio = medium"       "$(r --modo intermedio)" 'claude:[--settings][{"outputStyle":"intermedio"}][--effort][medium]'
  check "$sh: tu --model se respeta"     "$(r --modo ahorro --model opus)" 'claude:[--settings][{"outputStyle":"ahorro"}][--effort][low][--model][opus]'
  check "$sh: tu --effort se respeta"    "$(r --effort=max --modo completo)" 'claude:[--settings][{"outputStyle":"completo"}][--effort=max]'
  check "$sh: con Kimi no cambia modelo" "$(r -k --modo ahorro)" 'claude-kimi:[--settings][{"outputStyle":"ahorro"}][--effort][low]'
  check "$sh: modo inválido falla"       "$(r --modo raro; echo "rc=$?")" "modo desconocido: 'raro' (usa completo, intermedio o ahorro)
rc=1"
done

# Cada modo de --modo tiene su archivo, y el nombre del archivo coincide con el outputStyle
for m in completo intermedio ahorro; do
  check "output-styles/$m.md se llama $m" "$(sed -n 's/^name: //p' "$KIT/output-styles/$m.md")" "$m"
done
check "settings.json usa un modo que existe" "$(jq -r .outputStyle "$KIT/settings.json")" intermedio

if command -v jq >/dev/null; then
  sl() { "$KIT/hooks/statusline.sh" <<<"$1"; }
  check "statusline: modo/effort y costo" \
    "$(sl '{"model":{"display_name":"Sonnet"},"output_style":{"name":"ahorro"},"effort":{"level":"low"},"workspace":{"current_dir":"/tmp"},"cost":{"total_cost_usd":0.1234}}')" \
    'Sonnet · ahorro/low · tmp · $0.12'
  check "statusline: sin effort ni costo" \
    "$(sl '{"model":{"display_name":"K3"},"output_style":{"name":"completo"},"workspace":{"current_dir":"/tmp"}}')" \
    'K3 · completo · tmp'
  check "statusline: estilo default no se muestra" \
    "$(sl '{"model":{"display_name":"Opus"},"output_style":{"name":"default"},"effort":{"level":"medium"},"workspace":{"current_dir":"/tmp"}}')" \
    'Opus · medium · tmp'
fi

(( fail == 0 )) && echo "modos: launcher y statusline pasan"
exit $fail
