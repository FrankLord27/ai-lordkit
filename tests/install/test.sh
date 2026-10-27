#!/usr/bin/env bash
# Prueba update → rollback → uninstall en un HOME de mentira, sin Claude Code instalado.
# Uso: ./tests/install/test.sh  (sale con 1 si algo falla)
set -u
KIT="$(cd "$(dirname "$0")/../.." && pwd)"
H="$(mktemp -d)"; trap 'rm -rf "$H"' EXIT
fail=0
JQDIR="$(dirname "$(command -v jq)"):$(dirname "$(command -v git)")"  # en Windows jq y git no viven en /usr/bin
check() { if eval "$2"; then echo "ok   $1"; else echo "FALLA $1"; fail=1; fi; }
run() { HOME="$H" SHELL=/bin/zsh CLAUDE_YES=1 CLAUDE_PRIVATE_DIR="$H/sin-capa" PATH="/usr/bin:/bin:$JQDIR" \
          bash "$KIT/install.sh" "$@" >"$H/log" 2>&1 || { echo "--- install.sh $* falló:"; cat "$H/log"; fail=1; }; }
s() { jq -r "$1" "$H/.claude/settings.json"; }

mkdir -p "$H/.claude"
cat > "$H/.claude/settings.json" <<'JSON'
{ "theme": "dark", "env": { "MI_VAR": "1" },
  "permissions": { "allow": ["Bash(node *)"] },
  "enabledPlugins": { "mio@otro": true } }
JSON
# Copias viejas de la versión anterior del kit + una skill propia con nombre parecido
mkdir -p "$H/.claude/skills/eas-workflows/scripts" "$H/.claude/skills/expo-router" "$H/.claude/skills/expo-mia"
echo '{}' > "$H/.claude/skills/eas-workflows/scripts/package.json"

run update
check "update borra las copias viejas de Expo/EAS" '[[ ! -e $H/.claude/skills/eas-workflows && ! -e $H/.claude/skills/expo-router ]]'
check "update no toca una skill propia parecida"   '[[ -d $H/.claude/skills/expo-mia ]]'
check "update no instala deps de lo que borra"     '! grep -q "skill eas-workflows" "$H/log"'
check "update cuenta solo las skills del kit"      'grep -q "skills del kit instaladas en ~/.claude/skills/ ($(ls -d "$KIT"/skills/*/ | wc -l))" "$H/log"'
check "update conserva una clave propia"        '[[ $(s .theme) == dark ]]'
check "update conserva una variable propia"     '[[ $(s .env.MI_VAR) == 1 ]]'
check "update conserva un plugin propio"        '[[ $(s ".enabledPlugins[\"mio@otro\"]") == true ]]'
check "update aplica los permisos del kit"      '[[ $(s ".permissions.allow | index(\"Bash(node *)\")") == null ]]'
check "update instala el guard"                 '[[ -x $H/.claude/hooks/guard.sh ]]'
check "update instala los 3 modos"              '[[ -f $H/.claude/output-styles/completo.md && -f $H/.claude/output-styles/intermedio.md && -f $H/.claude/output-styles/ahorro.md ]]'
check "update deja intermedio por defecto"        '[[ $(s .outputStyle) == intermedio ]]'
check "update crea ~/.zshrc con shell-init"     'grep -q claude/shell-init.sh "$H/.zshrc"'

sleep 1; run rollback
check "rollback devuelve el settings.json"      '[[ $(s ".permissions.allow[0]") == "Bash(node *)" ]]'
check "rollback quita los agents que no había"  '[[ ! -d $H/.claude/agents ]]'

sleep 1; run rollback
check "un segundo rollback lo deshace"          '[[ -x $H/.claude/hooks/guard.sh ]]'

sleep 1; run uninstall
check "uninstall quita el guard"                '[[ ! -e $H/.claude/hooks/guard.sh ]]'
check "uninstall quita CLAUDE.md"               '[[ ! -e $H/.claude/CLAUDE.md ]]'
check "uninstall quita los modos"              '[[ ! -e $H/.claude/output-styles/ahorro.md ]]'
check "uninstall deja tus claves"               '[[ $(s .theme) == dark && $(s .env.MI_VAR) == 1 ]]'
check "uninstall quita las claves del kit"      '[[ $(s .hooks) == null && $(s .env.BASH_DEFAULT_TIMEOUT_MS) == null ]]'
check "uninstall limpia el .zshrc"              '! grep -q claude/shell-init.sh "$H/.zshrc"'

(( fail == 0 )) && echo "install.sh: update, rollback y uninstall pasan"
exit $fail
