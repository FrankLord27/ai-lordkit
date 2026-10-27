#!/usr/bin/env bash
# Hook PreToolUse (Bash): bloquea comandos destructivos o que filtran secretos ANTES de ejecutarse.
# Es la red final: en modo auto el clasificador puede aprobar comandos que no están en la lista
# allow, y las reglas deny de settings.json solo cubren patrones de prefijo.
# Exit 2 = bloquear el comando (el mensaje en stderr llega a Claude).

deny() {
  echo "guard.sh BLOQUEÓ este comando: $1. Si de verdad hace falta, el usuario debe correrlo a mano." >&2
  exit 2
}

# Falla CERRADO: sin jq no podemos inspeccionar el comando, así que no lo dejamos pasar.
command -v jq >/dev/null 2>&1 || deny "jq no está instalado y el guard no puede validar (sudo apt install jq)"

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
[[ "$tool" == "Bash" ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[[ -n "$cmd" ]] || exit 0

# Opciones globales de git (`git -C dir`, `git -c k=v`, `--git-dir=...`) van antes del
# subcomando y esconderían `git push`. Se quitan para comparar; el -C se guarda para
# saber en qué rama está ese repo.
git_dir=$(grep -Eo 'git[[:space:]]+(-c[[:space:]]+[^[:space:]]+[[:space:]]+)*-C[[:space:]]+[^[:space:];&|]+' <<<"$cmd" | head -1 | sed -E 's/.*-C[[:space:]]+//; s/^["'"'"']//; s/["'"'"']$//')
while :; do  # un paso por opción (sed portable: sin \b ni etiquetas, que BSD sed no entiende)
  next=$(sed -E 's/(^|[^A-Za-z0-9_-])git[[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)(=|[[:space:]]+)[^[:space:]]+/\1git/' <<<"$cmd")
  [[ "$next" == "$cmd" ]] && break
  cmd="$next"
done
if [[ -n "$git_dir" && "$git_dir" != /* ]]; then git_dir="${cwd:-.}/$git_dir"; fi

block() { grep -Eq -- "$1" <<<"$cmd" && deny "$2"; }

# ── Borrados ────────────────────────────────────────────────────────────────
if grep -Eq '\brm\b' <<<"$cmd" && grep -Eq '\brm\b[^|;&]*(\s-[a-zA-Z]*[rR]|--recursive)' <<<"$cmd"; then
  block '\brm\b[^|;&]*\s["'"'"']?(/|~|\$HOME|\$\{HOME\})/?\*?["'"'"']?(\s|$)' "rm recursivo sobre / o \$HOME"
fi
block '\brm\b[^|;&]*--no-preserve-root'                          "rm --no-preserve-root"
block '\brm\b[^|;&]*(~|\$HOME|\$\{HOME\})/\.claude/?["'"'"']?(\s|$)' "rm de ~/.claude completo"
block '\brm\b[^|;&]*\.credentials\.json'                         "rm de credenciales"
block '\bsudo\s+rm\b'                                            "sudo rm"

# ── Sistema ────────────────────────────────────────────────────────────────
block '\bdd\b[^|;&]*of=/dev/'                                    "dd hacia un dispositivo"
block '\bmkfs(\.| )'                                             "mkfs (formatear disco)"
block '\b(shutdown|reboot|poweroff|halt)\b'                      "apagado/reinicio del sistema"
block 'chmod\s+(-R\s+)?777\s+/'                                  "chmod 777 sobre raíz"
block ':\(\)\s*\{\s*:\s*\|\s*:'                                  "fork bomb"
block '>\s*/dev/(sd[a-z]|nvme)'                                  "escritura directa a disco"
block '(curl|wget)[^|;&]*\|\s*(sudo\s+)?(ba|z|da)?sh\b'          "curl/wget pipeado a shell"
block '\bdocker\s+run\b[^|;&]*(--privileged|-v\s*/:|--volume[= ]/:)' "docker run con privilegios o montando /"

# ── Secretos ───────────────────────────────────────────────────────────────
# Los .env.example/.sample/.template sí se permiten. sed -E sin \b ni \s: BSD sed (macOS) no los entiende.
# Cualquier mención de un .env cuenta como lectura, sin importar el programa (node -e,
# python -c, tac, find -exec...): una lista de lectores nunca está completa. Se permiten
# solo los usos que no muestran su contenido: escribirlo (`cp x .env`, `> .env`),
# comprobar que existe (`-f .env`) y pasárselo a docker compose (`--env-file .env`).
envf='\.env(\.[A-Za-z0-9_-]+)?'
end='([^A-Za-z0-9_.-]|$)'
scrubbed=$(sed -E \
  -e "s#(^|[^A-Za-z0-9_])(cp|mv)([[:space:]]+-[A-Za-z]+)*[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]*/)?$envf$end#\\1\\6#g" \
  -e 's/\.env\.(example|sample|template|dist)([^A-Za-z0-9_]|$)/\2/g' \
  -e "s#>>?[[:space:]]*([^[:space:]]*/)?$envf$end#\\3#g" \
  -e "s#-[fes][[:space:]]+([^[:space:]]*/)?$envf$end#\\3#g" \
  -e "s#--env-file(=|[[:space:]]+)([^[:space:]]*/)?$envf$end#\\4#g" \
  <<<"$cmd")
if grep -Eq "(^|[[:space:]/\"'=@(\`])$envf([^A-Za-z0-9_.-]|\$)" <<<"$scrubbed"; then
  deny "lectura o envío de un archivo .env (usa .env.example para ver los nombres de variables)"
fi
block '\b(cat|less|head|tail|base64|curl|scp)\b[^|;&]*(\.ssh/|\.aws/|\.gnupg/|\.credentials\.json|kimi\.key|\.pem\b|id_(rsa|ed25519))' "lectura o envío de llaves/credenciales"
block '(^|[;&|]\s*)(printenv|env)\s*($|\|)'                     "volcado completo de variables de entorno"

# ── Git ────────────────────────────────────────────────────────────────────
block 'git\s+push\b[^|;&]*(--force\b|--force-with-lease\b|\s-f\b|\s\+[^ ]+)' "git push forzado"
block 'git\s+push\b[^|;&]*(\s|:)(refs/heads/)?(main|master)(\s|$)'          "push directo a main/master (usa PR)"
block 'git\s+reset\s+--hard\s+origin/'                                      "git reset --hard contra origin"

# `git push` sin refspec estando en main/master también empuja a main.
if grep -Eq '(^|[;&|]\s*)git\s+push\b' <<<"$cmd"; then
  args=$(grep -Eo 'git\s+push\b[^|;&]*' <<<"$cmd" | head -1 | sed -E 's/^git[[:space:]]+push//')
  positional=$(tr ' ' '\n' <<<"$args" | grep -Ev '^(-|$)' | wc -l)
  if (( positional <= 1 )); then
    branch=$(git -C "${git_dir:-${cwd:-.}}" symbolic-ref --short HEAD 2>/dev/null || true)
    [[ "$branch" == "main" || "$branch" == "master" ]] && deny "git push estando en $branch (crea una rama y abre PR)"
  fi
fi

exit 0
