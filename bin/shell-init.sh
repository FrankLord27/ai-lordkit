# ai-lordkit/bin/shell-init.sh
# shellcheck shell=bash
# Se instala en ~/.claude/shell-init.sh y se carga desde .zshrc / .bashrc.
#
# Un solo comando: `claude`.
#   claude                  → suscripción Anthropic (Opus / Sonnet / Haiku)
#   claude --kimi           → mismos agents y skills, backend Kimi (K3 / K2.7)
#   claude -k --model k3-256k
#   claude --modo ahorro    → modo de trabajo: completo | intermedio | ahorro
#
# El menú /model no puede listar Kimi (está hardcodeado en el binario y la sesión
# tiene un backend fijo), así que la elección se hace al arrancar, no dentro.
#
# Un modo = output style + effort (+ Sonnet en ahorro). Dentro de la sesión se cambia con
# `/output-style <modo>` y `/effort <nivel>`. Si pasas tu propio --model o --effort,
# ese se respeta (p. ej. `claude --modo ahorro --model opus`).

_lordkit_modo() { # $1 = modo, $2 = 1 si no toca el modelo, $3 = 1 si no toca el effort.
  local effort model=""
  case "$1" in
    completo)   effort=xhigh ;;
    intermedio) effort=medium ;;
    ahorro)     effort=low; model=sonnet ;;
    *) echo "modo desconocido: '$1' (usa completo, intermedio o ahorro)" >&2; return 1 ;;
  esac
  printf '%s\n' --settings "{\"outputStyle\":\"$1\"}"
  [ "$3" = 1 ] || printf '%s\n' --effort "$effort"
  [ "$2" = 1 ] || [ -z "$model" ] || printf '%s\n' --model "$model"
}

claude() {
  local kimi=0 modo="" flags="" f own_model=0 own_effort=0
  local -a args pre
  args=(); pre=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --kimi|-k) kimi=1 ;;
      --modo)    modo="${2:-?}"; [ $# -gt 1 ] && shift ;;
      --modo=*)  modo="${1#--modo=}" ;;
      --model|--model=*)   own_model=1;  args+=("$1") ;;
      --effort|--effort=*) own_effort=1; args+=("$1") ;;
      *)         args+=("$1") ;;
    esac
    shift
  done
  if [ -n "$modo" ]; then
    # Con Kimi el modelo lo decide claude-kimi, así que el modo no lo toca.
    [ "$kimi" = 1 ] && own_model=1
    flags="$(_lordkit_modo "$modo" "$own_model" "$own_effort")" || return 1
    while IFS= read -r f; do pre+=("$f"); done <<<"$flags"
  fi
  if [ "$kimi" = 1 ]; then
    command claude-kimi "${pre[@]}" "${args[@]}"
  else
    command claude "${pre[@]}" "${args[@]}"
  fi
}

# El instalador oficial deja `claude` (y el kit, `claude-kimi`) en ~/.local/bin.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
