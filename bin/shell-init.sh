# ai-lordkit/bin/shell-init.sh
# Se instala en ~/.claude/shell-init.sh y se carga desde .zshrc / .bashrc.
#
# Un solo comando: `claude`.
#   claude              → suscripción Anthropic (Opus / Sonnet / Haiku)
#   claude --kimi       → mismos agents y skills, backend Kimi (K3 / K2.7)
#   claude -k --model k3-256k
#
# El menú /model no puede listar Kimi (está hardcodeado en el binario y la sesión
# tiene un backend fijo), así que la elección se hace al arrancar, no dentro.

claude() {
  case "${1:-}" in
    --kimi|-k) shift; command claude-kimi "$@" ;;
    *)         command claude "$@" ;;
  esac
}
