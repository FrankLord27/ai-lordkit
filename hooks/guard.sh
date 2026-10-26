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
# Leer o enviar archivos .env (los .env.example/.sample/.template sí se permiten).
scrubbed=$(sed -E 's/\.env\.(example|sample|template|dist)\b//g' <<<"$cmd")
if grep -Eq '\b(cat|less|more|head|tail|bat|nl|grep|egrep|rg|ag|awk|sed|cut|sort|strings|xxd|od|base64|source|curl|wget|scp|rsync|nc)\b[^|;&]*(^|[[:space:]/"'"'"'=@])\.env(\.[A-Za-z0-9_-]+)?([[:space:]"'"'"']|$)' <<<"$scrubbed" \
   || grep -Eq '(^|[;&|]\s*)\.\s+[^|;&]*\.env\b' <<<"$scrubbed"; then
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
  args=$(grep -Eo 'git\s+push\b[^|;&]*' <<<"$cmd" | head -1 | sed -E 's/^git\s+push//')
  positional=$(tr ' ' '\n' <<<"$args" | grep -Ev '^(-|$)' | wc -l)
  if (( positional <= 1 )); then
    branch=$(git -C "${cwd:-.}" symbolic-ref --short HEAD 2>/dev/null || true)
    [[ "$branch" == "main" || "$branch" == "master" ]] && deny "git push estando en $branch (crea una rama y abre PR)"
  fi
fi

exit 0
