#!/usr/bin/env bash
# scan-leaks.sh — revisa que el bundle público no lleve secretos ni datos personales.
#
# Uso:
#   scripts/scan-leaks.sh              → archivos versionados + cambios en stage
#   scripts/scan-leaks.sh --staged     → solo lo que está en stage (lo usa `install.sh sync`)
#   scripts/scan-leaks.sh --history    → TODO el historial de git (todas las ramas)
#
# Tres niveles:
#   1. Secretos (tokens, llaves privadas, URLs de BD con clave real) → siempre falla.
#   2. Datos personales (emails reales, rutas /home/<usuario>)        → falla.
#   3. Términos privados de TU capa privada ($CLAUDE_PRIVATE_DIR/private-terms.txt):
#      nombres de clientes, proyectos, colegios… → falla si aparecen en el bundle público.
#
# Sale con 1 si encuentra algo. Las excepciones viven en scripts/scan-allowlist.txt
# (regex por línea, se comparan contra "archivo: coincidencia").

set -uo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$BUNDLE"
PRIVATE_DIR="${CLAUDE_PRIVATE_DIR:-$HOME/ai-lordkit-private}"
ALLOW="$BUNDLE/scripts/scan-allowlist.txt"
MODE="tracked"
ONLY_SECRETS=0

# Opciones extra (las usa `install.sh sync` para revisar la capa privada):
#   --root DIR       revisa otro repo en vez del bundle
#   --only-secrets   solo nivel 1 (en tu repo privado los nombres y emails sí pueden estar)
while (( $# )); do
  case "$1" in
    --history|--staged) MODE="$1" ;;
    --root) ROOT="$(cd "$2" && pwd)"; shift ;;
    --only-secrets) ONLY_SECRETS=1 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

# Nivel 1: secretos. Patrones de proveedores conocidos + URLs con usuario:clave.
SECRET_RE='(sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|sk-kimi-[A-Za-z0-9]{16,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(sk|rk)_live_[A-Za-z0-9]{10,}|whsec_[A-Za-z0-9]{16,}|hf_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36}|(postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqp)://[^:@/[:space:]]+:[^@[:space:]]{6,}@[^[:space:]"'"'"'`]+)'
# Nivel 2: datos personales.
EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
HOME_RE='(/home/[a-z][a-z0-9_-]{2,}|/Users/[A-Za-z][A-Za-z0-9_-]{2,}|C:\\Users\\[A-Za-z][A-Za-z0-9_-]{2,})'
# Emails y rutas de ejemplo que sí son válidos en docs.
SAFE_RE='@(example\.(com|org|net)|ejemplo\.com|dominio\.com|test\.com|localhost|users\.noreply\.github\.com|anthropic\.com)|^noreply@|/home/(user|usuario|runner|node|ubuntu)\b|/Users/(foo|user|usuario)\b|C:\\Users\\(foo|user|usuario)\b'

TERMS_FILE=""
(( ONLY_SECRETS )) || { [[ -f "$PRIVATE_DIR/private-terms.txt" ]] && TERMS_FILE="$PRIVATE_DIR/private-terms.txt"; }

# Emite "ruta<TAB>contenido" para cada archivo a revisar, según el modo.
list_blobs() {
  case "$MODE" in
    --history)
      git -C "$ROOT" rev-list --all --objects | while read -r sha path; do
        [[ -n "$path" ]] || continue
        [[ "$(git -C "$ROOT" cat-file -t "$sha")" == blob ]] || continue
        printf '%s\t%s\n' "$path" "$sha"
      done ;;
    --staged)
      git -C "$ROOT" diff --cached --name-only --diff-filter=ACMR | while read -r path; do
        printf '%s\t:%s\n' "$path" "$path"
      done ;;
    *)
      # Sin git (kit bajado con get.sh): se revisan todos los archivos del directorio.
      if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        (cd "$ROOT" && find . -type f ! -path './.git/*' | sed 's|^\./||') | sort | while read -r path; do
          printf '%s\t@%s\n' "$path" "$path"
        done
        return 0
      fi
      { git -C "$ROOT" ls-files; git -C "$ROOT" diff --cached --name-only --diff-filter=ACMR; } | sort -u \
        | while read -r path; do
            [[ -f "$ROOT/$path" ]] && printf '%s\t@%s\n' "$path" "$path"
          done ;;
  esac
}

# Lee el contenido de un blob: sha, :ruta (stage) o @ruta (disco).
read_blob() {
  case "$1" in
    @*) cat "$ROOT/${1#@}" ;;
    :*) git -C "$ROOT" show "$1" ;;
    *)  git -C "$ROOT" cat-file -p "$1" ;;
  esac
}

allowed() {
  [[ -f "$ALLOW" ]] || return 1
  grep -qEf <(grep -v '^\s*\(#\|$\)' "$ALLOW") <<<"$1"
}

hits=0
report() {
  local kind="$1" line="$2"
  allowed "$line" && return 0
  echo "  [$kind] $line"
  hits=$((hits + 1))
}

while IFS=$'\t' read -r path ref; do
  # El propio escáner y su allowlist contienen los patrones a propósito.
  case "$path" in scripts/scan-leaks.sh|scripts/scan-allowlist.txt) continue ;; esac
  content="$(read_blob "$ref" 2>/dev/null | LC_ALL=C tr -d '\000')" || continue

  while read -r m; do [[ -n "$m" ]] && report secreto "$path: $m"; done \
    < <(grep -aoE "$SECRET_RE" <<<"$content" | sort -u)

  (( ONLY_SECRETS )) && continue

  while read -r m; do [[ -n "$m" ]] && report personal "$path: $m"; done \
    < <(grep -aoE "$EMAIL_RE|$HOME_RE" <<<"$content" | grep -vE "$SAFE_RE" | sort -u)

  if [[ -n "$TERMS_FILE" ]]; then
    while read -r m; do [[ -n "$m" ]] && report privado "$path: $m"; done \
      < <(grep -aoiFf <(grep -v '^\s*\(#\|$\)' "$TERMS_FILE") <<<"$content" | sort -u)
  fi
done < <(list_blobs)

if (( hits > 0 )); then
  echo ""
  echo "✗ $hits hallazgo(s). Si alguno es un ejemplo inofensivo, agrégalo a scripts/scan-allowlist.txt."
  exit 1
fi
if (( ONLY_SECRETS )); then
  echo "✓ Sin secretos"
elif [[ -n "$TERMS_FILE" ]]; then
  echo "✓ Sin secretos, datos personales ni términos privados"
else
  echo "✓ Sin secretos ni datos personales"
  echo "  (Sin $PRIVATE_DIR/private-terms.txt no se revisan nombres de clientes o proyectos.)"
fi
exit 0
