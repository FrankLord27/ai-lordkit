#!/usr/bin/env bash
# ai-lordkit/install.sh — v2 (ai-lordkit)
# Instalación, actualización y mantenimiento de Claude Code.
#
# Uso:
#   ./install.sh              → TODO (máquina formateada): verify + deps + clean(seguro) + install
#                               + restore + harden + graphify + doctor
#   ./install.sh deps         → instala pre-requisitos (git, gh, jq, Node 24, pnpm, uv)
#   ./install.sh update       → aplica el bundle a ~/.claude SIN reinstalar Claude (con backup)
#   ./install.sh rollback     → vuelve a la config de antes del último update (o: rollback <carpeta>)
#   ./install.sh uninstall    → quita lo que puso el kit (con backup; no toca credenciales ni historial)
#   ./install.sh restore      → igual que update pero pensado para post-instalación
#   ./install.sh backup       → copia la config viva de ~/.claude al bundle público y a tu capa privada
#   ./install.sh sync         → backup + escaneo + commit + push (público en rama aparte, privado directo)
#   ./install.sh private-init → crea tu capa privada en ~/ai-lordkit-private desde la plantilla
#   ./install.sh scan         → revisa el bundle buscando tokens, datos personales y términos privados
#   ./install.sh clean        → mueve ~/.claude a un backup y borra binarios (NO destruye datos)
#   ./install.sh install      → solo descarga e instala Claude Code
#   ./install.sh harden       → endurece pnpm (supply chain) y verifica Node 24
#   ./install.sh graphify     → instala graphify (grafo de conocimiento del código)
#   ./install.sh mcp          → registra los servidores MCP de mcp/servers.json (+ los de tu capa privada)
#   ./install.sh plugins      → registra los marketplaces e instala los plugins de settings.json
#   ./install.sh verify       → verifica integridad del bundle
#   ./install.sh doctor       → diagnostica pre-requisitos (git, gh, pnpm, node, jq, uv, docker)
#
# Tras formatear: 1) restaura esta carpeta  2) ./install.sh  3) abre 'claude' y haz login.
#
# Bundle en $SCRIPT_DIR (público, sin nada personal):
#   CLAUDE.md  settings.json  agents/  commands/  output-styles/  skills/  hooks/  bin/  mcp/
#
# Capa privada en $CLAUDE_PRIVATE_DIR (por defecto ~/ai-lordkit-private, tu repo privado):
#   CLAUDE.md  settings.json  agents/  commands/  skills/  mcp.json  private-terms.txt
#   Se aplica ENCIMA del bundle. backup/sync devuelven cada cosa a su capa.
#
# Principios v2 (por qué cambió):
#   - clean NUNCA hace rm -rf de ~/.claude: lo MUEVE a ~/.claude-backups/ (credenciales,
#     historial y proyectos se recuperan en restore). El v1 borraba las credenciales.
#   - Las skills van a ~/.claude/skills/ (nativo). Se eliminó el plugin job-skills.
#   - Sin listas hardcodeadas de agents/skills: el bundle se verifica dinámicamente.
#   - Sin IDs de modelo hardcodeados: agents y settings usan aliases (opus/sonnet/haiku).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_BIN="$HOME/.local/bin/claude"
CLAUDE_SHARE="$HOME/.local/share/claude"
BACKUP_ROOT="$HOME/.claude-backups"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/$TS"
OS="$(uname -s)"
# Sugerencia de instalación según el sistema (para mensajes de doctor)
if [[ "$OS" == Darwin ]]; then PKG_HINT="brew install"; else PKG_HINT="sudo apt install"; fi
PRIVATE_DIR="${CLAUDE_PRIVATE_DIR:-$HOME/ai-lordkit-private}"
# Línea que separa, dentro de ~/.claude/CLAUDE.md, la parte pública de la privada.
PRIVATE_MARK="<!-- capa-privada: todo lo de abajo viene de \$CLAUDE_PRIVATE_DIR/CLAUDE.md, no lo edites aquí -->"
SCANNER="$SCRIPT_DIR/scripts/scan-leaks.sh"

# Datos de usuario que clean/restore deben preservar siempre
USER_DATA=( .credentials.json kimi.key history.jsonl projects sessions plans tasks todos file-history )

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
step() { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ─── verify: integridad del bundle (dinámico, sin listas hardcodeadas) ───────
do_verify() {
  step "Verificando integridad del bundle"
  local errors=0

  for f in CLAUDE.md WORKFLOW.md settings.json bin/claude-kimi bin/shell-init.sh; do
    if [[ -f "$SCRIPT_DIR/$f" ]]; then ok "$f presente"; else err "FALTA: $f"; errors=$((errors+1)); fi
  done

  if command -v jq &>/dev/null && [[ -f "$SCRIPT_DIR/settings.json" ]]; then
    if jq . "$SCRIPT_DIR/settings.json" >/dev/null 2>&1; then
      ok "settings.json es JSON válido"
    else
      err "settings.json NO es JSON válido"; errors=$((errors+1))
    fi
  fi

  local n
  n=$(ls "$SCRIPT_DIR/agents/"*.md 2>/dev/null | wc -l)
  if (( n >= 9 )); then ok "agents: $n archivos"; else err "agents: solo $n (se esperan ≥9)"; errors=$((errors+1)); fi

  n=$(ls -d "$SCRIPT_DIR/skills/"*/ 2>/dev/null | wc -l)
  if (( n >= 18 )); then ok "skills: $n carpetas"; else err "skills: solo $n (se esperan ≥18)"; errors=$((errors+1)); fi
  local s missing=0
  for s in "$SCRIPT_DIR/skills/"*/; do
    [[ -f "$s/SKILL.md" ]] || { warn "skill sin SKILL.md: $(basename "$s")"; missing=$((missing+1)); }
  done
  (( missing == 0 )) && ok "todas las skills tienen SKILL.md"

  # Memoria entre sesiones = auto-memory nativa + skill mem-search (busca en el historial)
  local ms="$SCRIPT_DIR/skills/mem-search/scripts/mem-search.sh"
  if [[ -x "$ms" ]] && bash -n "$ms"; then
    ok "mem-search ejecutable"
  else
    err "skills/mem-search/scripts/mem-search.sh falta, no es ejecutable o tiene errores de sintaxis"; errors=$((errors+1))
  fi

  n=$(ls "$SCRIPT_DIR/commands/"*.md 2>/dev/null | wc -l)
  (( n >= 1 )) && ok "commands: $n" || warn "sin commands (opcional)"

  # Modos: cada output style conserva las instrucciones de código de Claude Code
  local m
  for m in completo intermedio ahorro; do
    if grep -qx 'keep-coding-instructions: true' "$SCRIPT_DIR/output-styles/$m.md" 2>/dev/null; then
      ok "modo $m"
    else
      err "output-styles/$m.md falta o no tiene keep-coding-instructions: true"; errors=$((errors+1))
    fi
  done

  local h
  for h in guard.sh format.sh notify.sh statusline.sh; do
    if [[ -x "$SCRIPT_DIR/hooks/$h" ]]; then
      ok "hooks/$h presente y ejecutable"
    else
      err "FALTA hooks/$h ejecutable"; errors=$((errors+1))
    fi
  done
  if command -v jq &>/dev/null && [[ -x "$SCRIPT_DIR/hooks/test-guard.sh" ]]; then
    if "$SCRIPT_DIR/hooks/test-guard.sh" >/dev/null 2>&1; then
      ok "guard.sh pasa sus tests"
    else
      err "guard.sh FALLA sus tests — corre: ./hooks/test-guard.sh"; errors=$((errors+1))
    fi
  fi

  if [[ -f "$SCRIPT_DIR/.credentials.json" ]]; then
    warn "Hay credenciales DENTRO del bundle — muévelas fuera: no deben vivir en Descargas"
  fi

  if [[ -x "$SCANNER" ]]; then
    if "$SCANNER"; then
      ok "bundle sin tokens ni datos personales"
    else
      err "El bundle tiene datos que no deben ser públicos (ver arriba)"; errors=$((errors+1))
    fi
  fi

  if grep -rEq 'claude-(opus|sonnet|haiku|fable)-?[0-9]' "$SCRIPT_DIR/agents/" 2>/dev/null; then
    warn "Hay IDs de modelo hardcodeados en agents/ — deben usar aliases (opus/sonnet/haiku)"
  else
    ok "agents sin IDs de modelo hardcodeados"
  fi

  verify_plugins || errors=$((errors+1))

  echo ""
  if (( errors > 0 )); then err "Verificación FALLÓ: $errors errores"; return 1; fi
  ok "Bundle íntegro"
}

# ─── plugins de settings.json: coherencia del bundle + qué cargó en esta máquina ─
verify_plugins() {
  command -v jq &>/dev/null || return 0
  local f="$SCRIPT_DIR/settings.json" bad=0 dup id
  jq -e . "$f" >/dev/null 2>&1 || return 0   # el JSON inválido ya se reportó arriba

  # 1. Cada plugin habilitado viene de un marketplace declarado en extraKnownMarketplaces
  while read -r id; do
    err "plugin $id: su marketplace no está en extraKnownMarketplaces"; bad=1
  done < <(jq -r '(.extraKnownMarketplaces // {} | keys) as $m
    | .enabledPlugins // {} | to_entries[] | select(.value == true) | .key
    | select((split("@")[1]) as $k | $m | index($k) | not)' "$f")

  # 2. Sin duplicados: el mismo plugin en dos marketplaces, o un plugin que repite
  #    una skill del bundle o un servidor de mcp/servers.json
  dup="$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key | split("@")[0]' "$f" | sort | uniq -d)"
  [[ -n "$dup" ]] && { err "plugins duplicados en dos marketplaces: $(tr '\n' ' ' <<<"$dup")"; bad=1; }
  while read -r id; do
    [[ -d "$SCRIPT_DIR/skills/$id" ]] && { err "plugin $id repite la skill skills/$id del bundle: deja uno"; bad=1; }
    if [[ -f "$SCRIPT_DIR/mcp/servers.json" ]] && jq -e --arg n "$id" '.mcpServers | has($n)' "$SCRIPT_DIR/mcp/servers.json" >/dev/null; then
      err "plugin $id repite el servidor MCP $id de mcp/servers.json: deja uno"; bad=1
    fi
  done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key | split("@")[0]' "$f")
  (( bad == 0 )) && ok "plugins de settings.json: marketplaces declarados y sin duplicados"

  # 3. En esta máquina: ¿cargaron? Solo avisa, porque verify corre antes de instalarlos.
  if command -v claude &>/dev/null && [[ -f "$CLAUDE_DIR/settings.json" ]]; then
    local list want missing=() broken=() total=0
    list="$(claude plugin list --json 2>/dev/null || echo '[]')"
    while read -r want; do
      total=$((total+1))
      if ! jq -e --arg id "$want" 'any(.[]; .id == $id and .enabled == true)' <<<"$list" >/dev/null; then
        missing+=("$want")
      elif jq -e --arg id "$want" 'any(.[]; .id == $id and ((.errors // []) | length) > 0)' <<<"$list" >/dev/null; then
        broken+=("$want")
      fi
    done < <(merged_settings | jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key')
    if (( ${#missing[@]} == 0 && ${#broken[@]} == 0 )); then
      ok "plugins cargados en esta máquina: $total/$total"
    else
      if (( ${#missing[@]} == total )); then
        warn "plugins: ninguno de los $total instalado todavía → ./install.sh plugins"
      elif (( ${#missing[@]} )); then
        warn "plugins sin instalar o apagados (${#missing[@]}/$total): ${missing[*]} → ./install.sh plugins"
      fi
      (( ${#broken[@]} )) && warn "plugins con errores de carga: ${broken[*]} → claude plugin list"
    fi
  fi
  return $bad
}

# ─── backup: config viva → bundle público + capa privada ─────────────────────
# Regla: el repo es la fuente de verdad. Del ~/.claude vivo solo vuelve:
#   - lo que YA existe en el bundle público → al bundle público
#   - todo lo demás (skills/agents/commands nuevos) → a tu capa privada
# Así nada nuevo se vuelve público sin que tú lo muevas a mano.
# settings.json nunca vuelve solo: el vivo mezcla público + privado + cosas locales.
do_backup() {
  step "Backup: ~/.claude → bundle público + capa privada"
  [[ -d "$CLAUDE_DIR" ]] || { warn "No existe ~/.claude"; return 0; }
  local has_private=0
  [[ -d "$PRIVATE_DIR" ]] && has_private=1
  (( has_private )) || warn "Sin capa privada ($PRIVATE_DIR): lo nuevo no se copia. Créala con: ./install.sh private-init"

  # CLAUDE.md: se parte en la línea marcadora.
  if [[ -f "$CLAUDE_DIR/CLAUDE.md" ]]; then
    awk -v m="$PRIVATE_MARK" '$0==m{exit} {print}' "$CLAUDE_DIR/CLAUDE.md" \
      | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$SCRIPT_DIR/CLAUDE.md"
    ok "CLAUDE.md (parte pública)"
    if (( has_private )) && grep -qxF "$PRIVATE_MARK" "$CLAUDE_DIR/CLAUDE.md"; then
      awk -v m="$PRIVATE_MARK" 'f{print} $0==m{f=1}' "$CLAUDE_DIR/CLAUDE.md" > "$PRIVATE_DIR/CLAUDE.md"
      ok "CLAUDE.md (parte privada → $PRIVATE_DIR)"
    fi
  fi
  [[ -f "$CLAUDE_DIR/WORKFLOW.md" ]] && cp "$CLAUDE_DIR/WORKFLOW.md" "$SCRIPT_DIR/WORKFLOW.md" && ok "WORKFLOW.md"

  # agents, commands, hooks: archivo por archivo.
  local d f name
  for d in agents commands output-styles hooks; do
    [[ -d "$CLAUDE_DIR/$d" ]] || continue
    for f in "$CLAUDE_DIR/$d/"*; do
      [[ -f "$f" && ! -L "$f" ]] || continue
      name="$(basename "$f")"
      if [[ -e "$SCRIPT_DIR/$d/$name" ]]; then
        cp "$f" "$SCRIPT_DIR/$d/$name"
      elif (( has_private )) && [[ "$d" != hooks ]]; then
        mkdir -p "$PRIVATE_DIR/$d" && cp "$f" "$PRIVATE_DIR/$d/$name"
      else
        warn "$d/$name es nuevo y no se copió (muévelo a mano al bundle si debe ser público)"
      fi
    done
    ok "$d/"
  done

  # skills: carpeta por carpeta, misma regla. Los enlaces simbólicos (skills de plugins) se ignoran.
  local s
  if [[ -d "$CLAUDE_DIR/skills" ]]; then
    for s in "$CLAUDE_DIR/skills/"*/; do
      s="${s%/}"; name="$(basename "$s")"
      [[ -L "$s" ]] && continue
      if [[ -d "$SCRIPT_DIR/skills/$name" ]]; then
        rm -rf "$SCRIPT_DIR/skills/$name" && cp -r "$s" "$SCRIPT_DIR/skills/$name"
      elif (( has_private )); then
        mkdir -p "$PRIVATE_DIR/skills"
        rm -rf "$PRIVATE_DIR/skills/$name" && cp -r "$s" "$PRIVATE_DIR/skills/$name"
      else
        warn "skill nueva no copiada: $name"
      fi
    done
    for s in "$SCRIPT_DIR/skills/"*/; do
      name="$(basename "$s")"
      [[ -d "$CLAUDE_DIR/skills/$name" ]] || warn "skill $name está en el bundle pero no en ~/.claude (no se borra sola: bórrala a mano si ya no va)"
    done
    ok "skills/"
  fi

  if [[ -f "$CLAUDE_DIR/settings.json" ]] && command -v jq &>/dev/null; then
    if ! diff -q <(jq -S . "$CLAUDE_DIR/settings.json") <(merged_settings | jq -S .) &>/dev/null; then
      warn "settings.json vivo difiere del repo. No se copia solo (puede llevar tokens en \"env\"). Edita el del repo o el de tu capa privada."
    fi
  fi
  warn "Credenciales, conversaciones y ~/.claude.json NO se copian nunca"
}

# ─── clean: mueve ~/.claude a backup (reversible), borra binarios ────────────
do_clean() {
  step "Limpieza segura de Claude Code"
  # Máquina limpia: no hay nada que mover ni borrar, así que no hace falta preguntar
  # (y `all` funciona sin terminal, por ejemplo con curl | bash en CI).
  if [[ ! -e "$CLAUDE_DIR" && ! -e "$CLAUDE_BIN" && ! -e "$CLAUDE_SHARE" ]]; then
    ok "Nada que limpiar (sin ~/.claude ni binario previo)"
    return 0
  fi
  echo -e "  ~/.claude se MOVERÁ a: ${YELLOW}$BACKUP_DIR/claude-dir${NC} (nada se destruye)"
  echo -e "  Se eliminarán binarios: ${RED}$CLAUDE_BIN${NC}, ${RED}$CLAUDE_SHARE${NC}"
  echo ""

  if [[ "${CLAUDE_YES:-0}" == "1" ]]; then
    REPLY="s"; echo "  → auto-confirmado (CLAUDE_YES=1)"
  else
    REPLY=""; read -r -p "  ¿Confirmar? [s/N] " REPLY < /dev/tty || true; echo ""
  fi
  [[ "$REPLY" =~ ^[SsYy] ]] || { err "Cancelado"; exit 1; }

  if [[ -d "$CLAUDE_DIR" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$CLAUDE_DIR" "$BACKUP_DIR/claude-dir" && ok "~/.claude movido a $BACKUP_DIR/claude-dir"
    echo "$BACKUP_DIR/claude-dir" > "$BACKUP_ROOT/.last-claude-dir"
  else
    warn "~/.claude no existía"
  fi
  rm -f "$CLAUDE_BIN" 2>/dev/null && ok "binario eliminado" || warn "binario no existía"
  rm -rf "$CLAUDE_SHARE" 2>/dev/null && ok "~/.local/share/claude eliminado" || true
}

# ─── install: instalador oficial ─────────────────────────────────────────────
do_install() {
  step "Instalación de Claude Code (instalador oficial)"
  curl -fsSL https://claude.ai/install.sh | bash || warn "El instalador oficial reportó un error, verificando binario..."
  export PATH="$HOME/.local/bin:$PATH"; hash -r 2>/dev/null || true
  if [[ -x "$HOME/.local/bin/claude" ]]; then
    ok "Claude Code instalado: $("$HOME/.local/bin/claude" --version 2>/dev/null || echo ok)"
  else
    err "Instalación no verificable"; exit 1
  fi
}

# ─── deps: bootstrap de máquina recién formateada ────────────────────────────
do_deps() {
  step "Bootstrap de dependencias del sistema"

  # macOS: Homebrew (sin sudo). Linux: apt (con sudo). Otros: a mano.
  if [[ "$OS" == Darwin ]] && ! command -v brew >/dev/null; then
    err "Falta Homebrew. Instálalo desde https://brew.sh y vuelve a correr: ./install.sh deps"
    return 1
  fi

  local pkgs=()
  command -v git  >/dev/null || pkgs+=(git)
  command -v gh   >/dev/null || pkgs+=(gh)
  command -v jq   >/dev/null || pkgs+=(jq)
  command -v curl >/dev/null || pkgs+=(curl)
  if (( ${#pkgs[@]} )); then
    if [[ "$OS" == Darwin ]]; then
      warn "Instalando vía brew: ${pkgs[*]}"
      brew install "${pkgs[@]}"
    elif command -v apt-get >/dev/null; then
      warn "Instalando vía apt (requiere sudo): ${pkgs[*]}"
      sudo apt-get update -qq && sudo apt-get install -y "${pkgs[@]}"
    else
      warn "Sin apt ni brew — instala manualmente: ${pkgs[*]}"
    fi
  else
    ok "git, gh, jq, curl presentes"
  fi

  # Node 24 LTS: brew en macOS, NodeSource oficial en Linux con apt
  local nv=0
  command -v node >/dev/null && nv=$(node --version | sed 's/v//' | cut -d. -f1)
  if (( nv < 24 )); then
    if [[ "$OS" == Darwin ]]; then
      warn "Instalando Node 24 LTS (brew node@24)"
      brew install node@24 && brew link --overwrite --force node@24
    elif command -v apt-get >/dev/null; then
      warn "Instalando Node 24 LTS (NodeSource, requiere sudo)"
      curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && sudo apt-get install -y nodejs
    else
      warn "Instala Node 24 LTS a mano (https://nodejs.org) y vuelve a correr: ./install.sh deps"
    fi
    hash -r 2>/dev/null || true
  fi
  ok "node: $(node --version 2>/dev/null || echo 'reabre la terminal')"

  # pnpm vía corepack (viene con Node). Si Node es de sistema (/usr), el symlink necesita sudo.
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  if ! command -v pnpm >/dev/null; then
    corepack enable pnpm 2>/dev/null || true
    command -v pnpm >/dev/null || sudo env COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack enable pnpm 2>/dev/null || true
    command -v pnpm >/dev/null || sudo npm install -g pnpm >/dev/null 2>&1 || npm install -g pnpm >/dev/null 2>&1 || true
  fi
  if command -v pnpm >/dev/null; then
    ok "pnpm: $(pnpm --version 2>/dev/null)"
  else
    err "pnpm NO se pudo instalar — instálalo a mano: sudo corepack enable pnpm"
  fi

  # uv (necesario para graphify)
  if ! command -v uv >/dev/null; then
    warn "Instalando uv (instalador oficial de Astral)"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
  ok "uv: $(uv --version 2>/dev/null || echo 'reabre la terminal')"

  command -v docker >/dev/null && ok "docker presente" \
    || warn "docker NO instalado (necesario para PostgreSQL/Redis/MinIO locales): https://docs.docker.com/engine/install/"

  if command -v gh >/dev/null && ! gh auth status &>/dev/null; then
    warn "gh sin autenticar — ejecuta después: gh auth login"
  fi
}

# ─── apply_config: aplica el bundle a ~/.claude (núcleo de restore/update) ───
apply_config() {
  mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/output-styles" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/hooks"

  for f in CLAUDE.md WORKFLOW.md; do
    cp "$SCRIPT_DIR/$f" "$CLAUDE_DIR/$f" && ok "$f instalado"
  done

  cp "$SCRIPT_DIR/agents/"*.md "$CLAUDE_DIR/agents/" \
    && ok "agents ($(ls "$CLAUDE_DIR/agents/"*.md | wc -l)): $(ls "$CLAUDE_DIR/agents/" | sed 's/\.md$//' | tr '\n' ' ')"

  if ls "$SCRIPT_DIR/commands/"*.md &>/dev/null; then
    cp "$SCRIPT_DIR/commands/"*.md "$CLAUDE_DIR/commands/" && ok "commands: $(ls "$CLAUDE_DIR/commands/" | tr '\n' ' ')"
  fi

  # Modos de trabajo (completo | intermedio | ahorro): `claude --modo X` o `/output-style X`
  if ls "$SCRIPT_DIR/output-styles/"*.md &>/dev/null; then
    cp "$SCRIPT_DIR/output-styles/"*.md "$CLAUDE_DIR/output-styles/" \
      && ok "modos: $(ls "$SCRIPT_DIR/output-styles/" | sed 's/\.md$//' | tr '\n' ' ')"
  fi

  if [[ -d "$SCRIPT_DIR/hooks" ]]; then
    cp "$SCRIPT_DIR/hooks/"* "$CLAUDE_DIR/hooks/"
    chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true
    ok "hooks instalados (guard.sh activo)"
  fi

  # Skills → ~/.claude/skills/ (nativo). Cada skill del bundle reemplaza a su versión vieja.
  local s name
  for s in "$SCRIPT_DIR/skills/"*/; do
    name="$(basename "$s")"
    rm -rf "$CLAUDE_DIR/skills/$name"
    cp -r "$s" "$CLAUDE_DIR/skills/$name"
  done
  ok "skills instaladas en ~/.claude/skills/ ($(ls -d "$CLAUDE_DIR/skills/"*/ | wc -l))"

  # Skills con motor propio (scripts/package.json, p. ej. mapa-bloque): dependencias fijadas por lockfile
  local pj sk
  for pj in "$CLAUDE_DIR/skills/"*/scripts/package.json; do
    [[ -f "$pj" ]] || continue
    sk="$(basename "$(dirname "$(dirname "$pj")")")"
    if ! command -v pnpm &>/dev/null; then
      warn "sin pnpm: la skill $sk necesita 'pnpm install' en $(dirname "$pj")"
    elif (cd "$(dirname "$pj")" && pnpm install --frozen-lockfile --prod --ignore-scripts --silent); then
      ok "dependencias de la skill $sk instaladas"
    else
      warn "no pude instalar las dependencias de la skill $sk (corre 'pnpm install' en $(dirname "$pj"))"
    fi
  done

  # Migración: elimina el viejo plugin job-skills (las skills ya son nativas)
  if [[ -d "$CLAUDE_DIR/plugins/cache/local/job-skills" ]]; then
    rm -rf "$CLAUDE_DIR/plugins/cache/local/job-skills"
    rm -f "$CLAUDE_DIR/plugins/installed_plugins.json"
    warn "Plugin obsoleto job-skills eliminado (migrado a ~/.claude/skills/)"
  fi

  # Migración: el espejo local de docs (docs/ai-context) se reemplazó por el MCP Context7
  if [[ -L "$CLAUDE_DIR/docs" ]]; then
    rm -f "$CLAUDE_DIR/docs" && warn "Enlace viejo ~/.claude/docs eliminado (ahora se usa Context7)"
  fi

  # Migración: skills retiradas del bundle (Expo/EAS, Auth0 y skill-creator vienen de plugins
  # oficiales; fullstack-standard/v2/v3 se unificaron en `fullstack`)
  local old
  for old in "$CLAUDE_DIR/skills/"expo-* "$CLAUDE_DIR/skills/"eas-* "$CLAUDE_DIR/skills/auth0" "$CLAUDE_DIR/skills/"fullstack-{standard,v2,v3} "$CLAUDE_DIR/skills/skill-creator"; do
    [[ -d "$old" && ! -d "$SCRIPT_DIR/skills/$(basename "$old")" ]] || continue
    rm -rf "$old" && warn "skill retirada: $(basename "$old")"
  done

  # Launcher claude-kimi (Claude Code sobre modelos Kimi). La API key NO viaja en
  # el bundle: vive en ~/.claude/kimi.key (chmod 600, gitignored) o en $KIMI_API_KEY.
  if [[ -f "$SCRIPT_DIR/bin/claude-kimi" ]]; then
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$SCRIPT_DIR/bin/claude-kimi" "$HOME/.local/bin/claude-kimi"
    if [[ -f "$CLAUDE_DIR/kimi.key" ]]; then
      chmod 600 "$CLAUDE_DIR/kimi.key"
      ok "claude-kimi instalado (key en ~/.claude/kimi.key)"
    else
      ok "claude-kimi instalado"
      warn "Falta la key: printf '%s' 'sk-kimi-...' > ~/.claude/kimi.key && chmod 600 ~/.claude/kimi.key"
    fi
  fi

  # shell-init: define la función `claude` para que `claude --kimi` use el otro backend
  if [[ -f "$SCRIPT_DIR/bin/shell-init.sh" ]]; then
    cp "$SCRIPT_DIR/bin/shell-init.sh" "$CLAUDE_DIR/shell-init.sh"
    local rc
    # Un Mac nuevo no trae ~/.zshrc: sin él, `claude --kimi` y el PATH no quedarían listos.
    case "$(basename "${SHELL:-}")" in
      zsh)  [[ -f "$HOME/.zshrc" ]]  || { touch "$HOME/.zshrc"  && ok "creado ~/.zshrc"; } ;;
      bash) [[ -f "$HOME/.bashrc" ]] || { touch "$HOME/.bashrc" && ok "creado ~/.bashrc"; } ;;
    esac
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
      [[ -f "$rc" ]] || continue
      grep -q 'claude/shell-init.sh' "$rc" && continue
      cat >> "$rc" <<'RC'

# Claude Code: `claude` = Anthropic, `claude --kimi` = backend Kimi.
# NO exportes ANTHROPIC_BASE_URL ni ANTHROPIC_API_KEY globalmente: rompe el login oficial.
[ -f "$HOME/.claude/shell-init.sh" ] && . "$HOME/.claude/shell-init.sh"
RC
      ok "shell-init enlazado en $(basename "$rc")"
    done
    ok "shell-init instalado (claude --kimi)"
  fi

  apply_private
  write_settings
}

# ─── write_settings: el kit manda en lo que declara, lo tuyo se queda ───────────
# Las claves que el kit (público + privado) declara se escriben encima: los objetos se
# funden clave por clave y los arrays y valores del kit reemplazan a los tuyos (así un
# permiso que el kit quitó no se queda pegado). Todo lo que el kit no declara (tu
# statusLine, tus variables en "env", un plugin que instalaste a mano) se conserva.
write_settings() {
  local live="$CLAUDE_DIR/settings.json"
  if ! command -v jq &>/dev/null; then
    cp "$SCRIPT_DIR/settings.json" "$live" && warn "jq no instalado: settings.json copiado tal cual (sin capa privada ni tus cambios)"
    return 0
  fi
  if [[ -f "$live" ]] && jq -e 'type == "object"' "$live" >/dev/null 2>&1; then
    jq -s 'def m($a; $b): reduce ($b | keys_unsorted[]) as $k ($a;
             if (.[$k] | type) == "object" and ($b[$k] | type) == "object" then .[$k] = m(.[$k]; $b[$k])
             else .[$k] = $b[$k] end);
           m(.[0]; .[1])' "$live" <(merged_settings) > "$live.tmp" \
      && mv "$live.tmp" "$live" && ok "settings.json actualizado (se conservan tus claves propias)"
  else
    [[ -f "$live" ]] && warn "Tu settings.json no era JSON válido: se reemplaza (la copia queda en el backup)"
    merged_settings > "$live.tmp" && mv "$live.tmp" "$live" && ok "settings.json instalado"
  fi
}

# ─── settings mezclados: público + privado (objetos se funden, arrays se suman) ─
merged_settings() {
  if [[ -f "$PRIVATE_DIR/settings.json" ]]; then
    jq -s 'def m($a; $b): reduce ($b | keys_unsorted[]) as $k ($a;
             if (.[$k] | type) == "object" and ($b[$k] | type) == "object" then .[$k] = m(.[$k]; $b[$k])
             elif (.[$k] | type) == "array" and ($b[$k] | type) == "array" then .[$k] = (.[$k] + ($b[$k] - .[$k]))
             else .[$k] = $b[$k] end);
           m(.[0]; .[1])' "$SCRIPT_DIR/settings.json" "$PRIVATE_DIR/settings.json"
  else
    cat "$SCRIPT_DIR/settings.json"
  fi
}

# ─── apply_private: capa privada ENCIMA del bundle público ───────────────────
apply_private() {
  if [[ ! -d "$PRIVATE_DIR" ]]; then
    warn "Sin capa privada en $PRIVATE_DIR (opcional). Para tus reglas y skills propias: ./install.sh private-init"
    return 0
  fi
  step "Aplicando capa privada: $PRIVATE_DIR"
  if [[ -s "$PRIVATE_DIR/CLAUDE.md" ]]; then
    printf '\n%s\n\n' "$PRIVATE_MARK" >> "$CLAUDE_DIR/CLAUDE.md"
    cat "$PRIVATE_DIR/CLAUDE.md" >> "$CLAUDE_DIR/CLAUDE.md"
    ok "CLAUDE.md privado agregado"
  fi
  [[ -f "$PRIVATE_DIR/settings.json" ]] && ok "settings.json privado: se mezcla al escribir settings.json"
  local d f s
  for d in agents commands; do
    for f in "$PRIVATE_DIR/$d/"*.md; do
      [[ -f "$f" ]] && cp "$f" "$CLAUDE_DIR/$d/"
    done
  done
  for s in "$PRIVATE_DIR/skills/"*/; do
    [[ -d "$s" ]] || continue
    rm -rf "$CLAUDE_DIR/skills/$(basename "$s")"
    cp -r "${s%/}" "$CLAUDE_DIR/skills/"
  done
  ok "agents, commands y skills privados copiados"
}

# ─── restore: bundle → ~/.claude + recupera datos de usuario del último clean ─
do_restore() {
  step "Restaurando configuración desde el bundle"
  do_verify || { err "Bundle inválido — abortando"; exit 1; }
  mkdir -p "$CLAUDE_DIR"

  # Recupera credenciales/historial/proyectos del ~/.claude movido por clean
  local last=""
  [[ -f "$BACKUP_ROOT/.last-claude-dir" ]] && last="$(cat "$BACKUP_ROOT/.last-claude-dir")"
  if [[ -n "$last" && -d "$last" ]]; then
    step "Recuperando datos de usuario desde $last"
    local item
    for item in "${USER_DATA[@]}"; do
      if [[ -e "$last/$item" && ! -e "$CLAUDE_DIR/$item" ]]; then
        cp -r "$last/$item" "$CLAUDE_DIR/$item" && ok "recuperado: $item"
      fi
    done
  fi

  apply_config

  if [[ ! -f "$CLAUDE_DIR/.credentials.json" ]]; then
    warn "Sin credenciales (normal tras formatear): al abrir 'claude' por primera vez haz login"
  fi
}

# ─── update: backup ligero + aplica bundle (sin reinstalar Claude) ───────────
do_update() {
  step "Actualización desde el bundle"
  [[ -d "$CLAUDE_DIR" ]] || { err "No existe ~/.claude. Ejecuta: ./install.sh"; exit 1; }
  do_verify || { err "Bundle inválido — abortando"; exit 1; }

  backup_config
  apply_config
}

# ─── backup_config: copia lo que el kit toca (la usan update, rollback y uninstall) ─
backup_config() {
  step "Backup previo en $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  local f d
  for f in CLAUDE.md WORKFLOW.md settings.json; do
    [[ -f "$CLAUDE_DIR/$f" ]] && cp "$CLAUDE_DIR/$f" "$BACKUP_DIR/"
  done
  for d in agents commands output-styles hooks skills; do
    [[ -d "$CLAUDE_DIR/$d" ]] && cp -r "$CLAUDE_DIR/$d" "$BACKUP_DIR/$d"
  done
  ok "Backup listo"
}

confirm() { # $1 = pregunta. CLAUDE_YES=1 la contesta que sí.
  local reply=""
  if [[ "${CLAUDE_YES:-0}" == "1" ]]; then echo "  → auto-confirmado (CLAUDE_YES=1)"; return 0; fi
  read -r -p "  $1 [s/N] " reply < /dev/tty || true; echo ""
  [[ "$reply" =~ ^[SsYy] ]]
}

# ─── rollback: vuelve a la config que había antes del último update ──────────
# Usa el backup más reciente de update (o el que le pases). Antes respalda lo actual,
# así que un segundo rollback deshace el primero.
do_rollback() {
  step "Rollback de la configuración"
  local src="${1:-}" all d i
  if [[ -z "$src" ]]; then
    all=( "$BACKUP_ROOT"/*/ )
    for (( i=${#all[@]}-1; i>=0; i-- )); do
      d="${all[$i]%/}"
      [[ -f "$d/settings.json" || -f "$d/CLAUDE.md" ]] && { src="$d"; break; }
    done
  fi
  [[ -n "$src" && -d "$src" ]] || { err "No hay backups de update en $BACKUP_ROOT"; return 1; }
  echo -e "  Se restaurará: ${YELLOW}$src${NC} (CLAUDE.md, WORKFLOW.md, settings.json, agents, commands, output-styles, hooks, skills)"
  confirm "¿Confirmar?" || { err "Cancelado"; return 1; }
  backup_config
  local f
  for f in CLAUDE.md WORKFLOW.md settings.json; do
    if [[ -f "$src/$f" ]]; then cp "$src/$f" "$CLAUDE_DIR/$f"; else rm -f "$CLAUDE_DIR/$f"; fi
  done
  for d in agents commands output-styles hooks skills; do
    rm -rf "${CLAUDE_DIR:?}/$d"
    [[ -d "$src/$d" ]] && cp -r "$src/$d" "$CLAUDE_DIR/$d"
  done
  ok "Configuración restaurada desde $src"
  ok "Lo que tenías justo antes quedó en $BACKUP_DIR (otro rollback lo devuelve)"
}

# ─── uninstall: quita lo que puso el kit, con backup ─────────────────────────
# No toca el binario de Claude, tus credenciales, el historial ni tus proyectos.
do_uninstall() {
  step "Desinstalar ai-lordkit"
  [[ -d "$CLAUDE_DIR" ]] || { ok "No existe ~/.claude: nada que quitar"; return 0; }
  echo "  Se quitan los agents, commands, modos, hooks y skills del kit, CLAUDE.md, WORKFLOW.md,"
  echo "  las claves que el kit pone en settings.json, claude-kimi y la línea de tu .zshrc/.bashrc."
  confirm "¿Confirmar? (todo queda en un backup)" || { err "Cancelado"; return 1; }
  backup_config

  local f name d
  for d in agents commands output-styles hooks; do
    for f in "$SCRIPT_DIR/$d/"*; do
      [[ -f "$f" ]] && rm -f "$CLAUDE_DIR/$d/$(basename "$f")"
    done
  done
  for f in "$SCRIPT_DIR/skills/"*/; do
    name="$(basename "$f")"
    rm -rf "${CLAUDE_DIR:?}/skills/$name"
  done
  rm -f "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/WORKFLOW.md" "$CLAUDE_DIR/shell-init.sh" "$HOME/.local/bin/claude-kimi"
  ok "agents, commands, hooks, skills, CLAUDE.md y claude-kimi quitados"

  if [[ -f "$CLAUDE_DIR/settings.json" ]] && command -v jq &>/dev/null; then
    jq --argjson kit "$(merged_settings | jq 'del(."$schema")')" 'def strip($a; $b): reduce ($b | keys_unsorted[]) as $k ($a;
        if (.[$k] | type) == "object" and ($b[$k] | type) == "object"
        then .[$k] = strip(.[$k]; $b[$k]) | (if .[$k] == {} then del(.[$k]) else . end)
        else del(.[$k]) end);
      strip(.; $kit)' \
      "$CLAUDE_DIR/settings.json" > "$CLAUDE_DIR/settings.json.tmp" \
      && mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json" \
      && ok "settings.json: quitadas las claves del kit (las tuyas se quedan)"
  fi

  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ -f "$rc" ]] && grep -q 'claude/shell-init.sh' "$rc" || continue
    grep -vxF -e '# Claude Code: `claude` = Anthropic, `claude --kimi` = backend Kimi.' \
      -e '# NO exportes ANTHROPIC_BASE_URL ni ANTHROPIC_API_KEY globalmente: rompe el login oficial.' \
      -e '[ -f "$HOME/.claude/shell-init.sh" ] && . "$HOME/.claude/shell-init.sh"' "$rc" > "$rc.tmp" \
      && cat "$rc.tmp" > "$rc" && rm -f "$rc.tmp" && ok "quitado de $(basename "$rc")"
  done

  echo ""
  ok "Listo. Backup en $BACKUP_DIR (para volver: ./install.sh rollback)"
  echo "  Los plugins y servidores MCP siguen instalados. Para quitarlos:"
  if command -v jq &>/dev/null; then
    merged_settings | jq -r '.enabledPlugins // {} | to_entries[] | select(.value) | "    claude plugin uninstall \(.key)"'
    jq -r '.mcpServers | keys[] | "    claude mcp remove --scope user \(.)"' "$SCRIPT_DIR/mcp/servers.json"
  fi
  echo "  El kit descargado sigue en $SCRIPT_DIR: bórralo a mano si ya no lo quieres."
}

# ─── harden: seguridad supply-chain de pnpm + Node 24 ────────────────────────
do_harden() {
  step "Endureciendo pnpm y verificando runtime"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

  if ! command -v pnpm &>/dev/null; then
    err "pnpm no instalado. Instala con: corepack enable pnpm"; return 1
  fi

  local pv="$(pnpm --version | cut -d. -f1)"
  if (( pv < 10 )); then
    warn "pnpm $pv es viejo — los lifecycle scripts de dependencias NO están bloqueados. Actualiza a pnpm ≥10."
  else
    ok "pnpm $(pnpm --version): lifecycle scripts de dependencias bloqueados por defecto"
  fi

  # Cuarentena de 7 días para paquetes recién publicados (mitiga paquetes comprometidos)
  pnpm config set minimumReleaseAge 10080 && ok "minimumReleaseAge = 10080 min (7 días)"
  pnpm config set engine-strict true && ok "engine-strict = true (respeta engines.node)"

  if command -v node &>/dev/null; then
    local nv="$(node --version | sed 's/v//' | cut -d. -f1)"
    if (( nv >= 24 )); then ok "Node $(node --version) (≥24)"; else warn "Node $(node --version) — se requiere Node 24 LTS"; fi
  else
    warn "node no instalado"
  fi
}

# ─── graphify: memoria de código (knowledge graph) ───────────────────────────
do_graphify() {
  step "Instalando graphify (grafo de conocimiento del código)"

  if ! command -v uv &>/dev/null; then
    warn "uv no instalado — instálalo desde https://docs.astral.sh/uv/ y reejecuta: ./install.sh graphify"
    return 0
  fi

  uv tool install graphifyy && ok "graphify $(graphify --version 2>/dev/null | head -1)"
  graphify install --platform claude && ok "skill graphify registrada en ~/.claude/skills/"
  echo "  Uso: dentro de Claude Code escribe:  /graphify ."
}

# ─── mcp: registra los servidores de mcp/servers.json (+ mcp.json privado) ───
# Los ${VAR} se rellenan con tu entorno al instalar. Si falta una variable, ese
# servidor se salta. El valor queda solo en ~/.claude.json de esta máquina.
do_mcp() {
  step "Servidores MCP"
  command -v claude &>/dev/null || { warn "claude no está en PATH — reintenta: ./install.sh mcp"; return 0; }
  command -v jq &>/dev/null || { warn "jq no instalado — reintenta: ./install.sh mcp"; return 0; }
  local existing file name cfg missing
  existing="$(claude mcp list 2>/dev/null || true)"
  for file in "$SCRIPT_DIR/mcp/servers.json" "$PRIVATE_DIR/mcp.json"; do
    [[ -f "$file" ]] || continue
    while read -r name; do
      if grep -q "^$name:" <<<"$existing"; then ok "$name ya estaba"; continue; fi
      cfg="$(jq -c --arg n "$name" '.mcpServers[$n]' "$file")"
      missing="$({ grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' <<<"$cfg" || true; } | tr -d '${}' | sort -u \
        | while read -r v; do [[ -n "${!v:-}" ]] || printf '%s ' "$v"; done)"
      if [[ -n "$missing" ]]; then
        warn "$name saltado: falta $missing(exporta la variable y corre ./install.sh mcp)"
        continue
      fi
      cfg="$(jq -c 'walk(if type == "string" then gsub("\\$\\{(?<v>[A-Za-z_][A-Za-z0-9_]*)\\}"; env[.v]) else . end)' <<<"$cfg")"
      claude mcp add-json --scope user "$name" "$cfg" >/dev/null && ok "$name agregado" || warn "No se pudo agregar $name"
    done < <(jq -r '.mcpServers | keys[]' "$file")
  done
}
do_context7() { do_mcp; }

# ─── plugins: marketplaces + plugins declarados en settings.json (+ capa privada) ─
# Claude Code registra extraKnownMarketplaces al abrir una sesión, pero `claude plugin`
# desde la terminal no: por eso se agregan aquí y luego se instala cada plugin habilitado.
do_plugins() {
  step "Plugins"
  command -v claude &>/dev/null || { warn "claude no está en PATH — reintenta: ./install.sh plugins"; return 0; }
  command -v jq &>/dev/null || { warn "jq no instalado — reintenta: ./install.sh plugins"; return 0; }
  local settings known installed name repo sparse id
  settings="$(merged_settings)"
  known="$(claude plugin marketplace list --json 2>/dev/null | jq -r '.[].name' || true)"
  while IFS=$'\t' read -r name repo sparse; do
    if grep -qx "$name" <<<"$known"; then ok "marketplace $name ya estaba"; continue; fi
    # shellcheck disable=SC2086  # sparse: lista de carpetas separadas por espacio
    if claude plugin marketplace add "$repo" ${sparse:+--sparse $sparse} >/dev/null 2>&1; then
      ok "marketplace $name agregado ($repo)"
    else
      warn "No se pudo agregar el marketplace $name ($repo) — reintenta: claude plugin marketplace add $repo"
    fi
  done < <(jq -r '.extraKnownMarketplaces // {} | to_entries[]
    | select(.value.source.source == "github")
    | [.key, .value.source.repo, ((.value.source.sparsePaths // []) | join(" "))] | @tsv' <<<"$settings")
  # `marketplace add` reescribe la entrada en ~/.claude/settings.json sin autoUpdate ni
  # sparsePaths: se restauran las del bundle para que sigan actualizándose solas.
  if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
    jq --argjson m "$(jq -c '.extraKnownMarketplaces // {}' <<<"$settings")" \
      '.extraKnownMarketplaces = ((.extraKnownMarketplaces // {}) + $m)' "$CLAUDE_DIR/settings.json" \
      > "$CLAUDE_DIR/settings.json.tmp" && mv "$CLAUDE_DIR/settings.json.tmp" "$CLAUDE_DIR/settings.json"
  fi

  installed="$(claude plugin list --json 2>/dev/null | jq -r '.[].id' || true)"
  while read -r id; do
    if grep -qx "$id" <<<"$installed"; then ok "$id ya estaba"; continue; fi
    if claude plugin install "$id" >/dev/null 2>&1; then
      ok "$id instalado"
    else
      warn "No se pudo instalar $id — reintenta: claude plugin install $id"
    fi
  done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' <<<"$settings")
}

# ─── sync: backup → escaneo → commit → push ──────────────────────────────────
# Público: solo rutas del bundle (nunca `git add -A`), escaneo completo, y si estás en
# main se sube a una rama sync/<fecha> para que entre por PR.
# Privado: escaneo de tokens (los nombres sí pueden estar) y push directo a su rama.
do_sync() {
  step "Sync: ~/.claude → repos"
  do_backup

  local paths=(CLAUDE.md WORKFLOW.md agents commands output-styles hooks skills)
  git -C "$SCRIPT_DIR" add -- "${paths[@]}"
  if git -C "$SCRIPT_DIR" diff --cached --quiet; then
    ok "Bundle público sin cambios"
  elif ! "$SCANNER" --staged; then
    git -C "$SCRIPT_DIR" reset -q
    err "Sync ABORTADO: el bundle público tiene datos que no deben salir (ver arriba)."
    err "Muévelos a tu capa privada o agrégalos a scripts/scan-allowlist.txt si son ejemplos."
    return 1
  else
    local branch
    branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD)"
    if [[ "$branch" == main || "$branch" == master ]]; then
      branch="sync/$TS"
      git -C "$SCRIPT_DIR" switch -q -c "$branch"
    fi
    git -C "$SCRIPT_DIR" commit -q -m "chore(config): sync $(date +%Y-%m-%d\ %H:%M)" && ok "Commit en $branch"
    if git -C "$SCRIPT_DIR" push -q -u origin "$branch"; then
      ok "Subido a $branch. Abre el PR con: gh pr create --fill --head $branch"
    else
      warn "No se pudo subir (¿sin permiso de push? usa tu fork)"
    fi
  fi

  if [[ -d "$PRIVATE_DIR/.git" ]]; then
    git -C "$PRIVATE_DIR" add -A
    if git -C "$PRIVATE_DIR" diff --cached --quiet; then
      ok "Capa privada sin cambios"
    elif ! "$SCANNER" --root "$PRIVATE_DIR" --staged --only-secrets; then
      git -C "$PRIVATE_DIR" reset -q
      err "Sync privado ABORTADO: hay algo que parece un token. Los tokens no van en ningún repo."
      return 1
    else
      git -C "$PRIVATE_DIR" commit -q -m "chore: sync $(date +%Y-%m-%d\ %H:%M)" && ok "Commit en la capa privada"
      git -C "$PRIVATE_DIR" push -q -u origin HEAD 2>/dev/null && ok "Capa privada subida" \
        || warn "Capa privada sin remoto: git -C $PRIVATE_DIR remote add origin <tu-repo-privado>"
    fi
  fi
}

# ─── private-init: crea la capa privada desde la plantilla ───────────────────
do_private_init() {
  step "Capa privada en $PRIVATE_DIR"
  if [[ -d "$PRIVATE_DIR" ]]; then
    ok "Ya existe, no se toca"
    return 0
  fi
  cp -r "$SCRIPT_DIR/private-template" "$PRIVATE_DIR"
  mkdir -p "$PRIVATE_DIR/skills" "$PRIVATE_DIR/agents" "$PRIVATE_DIR/commands"
  git -C "$PRIVATE_DIR" init -q -b main && ok "Creada con git init"
  echo "  1. Pon tus reglas en $PRIVATE_DIR/CLAUDE.md y tus términos en private-terms.txt"
  echo "  2. Crea un repo PRIVADO en GitHub y conéctalo:"
  echo "       git -C $PRIVATE_DIR remote add origin git@github.com:<tu-usuario>/ai-lordkit-private.git"
  echo "  3. ./install.sh update"
}

# ─── scan: busca tokens, datos personales y términos privados ────────────────
do_scan() {
  step "Escaneando el bundle"
  "$SCANNER" "$@"
}

# ─── doctor ──────────────────────────────────────────────────────────────────
do_doctor() {
  step "Verificando pre-requisitos del sistema"

  command -v git &>/dev/null && ok "git: $(git --version)" || err "git NO instalado"

  if command -v gh &>/dev/null; then
    ok "gh CLI: $(gh --version | head -1)"
    gh auth status &>/dev/null && ok "gh autenticado" || warn "gh NO autenticado: gh auth login"
  else
    err "gh CLI NO instalado ($PKG_HINT gh)"
  fi

  local gu ge gk gs
  gu=$(git config --global --get user.name 2>/dev/null || echo "")
  ge=$(git config --global --get user.email 2>/dev/null || echo "")
  gk=$(git config --global --get user.signingkey 2>/dev/null || echo "")
  gs=$(git config --global --get commit.gpgsign 2>/dev/null || echo "")
  [[ -n "$gu" && -n "$ge" ]] && ok "git config: $gu <$ge>" || warn "git config global incompleto (user.name/user.email)"
  [[ -n "$gk" && "$gs" == "true" ]] && ok "firma de commits activa" || warn "firma de commits NO configurada (ver CHECKLIST.md)"

  if command -v node &>/dev/null; then
    local nv="$(node --version | sed 's/v//' | cut -d. -f1)"
    (( nv >= 24 )) && ok "node: $(node --version)" || warn "node $(node --version) — se requiere 24 LTS"
  else
    err "node NO instalado"
  fi

  if command -v pnpm &>/dev/null; then
    ok "pnpm: $(pnpm --version)"
    local mra="$(pnpm config get minimumReleaseAge 2>/dev/null || echo "")"
    [[ -n "$mra" && "$mra" != "undefined" ]] && ok "supply-chain: minimumReleaseAge=$mra" || warn "sin minimumReleaseAge — corre: ./install.sh harden"
  else
    err "pnpm NO instalado"
  fi

  command -v jq &>/dev/null && ok "jq: $(jq --version)" || err "jq NO instalado — los hooks (guard/prettier) lo necesitan: $PKG_HINT jq"
  command -v docker &>/dev/null && ok "docker: $(docker --version | cut -d, -f1)" || warn "docker NO instalado"
  command -v uv &>/dev/null && ok "uv: $(uv --version)" || warn "uv NO instalado (necesario para graphify)"
  command -v graphify &>/dev/null && ok "graphify: $(graphify --version 2>/dev/null | head -1)" || warn "graphify NO instalado: ./install.sh graphify"
  command -v claude &>/dev/null && ok "claude: $(claude --version 2>/dev/null || echo instalado)" || warn "claude NO en PATH (hash -r)"
  # claude-mem salió del kit (su observer ahora es de pago o gasta tu plan). Si quedó de antes, avisa.
  if command -v claude &>/dev/null && claude plugin list --json 2>/dev/null \
       | jq -e 'any(.[]; .id == "claude-mem@thedotmack")' >/dev/null 2>&1; then
    warn "claude-mem sigue instalado y el kit ya no lo usa: claude plugin uninstall claude-mem@thedotmack"
  fi

  [[ -x "$CLAUDE_DIR/hooks/guard.sh" ]] && ok "guard.sh activo (bloqueo de comandos destructivos)" || warn "guard.sh NO instalado — corre: ./install.sh update"
}

# ─── summary ─────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  ¡Operación completa!${NC}"
  echo -e "${BOLD}══════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}Subagents ($(ls "$CLAUDE_DIR/agents/"*.md 2>/dev/null | wc -l)) — modelos por alias, se auto-actualizan:${NC}"
  local a name model
  for a in "$CLAUDE_DIR/agents/"*.md; do
    name=$(basename "$a" .md)
    model=$(grep -m1 '^model:' "$a" | awk '{print $2}')
    printf "    • %-26s %s\n" "$name" "$model"
  done
  echo ""
  echo -e "  ${BOLD}Seguridad:${NC}"
  echo -e "    • guard.sh: bloquea borrados recursivos peligrosos, pipes remotos a shell,"
  echo -e "      force-push, push a main y lectura de archivos de entorno o llaves"
  echo -e "    • pnpm: cuarentena de 7 días para paquetes nuevos + scripts bloqueados"
  echo ""
  echo -e "  ${BOLD}Memoria:${NC} auto-memory + mem-search (historial) + graphify (/graphify .) + memory-bank"
  echo ""
  echo -e "  ${BOLD}Skills:${NC} $(ls -d "$CLAUDE_DIR/skills/"*/ 2>/dev/null | wc -l) en ~/.claude/skills/ (nativas, sin plugin)"
  echo ""
  echo -e "  ${BOLD}Próximos pasos:${NC}"
  echo -e "    1. Nueva terminal (o hash -r)"
  echo -e "    2. ${GREEN}claude /agents${NC}  → deben aparecer $(ls "$CLAUDE_DIR/agents/"*.md 2>/dev/null | wc -l) subagents"
  echo -e "    3. ${GREEN}claude /status${NC}  → verifica modelo"
  echo ""
}

# ─── main ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Claude Code — instalador v2${NC}"
echo -e "Bundle: ${BLUE}$SCRIPT_DIR${NC}"

case "${1:-all}" in
  verify)    do_verify ;;
  backup)    do_backup ;;
  clean)     do_clean ;;
  deps)      do_deps ;;
  install)   do_install ;;
  restore)   do_restore; print_summary ;;
  update)    do_update; do_mcp; do_plugins; do_doctor; print_summary ;;
  harden)    do_harden ;;
  graphify)  do_graphify ;;
  context7|mcp) do_mcp ;;
  plugins)   do_plugins ;;
  sync)      do_sync ;;
  private-init) do_private_init ;;
  scan)      shift; do_scan "$@" ;;
  doctor)    do_doctor ;;
  rollback)  shift; do_rollback "$@" ;;
  uninstall) do_uninstall ;;
  all)
    # verify/clean/install/restore son críticos (abortan si fallan);
    # harden/graphify/doctor son mejoras: si una falla, el resto continúa.
    do_verify
    do_deps    || warn "deps incompleto — revisa arriba y reintenta: ./install.sh deps"
    do_clean
    do_install
    do_restore
    do_harden    || warn "harden falló — reintenta: ./install.sh harden"
    do_graphify  || warn "graphify falló — reintenta: ./install.sh graphify"
    do_mcp       || warn "mcp falló — reintenta: ./install.sh mcp"
    do_plugins   || warn "plugins falló — reintenta: ./install.sh plugins"
    do_doctor    || true
    print_summary
    ;;
  *)
    echo "Uso: $0 [all|verify|backup|clean|deps|install|restore|update|rollback|uninstall|harden|graphify|mcp|plugins|sync|private-init|scan|doctor]"
    echo ""
    echo "  all       → instalación completa desde cero (máquina formateada): deps + install + restore + harden + graphify"
    echo "  deps      → instala pre-requisitos del sistema (git, gh, jq, Node 24, pnpm, uv)"
    echo "  update    → aplica el bundle a ~/.claude sin reinstalar (con backup)"
    echo "  backup    → sincroniza la config viva HACIA el bundle (espejo)"
    exit 1
    ;;
esac
