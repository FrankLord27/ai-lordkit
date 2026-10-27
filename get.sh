#!/usr/bin/env bash
# ai-lordkit/get.sh — instala ai-lordkit con un solo comando, sin clonar el repo.
#
#   curl -fsSL https://raw.githubusercontent.com/FrankLord27/ai-lordkit/main/get.sh | bash
#
# Qué hace:
#   1. Descarga el kit (tarball de GitHub) en ~/.ai-lordkit. La versión anterior queda en ~/.ai-lordkit.prev.
#   2. Corre ~/.ai-lordkit/install.sh:
#        - sin ~/.claude  → `all`    (dependencias + Claude Code + config)
#        - con ~/.claude  → `update` (solo aplica la config, con backup)
#      Para otro subcomando:  curl -fsSL .../get.sh | bash -s -- doctor
#
# Variables:
#   AI_LORDKIT_REF   rama, tag o SHA a instalar (por defecto: el último release; sin releases, main).
#                    Un SHA es lo más seguro.
#   AI_LORDKIT_DIR   dónde dejar el kit (por defecto: ~/.ai-lordkit).
#   AI_LORDKIT_REPO  owner/repo en GitHub (por defecto: FrankLord27/ai-lordkit).
#   CLAUDE_YES=1     confirma solo la limpieza de `all` (para CI o máquinas sin terminal).
#
# Todo va dentro de main(): si la descarga se corta a mitad, bash no ejecuta nada.

main() {
  set -euo pipefail

  local repo="${AI_LORDKIT_REPO:-FrankLord27/ai-lordkit}"
  local ref="${AI_LORDKIT_REF:-}"
  local dir="${AI_LORDKIT_DIR:-$HOME/.ai-lordkit}"

  say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
  fail() { printf '\033[0;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }

  case "$(uname -s)" in
    Linux|Darwin) ;;
    *) fail "Sistema no soportado: $(uname -s). ai-lordkit funciona en Linux y macOS. En Windows usa WSL: https://github.com/$repo#windows" ;;
  esac
  command -v curl >/dev/null 2>&1 || fail "Falta curl. Instálalo y vuelve a correr el comando."
  command -v tar  >/dev/null 2>&1 || fail "Falta tar. Instálalo y vuelve a correr el comando."

  # Por defecto, el último release publicado (no lo que haya en main ese día).
  # Sin releases o sin red hacia la API de GitHub, cae a main.
  if [[ -z "$ref" ]]; then
    ref="$(curl -fsSL --retry 2 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)"
    ref="${ref:-main}"
  fi
  local url="https://github.com/$repo/archive/$ref.tar.gz"

  # Un clon de git es tuyo (backup/sync dependen de él): no se pisa.
  if [[ -d "$dir/.git" ]]; then
    say "$dir es un clon de git: no lo toco. Actualízalo con 'git -C $dir pull' si quieres."
  else
    local tmp
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/ai-lordkit.XXXXXX")"
    trap "rm -rf '$tmp'" EXIT

    say "Descargando $repo@$ref"
    mkdir -p "$tmp/kit"
    curl -fsSL --retry 3 "$url" | tar -xzf - -C "$tmp/kit" --strip-components 1 \
      || fail "No se pudo descargar $url (¿existe la versión '$ref'?)"
    [[ -f "$tmp/kit/install.sh" && -f "$tmp/kit/settings.json" ]] \
      || fail "La descarga no parece ai-lordkit (falta install.sh o settings.json)"
    printf '%s\n' "$ref" > "$tmp/kit/.ai-lordkit-ref"

    # Cambio casi atómico: el kit viejo queda en .prev hasta la próxima instalación.
    if [[ -d "$dir" ]]; then
      rm -rf "$dir.prev"
      mv "$dir" "$dir.prev"
    fi
    mkdir -p "$(dirname "$dir")"
    mv "$tmp/kit" "$dir"
    chmod +x "$dir/install.sh"
    say "Kit en $dir"
  fi

  local cmd=()
  if (( $# > 0 )); then
    cmd=("$@")
  elif [[ -d "$HOME/.claude" ]]; then
    cmd=(update)
  else
    cmd=(all)
  fi
  say "Corriendo: install.sh ${cmd[*]}"

  # Con curl | bash, stdin es el propio script: install.sh no debe leerlo.
  # Si hay terminal, se le da la terminal (preguntas y sudo); si no, /dev/null.
  if ( exec </dev/tty ) 2>/dev/null; then
    bash "$dir/install.sh" "${cmd[@]}" </dev/tty
  else
    bash "$dir/install.sh" "${cmd[@]}" </dev/null
  fi
}

main "$@"
