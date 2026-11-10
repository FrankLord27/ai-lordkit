#!/usr/bin/env bash
# Hook PreToolUse (Bash): bloquea comandos destructivos o que filtran secretos ANTES de ejecutarse.
# Exit 2 = bloquear el comando (el mensaje en stderr llega a Claude).
#
# Cómo decide: NO compara regex contra el texto crudo. Primero parte el comando como lo
# haría el shell (comillas, escapes, `;` `&&` `|`, `$(...)`, `<(...)`, backticks, here-docs,
# `bash -c '...'`, `eval`) y después aplica las reglas a cada comando por separado, mirando
# el PROGRAMA y sus ARGUMENTOS ya sin comillas. Así `git push origin "main"` se bloquea y
# `git commit -m "docs: no uses git push --force"` no.
#
# Límite conocido: no expande variables ni alias (`f=.en; cat ${f}v`, `git p origin main`).
# Es una red de seguridad, no un sandbox: la barrera principal son los permisos de
# settings.json. Compatible con bash 3.2 (macOS) y Git Bash.
# shellcheck disable=SC2088  # "~" es un marcador de ruta normalizada: no se expande, a propósito

deny() {
  echo "guard.sh BLOQUEÓ este comando: $1. Si de verdad hace falta, el usuario debe correrlo a mano." >&2
  exit 2
}

# Falla CERRADO: sin jq no podemos inspeccionar el comando, así que no lo dejamos pasar.
command -v jq >/dev/null 2>&1 || deny "jq no está instalado y el guard no puede validar (sudo apt install jq)"
# Windows (Git Bash): jq.exe termina las líneas en CRLF; se quita el \r para que las comparaciones no fallen.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; } ;; esac

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")
[[ "$tool" == "Bash" ]] || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[[ -n "$cmd" ]] || exit 0

# Git Bash en Windows: cwd llega como C:\... y las rutas absolutas empiezan por "C:/", no por "/".
if command -v cygpath >/dev/null 2>&1 && [[ -n "$cwd" ]]; then cwd=$(cygpath -u "$cwd"); fi

# ── 1. Partir el comando en segmentos ───────────────────────────────────────
# Cada segmento es un comando simple: sus palabras van unidas por US en SEG_WORDS[i].
# SEG_CONN = qué lo precede (`;` `&` `|` `(` `$(`), SEG_PREV = el comando anterior de la
# tubería, SEG_PARENT = el comando que contiene la sustitución `$(...)` donde vive.
US=$'\037'
SEG_WORDS=(); SEG_CONN=(); SEG_PARENT=(); SEG_PREV=(); SEG_PROG=(); SEG_SUDO=()
HD_SEG=(); HD_BODY=()
nseg=0

parse() { # $1 = texto, $2 = segmento padre (-1 si no hay)
  local s="$1" n=${#1} i=0 c nx w="" hw=0 q="" cur=0 sp=0 j d line rest used body
  local st_cur=() st_w=() st_q=() st_type=() pend_d=() pend_s=()
  _new()  { SEG_WORDS[nseg]=""; SEG_CONN[nseg]="$1"; SEG_PARENT[nseg]="$2"; SEG_PREV[nseg]="$3"; cur=$nseg; nseg=$((nseg+1)); }
  _endw() { if ((hw)); then SEG_WORDS[cur]+="$w$US"; fi; w=""; hw=0; }
  _sep()  { _endw; _new "$1" "${SEG_PARENT[cur]}" "$cur"; }
  _open() { st_cur[sp]=$cur; st_w[sp]="$w"; st_q[sp]="$q"; st_type[sp]="$1"; sp=$((sp+1))
            _new '$(' "$cur" -1; w=""; hw=0; q=""; }
  _close(){ _endw; sp=$((sp-1)); cur=${st_cur[sp]}; w="${st_w[sp]}\$(…)"; hw=1; q="${st_q[sp]}"; }
  _bt()   { if ((sp>0)) && [[ "${st_type[sp-1]}" == '`' ]]; then _close; else _open '`'; fi; }

  _new ';' "$2" -1
  while ((i<n)); do
    c="${s:i:1}"; nx="${s:i+1:1}"
    if [[ "$q" == "'" ]]; then
      if [[ "$c" == "'" ]]; then q=""; else w+="$c"; fi
      i=$((i+1)); continue
    fi
    if [[ "$q" == '"' ]]; then
      case "$c" in
        '"') q="" ;;
        '\') case "$nx" in '$'|'`'|'"'|'\') w+="$nx"; i=$((i+1)) ;; $'\n') i=$((i+1)) ;; *) w+="$c" ;; esac ;;
        '$') if [[ "$nx" == "(" ]]; then _open '$('; i=$((i+1)); else w+="$c"; fi ;;
        '`') _bt ;;
        *)   w+="$c" ;;
      esac
      i=$((i+1)); continue
    fi
    case "$c" in
      "'"|'"') q="$c"; hw=1 ;;
      '\') if [[ "$nx" != $'\n' ]]; then w+="$nx"; hw=1; fi; i=$((i+1)) ;;
      ' '|$'\t') _endw ;;
      $'\n')
        _sep ';'
        # Here-docs pendientes: su cuerpo no es un comando (salvo que alimente a un shell, ver analyze).
        j=0
        while ((j<${#pend_d[@]})); do
          rest="${s:i+1}"; used=0; d="${pend_d[j]}"; body=""
          while IFS= read -r line || [[ -n "$line" ]]; do
            used=$((used+${#line}+1))
            [[ "${line#"${line%%[!$'\t']*}"}" == "$d" ]] && break
            body+="$line"$'\n'
          done <<<"$rest"
          HD_SEG[${#HD_SEG[@]}]="${pend_s[j]}"; HD_BODY[${#HD_BODY[@]}]="$body"
          i=$((i+used)); j=$((j+1))
        done
        pend_d=(); pend_s=() ;;
      ';') _sep ';' ;;
      '&') if [[ "$nx" == '&' ]]; then i=$((i+1)); _sep '&'
           elif [[ "$nx" == '>' ]]; then :   # &> es una redirección
           else _sep '&'; fi ;;
      '|') if [[ "$nx" == '|' ]]; then i=$((i+1)); _sep '&'
           elif [[ "$nx" == '&' ]]; then i=$((i+1)); _sep '|'
           else _sep '|'; fi ;;
      '(') _sep '(' ;;
      ')') if ((sp>0)) && [[ "${st_type[sp-1]}" == '$(' ]]; then _close; else _sep ';'; fi ;;
      '`') _bt ;;
      '$') if [[ "$nx" == "(" ]]; then _open '$('; i=$((i+1)); else w+="$c"; hw=1; fi ;;
      '<'|'>')
        if [[ "$nx" == "(" ]]; then _open '$('; i=$((i+1))
        elif [[ "$c" == '<' && "$nx" == '<' && "${s:i+2:1}" != '<' ]]; then
          # here-doc: lee el delimitador y deja el cuerpo para el próximo salto de línea
          _endw; j=$((i+2)); [[ "${s:j:1}" == '-' ]] && j=$((j+1))
          while [[ "${s:j:1}" == ' ' || "${s:j:1}" == $'\t' ]]; do j=$((j+1)); done
          d=""
          while ((j<n)); do
            case "${s:j:1}" in ' '|$'\t'|$'\n'|';'|'|'|'&'|'<'|'>'|')') break ;; "'"|'"'|'\') ;; *) d+="${s:j:1}" ;; esac
            j=$((j+1))
          done
          if [[ -n "$d" ]]; then pend_d[${#pend_d[@]}]="$d"; pend_s[${#pend_s[@]}]=$cur; fi
          i=$((j-1))
        else
          _endw; SEG_WORDS[cur]+="$c$US"
          while [[ "${s:i+1:1}" == '<' || "${s:i+1:1}" == '>' || "${s:i+1:1}" == '&' || "${s:i+1:1}" == '|' ]]; do i=$((i+1)); done
        fi ;;
      '#') if ((hw)); then w+="$c"; else
             while ((i+1<n)) && [[ "${s:i+1:1}" != $'\n' ]]; do i=$((i+1)); done
           fi ;;
      *) w+="$c"; hw=1 ;;
    esac
    i=$((i+1))
  done
  _endw
}

# ── 2. Utilidades ───────────────────────────────────────────────────────────
is_shell()  { case "$1" in sh|bash|zsh|dash|ksh|fish|ash) return 0 ;; esac; return 1; }
is_interp() { is_shell "$1" && return 0
              case "$1" in python|python2|python3|node|nodejs|deno|bun|perl|ruby|php|source|.|eval) return 0 ;; esac; return 1; }

# Normaliza una ruta para compararla: ~, $HOME, ${HOME…} y el HOME real pasan a "~";
# se quitan los finales /, /*, /. ; la raíz queda como "/".
norm_path() {
  local p="$1" prev
  case "$p" in
    '~'|'~/'*)      p="~${p#\~}" ;;
    '$HOME'*)       p="~${p#\$HOME}" ;;
    '${HOME'*'}'*)  p="~${p#*\}}" ;;
    *) if [[ -n "${HOME:-}" && "$HOME" != "/" && ( "$p" == "$HOME" || "$p" == "$HOME"/* ) ]]; then p="~${p#"$HOME"}"; fi ;;
  esac
  while :; do
    prev="$p"
    p="${p%/}"; p="${p%/\*}"; p="${p%/.}"
    [[ "$p" == "$prev" ]] && break
  done
  [[ -z "$p" ]] && p="/"
  printf '%s' "$p"
}
# Rutas que nunca se borran ni se abren de permisos en bloque.
danger_re='^(/|~|/home|/Users|/root|/(home|Users)/[^/]+|~/[^/]+|/(etc|usr|var|boot|bin|sbin|lib|lib64|opt|srv|sys|proc|dev|run|mnt|media))$'
danger_path() { [[ "$1" =~ $danger_re ]]; }
win_root_re='^([A-Za-z]:[/\\]*|/[A-Za-z]/?)\*?$'
win_user_re='^(/[A-Za-z]/Users/[^/]+|[A-Za-z]:[/\\]*Users[/\\]*[^/\\]+|\$USERPROFILE|\$\{USERPROFILE\}|%USERPROFILE%)[/\\]*\*?$'

# ¿La palabra nombra un archivo .env real? (.env.example/.sample/.template/.dist no cuentan)
env_re='(^|[^A-Za-z0-9_])\.env([.-][A-Za-z0-9_-]+)*([^A-Za-z0-9_.-]|$)'
envx_re='[A-Za-z0-9_*?]\.env$'
mentions_env() {
  local t="$1" base
  t="${t//.env.example/}"; t="${t//.env.sample/}"; t="${t//.env.template/}"; t="${t//.env.dist/}"
  [[ "$t" =~ $env_re ]] && return 0
  [[ "$t" =~ $envx_re && "$t" != *process.env ]] && return 0
  base="${t##*/}"
  if [[ "$base" == .* && "$base" == *[\*\?\[]* ]]; then
    # shellcheck disable=SC2053  # comparación como patrón, a propósito
    [[ ".env" == $base || ".env.local" == $base || ".env.production" == $base ]] && return 0
  fi
  return 1
}
cred_re='(\.ssh(/|$)|\.aws(/|$)|\.gnupg(/|$)|\.credentials\.json|kimi\.key|\.pem$|id_(rsa|ed25519|ecdsa|dsa)|\.config/gh/hosts\.yml|(^|/)\.claude\.json$|(^|/)\.netrc$|(^|/)\.pgpass$|\.docker/config\.json|^(~|\$HOME|\$\{HOME\})/\.npmrc$)'
cred_ok_re='(\.pub|known_hosts|/config|allowed_signers|authorized_keys)$'
secretvar_re='\$\{?[A-Za-z_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|PRIVATE_KEY)[A-Za-z_]*\}?'
mra_re='minimum[-_]?release[-_]?age'
assign_re='^[A-Za-z_][A-Za-z0-9_]*='

vcwd="$cwd"          # carpeta "virtual": sigue los `cd` del propio comando
DL_FILES=()          # archivos bajados con curl -o / wget -O en este mismo comando
git_dir=""

current_branch() { git -C "${git_dir:-${vcwd:-.}}" symbolic-ref --short HEAD 2>/dev/null || true; }

# ── 3. Reglas por comando ───────────────────────────────────────────────────
analyze() {
  local idx=$1 W=() k=0 nW t sudo=0 prog a i n prevtok re
  IFS="$US" read -r -d '' -a W <<<"${SEG_WORDS[idx]}"
  nW=${#W[@]}
  if ((nW>0)) && [[ "${W[nW-1]}" == $'\n' ]]; then unset "W[$((nW-1))]"; nW=$((nW-1)); fi
  SEG_PROG[idx]=""; SEG_SUDO[idx]=0
  ((nW>0)) || return 0
  # Un comando dentro de `sudo bash -c '…'` también corre con sudo.
  i=${SEG_PARENT[idx]}
  if [[ -n "$i" ]] && ((i>=0)) && [[ "${SEG_SUDO[i]:-0}" == 1 ]]; then sudo=1; fi

  shopt -s nocasematch
  # Asignaciones y envoltorios delante del programa (sudo, env, xargs, timeout…)
  while ((k<nW)); do
    t="${W[k]}"
    if [[ "$t" =~ $assign_re ]]; then
      re="^npm_config_$mra_re"
      [[ "$t" =~ $re ]] && deny "desactivar la cuarentena de pnpm (minimumReleaseAge)"
      k=$((k+1)); continue
    fi
    case "${t##*/}" in
      sudo|doas)
        sudo=1; k=$((k+1))
        while ((k<nW)) && [[ "${W[k]}" == -* ]]; do
          case "${W[k]}" in -u|-g|-h|-p|-C|-D|-R|-T|-U) k=$((k+1)) ;; esac; k=$((k+1))
        done; continue ;;
      env)
        k=$((k+1))
        while ((k<nW)) && [[ "${W[k]}" == -* || "${W[k]}" =~ $assign_re ]]; do
          if [[ "${W[k]}" == -u || "${W[k]}" == -C ]]; then k=$((k+1)); fi
          k=$((k+1))
        done
        if ((k>=nW)) || [[ "${W[k]}" == '>' || "${W[k]}" == '<' ]]; then deny "volcado completo de variables de entorno"; fi
        continue ;;
      command|exec|nohup|time|nice|ionice|stdbuf|builtin)
        k=$((k+1)); while ((k<nW)) && [[ "${W[k]}" == -* ]]; do k=$((k+1)); done; continue ;;
      timeout)
        k=$((k+1)); while ((k<nW)) && [[ "${W[k]}" == -* ]]; do k=$((k+1)); done; k=$((k+1)); continue ;;
      xargs)
        k=$((k+1))
        while ((k<nW)) && [[ "${W[k]}" == -* ]]; do
          case "${W[k]}" in -I|-n|-P|-L|-d|-E|-s) k=$((k+1)) ;; esac; k=$((k+1))
        done; continue ;;
    esac
    break
  done
  ((k<nW)) || return 0
  prog="${W[k]##*/}"; SEG_PROG[idx]="$prog"; SEG_SUDO[idx]=$sudo
  local A=("${W[@]:k+1}"); n=${#A[@]}
  local all=" ${A[*]} "

  # bash -c '…' / eval '…' / here-doc hacia un shell: su texto también es un comando.
  if is_shell "$prog"; then
    for ((i=0;i<n;i++)); do
      if [[ "${A[i]}" =~ ^-[a-z]*c$ ]] && ((i+1<n)); then parse "${A[i+1]}" "$idx"; break; fi
    done
    for ((i=0;i<${#HD_SEG[@]};i++)); do
      [[ "${HD_SEG[i]}" == "$idx" ]] && parse "${HD_BODY[i]}" "$idx"
    done
  elif [[ "$prog" == eval ]]; then parse "${A[*]}" "$idx"
  fi

  # ── Descarga y ejecución ──
  if is_interp "$prog" && [[ "${SEG_CONN[idx]}" == '|' ]]; then
    i=${SEG_PREV[idx]}
    while [[ -n "$i" ]] && ((i>=0)); do
      case "${SEG_PROG[i]}" in curl|wget) deny "curl/wget pipeado a un intérprete" ;; esac
      [[ "${SEG_CONN[i]}" == '|' ]] || break
      i=${SEG_PREV[i]}
    done
  fi
  if [[ "$prog" == curl || "$prog" == wget ]]; then
    i=${SEG_PARENT[idx]}
    if [[ -n "$i" ]] && ((i>=0)) && is_interp "${SEG_PROG[i]}"; then deny "ejecutar lo que baja curl/wget"; fi
    for ((i=0;i<n;i++)); do
      case "${A[i]}" in -o|-O|--output|--output-document) ((i+1<n)) && DL_FILES[${#DL_FILES[@]}]="${A[i+1]}" ;; esac
    done
  fi
  if ((${#DL_FILES[@]})); then
    for t in "${DL_FILES[@]}"; do
      [[ "${W[k]}" == "$t" || "${W[k]}" == "./$t" ]] && deny "ejecutar un script recién bajado con curl/wget"
      if is_shell "$prog" || [[ "$prog" == source || "$prog" == . ]]; then
        for a in "${A[@]}"; do [[ "$a" == "$t" ]] && deny "ejecutar un script recién bajado con curl/wget"; done
      fi
    done
  fi

  # ── Secretos: .env, llaves, variables ──
  local env_hit=0 env_bad=0 pos=0 first_pos=-1 last_arg=""
  prevtok=""
  for ((i=0;i<n;i++)); do
    a="${A[i]}"
    if [[ "$a" == '<' || "$a" == '>' ]]; then prevtok="$a"; continue; fi
    if [[ "$prevtok" == '>' ]]; then
      re='^/dev/(sd[a-z]|nvme|vd[a-z]|hd[a-z]|mmcblk)'
      [[ "$a" =~ $re ]] && deny "escritura directa a disco"
      prevtok=""; continue
    fi
    if [[ "$prevtok" == '<' ]]; then
      mentions_env "$a" && deny "lectura de un archivo .env (usa .env.example para ver los nombres de variables)"
      [[ "$a" =~ $cred_re && ! "$a" =~ $cred_ok_re ]] && deny "lectura o envío de llaves/credenciales"
      prevtok=""; continue
    fi
    # El texto de un mensaje (commit, PR, issue) no es una ruta.
    if ((i>0)) && [[ "$prog" == git || "$prog" == gh ]]; then
      case "${A[i-1]}" in -m|--message|-t|--title|-b|--body) continue ;; esac
    fi
    [[ "$a" == /proc/*/environ ]] && deny "volcado completo de variables de entorno"
    if [[ "$a" != -* ]]; then pos=$((pos+1)); ((first_pos<0)) && first_pos=$i; last_arg="$a"; fi
    if mentions_env "$a"; then
      env_hit=1
      case "$prog" in
        ls|touch|chmod|chown|stat|test|'['|'[['|rm|mkdir|echo|printf|wc|true) ;;
        grep|egrep|fgrep|rg) [[ $i -eq $first_pos ]] || env_bad=1 ;;
        sed) re=' -[a-z]*i'; [[ "$all" =~ $re ]] || env_bad=1 ;;
        cp|mv|install|ln) [[ $i -eq $((n-1)) && "$all" != *" -t "* ]] || env_bad=1 ;;
        git) case "$all" in *" check-ignore "*|*" rm "*|*" status "*|*" ls-files "*) ;; *) env_bad=1 ;; esac ;;
        docker|docker-compose)
          if [[ "$a" == --env-file=* ]] || { ((i>0)) && [[ "${A[i-1]}" == --env-file ]]; }; then :; else env_bad=1; fi ;;
        *) env_bad=1 ;;
      esac
    fi
    if [[ "$a" =~ $cred_re && ! "$a" =~ $cred_ok_re ]]; then
      case "$prog" in
        ls|chmod|chown|mkdir|test|'['|'[['|stat|touch|ssh|ssh-add|ssh-keyscan|rm) ;;
        ssh-keygen) [[ "$all" == *" -y "* ]] && deny "lectura o envío de llaves/credenciales" ;;
        git) [[ "$all" == *" config "* ]] || deny "lectura o envío de llaves/credenciales" ;;
        *) deny "lectura o envío de llaves/credenciales" ;;
      esac
    fi
  done
  ((env_hit && env_bad)) && deny "lectura o envío de un archivo .env (usa .env.example para ver los nombres de variables)"

  case "$prog" in
    printenv) ((pos==0)) && deny "volcado completo de variables de entorno" ;;
    export)   [[ $n -eq 0 || "$all" == *" -p "* ]] && deny "volcado completo de variables de entorno" ;;
    declare|typeset) re=' -[a-z]*[xp][a-z]* '; [[ "$all" =~ $re ]] && ((pos==0)) && deny "volcado completo de variables de entorno" ;;
    set)      ((n==0)) && deny "volcado completo de variables de entorno" ;;
    echo|printf) [[ "$all" =~ $secretvar_re ]] && deny "imprimir una variable con un secreto" ;;
  esac
  re=' (-e|-p|--eval|--print|-c) '
  if [[ "$all" =~ $re ]]; then
    re='(process\.env|os\.environ)([^.A-Za-z0-9_[]|$)'
    [[ "$all" =~ $re ]] && deny "volcado completo de variables de entorno"
  fi

  # ── Reglas por programa ──
  case "$prog" in
    cd)
      if ((n==0)); then vcwd="~"; else case "${A[0]}" in /*|'~'*|'$HOME'*|'${HOME'*) vcwd="${A[0]}" ;; *) vcwd="${vcwd%/}/${A[0]}" ;; esac; fi ;;

    rm)
      ((sudo)) && deny "sudo rm"
      [[ "$all" == *" --no-preserve-root "* ]] && deny "rm --no-preserve-root"
      [[ "$all" == *.credentials.json* ]] && deny "rm de credenciales"
      local rec=0
      re='^-[a-z]*r'
      for a in "${A[@]}"; do [[ "$a" == --recursive || "$a" =~ $re ]] && rec=1; done
      for a in "${A[@]}"; do
        [[ "$a" == -* ]] && continue
        t=$(norm_path "$a")
        [[ "$t" == "~/.claude" ]] && deny "rm de ~/.claude completo"
        ((rec)) || continue
        danger_path "$t" && deny "rm recursivo sobre / , \$HOME o una carpeta del sistema ($a)"
        [[ "$a" =~ $win_root_re ]] && deny "rm recursivo sobre la raíz de una unidad"
        [[ "$a" =~ $win_user_re ]] && deny "rm recursivo sobre tu carpeta de usuario"
        case "$a" in '*'|'.'|'./'|'./*'|'.*') danger_path "$(norm_path "$vcwd")" && deny "rm recursivo de todo estando en $vcwd" ;; esac
      done ;;

    find)
      re=' -exec(dir)? +(sudo +)?(rm|shred) '
      if [[ "$all" == *" -delete "* || "$all" =~ $re ]]; then
        for a in "${A[@]}"; do
          [[ "$a" == -* ]] && break
          danger_path "$(norm_path "$a")" && deny "find que borra dentro de $a"
        done
      fi ;;

    mv)
      for ((i=0;i<n-1;i++)); do
        [[ "${A[i]}" == -* ]] && continue
        t=$(norm_path "${A[i]}")
        [[ "$t" == "~" || "$t" == "~/.claude" || "$t" == "~/.ssh" || "$t" == "/" ]] && deny "mover $t"
      done ;;

    rsync)
      if [[ "$all" == *" --delete"* ]] && danger_path "$(norm_path "$last_arg")"; then deny "rsync --delete sobre $last_arg"; fi ;;

    dd)    [[ "$all" == *" of=/dev/"* ]] && deny "dd hacia un dispositivo" ;;
    mkfs|mkfs.*|mke2fs|wipefs|mkswap|fdisk|parted|sgdisk) deny "formatear o reparticionar un disco" ;;
    shutdown|reboot|poweroff|halt) deny "apagado/reinicio del sistema" ;;
    systemctl) re=' (poweroff|reboot|halt|suspend|hibernate|kexec) '; [[ "$all" =~ $re ]] && deny "apagado/reinicio del sistema" ;;
    kill)    re=' -(9|KILL|SIGKILL) '; [[ "$all" == *" -1 "* && "$all" =~ $re ]] && deny "kill -9 -1 (mata todos tus procesos)" ;;
    crontab) [[ "$all" == *" -r "* ]] && deny "crontab -r (borra todas las tareas programadas)" ;;

    chmod|chown)
      re=' (0?777|a[+=]rwx|ugo[+=]rwx) '
      if [[ "$prog" == chown || "$all" =~ $re ]]; then
        local seen=0
        for a in "${A[@]}"; do
          [[ "$a" == -* ]] && continue
          seen=$((seen+1)); ((seen==1)) && continue          # el modo o el dueño
          t=$(norm_path "$a")
          if danger_path "$t" && [[ "$t" != "~/"* ]]; then deny "$prog en bloque sobre $a"; fi
        done
      fi ;;

    git) rule_git "${A[@]}" ;;

    gh)
      re=' auth +token ';   [[ "$all" =~ $re ]] && deny "gh auth token (imprime tu token)"
      re=' (-t|--show-token) '; [[ "$all" == *" auth "* && "$all" =~ $re ]] && deny "gh auth status --show-token"
      re=' repo +delete ';  [[ "$all" =~ $re ]] && deny "gh repo delete"
      re=' (-X|--method)[= ]?DELETE '; [[ "$all" == *" api "* && "$all" =~ $re ]] && deny "gh api DELETE"
      re=' pr +merge ';     [[ "$all" =~ $re && "$all" == *" --admin "* ]] && deny "gh pr merge --admin (salta la protección de rama)"
      ;;

    docker|docker-compose|podman)
      re=' (run|create) '
      if [[ "$all" =~ $re ]]; then
        re=' (--privileged|--pid[= ]host|--cap-add[= ][^ ]+|--device[= ][^ ]+) '
        [[ "$all" =~ $re ]] && deny "docker run con privilegios"
        for ((i=0;i<n;i++)); do
          a="${A[i]}"; t=""
          case "$a" in
            -v|--volume) ((i+1<n)) && t="${A[i+1]%%:*}" ;;
            -v?*)        t="${a#-v}"; t="${t%%:*}" ;;
            --volume=*)  t="${a#--volume=}"; t="${t%%:*}" ;;
            --mount|--mount=*)
              [[ "$a" == --mount ]] && a="${A[i+1]:-}"
              re='(source|src)=([^,]+)'
              if [[ "$a" =~ $re ]]; then t="${BASH_REMATCH[2]}"; fi ;;
          esac
          [[ -z "$t" ]] && continue
          [[ "$t" == */docker.sock ]] && deny "docker run montando el socket de Docker"
          danger_path "$(norm_path "$t")" && deny "docker run montando $t del host"
        done
      fi
      re=' (-v|--volumes) ';  [[ "$all" == *" down "* && "$all" =~ $re ]] && deny "docker compose down -v (borra los volúmenes con tus datos)"
      re=' volume +(prune|rm) '; [[ "$all" =~ $re ]] && deny "borrar volúmenes de Docker"
      re=' system +prune ';   [[ "$all" =~ $re && "$all" == *" --volumes "* ]] && deny "borrar volúmenes de Docker"
      if [[ "$all" == *" config "* ]] && [[ "$prog" == docker-compose || "$all" == *" compose "* ]]; then
        deny "docker compose config (imprime el entorno resuelto, con secretos)"
      fi
      re=' (exec|run) '
      if [[ "$all" =~ $re ]]; then
        [[ "$all" == *" printenv "* || "$last_arg" == env ]] && deny "volcado completo de variables de entorno"
      fi
      re='DROP +(DATABASE|SCHEMA)'; [[ "$all" =~ $re ]] && deny "DROP DATABASE/SCHEMA"
      ;;

    psql|pgcli) re='DROP +(DATABASE|SCHEMA)'; [[ "$all" =~ $re ]] && deny "DROP DATABASE/SCHEMA" ;;
    redis-cli)  re=' (FLUSHALL|FLUSHDB) ';    [[ "$all" =~ $re ]] && deny "redis FLUSHALL/FLUSHDB" ;;
  esac

  # Prisma y pnpm pueden venir detrás de `pnpm exec`, `npx`, `pnpm --filter x`…
  if [[ "$prog" == prisma || "$all" == *" prisma "* ]]; then
    re=' migrate +reset '; [[ "$all" =~ $re ]] && deny "prisma migrate reset (borra la base de datos)"
    [[ "$all" == *" --force-reset "* ]] && deny "prisma db push --force-reset (borra la base de datos)"
  fi
  case "$prog" in pnpm|npm|npx|yarn|corepack)
    re=" config +(set|delete) +$mra_re"; [[ "$all" =~ $re ]] && deny "desactivar la cuarentena de pnpm (minimumReleaseAge)"
    re="--(config\\.)?$mra_re";          [[ "$all" =~ $re ]] && deny "desactivar la cuarentena de pnpm (minimumReleaseAge)"
  ;; esac
  shopt -u nocasematch
  return 0
}

rule_git() {
  local G=("$@") g=0 gn=$# sub a t dst src dyn=0 nref=0 force=0 allb=0 i posn=0 re rest
  git_dir=""
  shopt -u nocasematch      # aquí -c y -C son opciones distintas
  # Opciones globales antes del subcomando
  while ((g<gn)); do
    a="${G[g]}"
    case "$a" in
      -C) git_dir="${G[g+1]:-}"; g=$((g+2)) ;;
      -c) t=$(tr 'A-Z' 'a-z' <<<"${G[g+1]:-}")
          re='^(alias\.|core\.(sshcommand|hookspath|fsmonitor|pager)|credential\.helper|[^=]+=!)'
          [[ "$t" =~ $re ]] && deny "git -c que ejecuta un programa ($t)"
          g=$((g+2)) ;;
      --git-dir|--work-tree|--namespace|--exec-path|--config-env) g=$((g+2)) ;;
      -*) g=$((g+1)) ;;
      *) break ;;
    esac
  done
  if ((g>=gn)); then shopt -s nocasematch; return 0; fi
  sub="${G[g]}"; g=$((g+1))
  if [[ -n "$git_dir" ]]; then
    if command -v cygpath >/dev/null 2>&1; then git_dir=$(cygpath -u "$git_dir"); fi
    [[ "$git_dir" != /* ]] && git_dir="${vcwd:-.}/$git_dir"
  fi
  rest=$(tr 'A-Z' 'a-z' <<<" ${G[*]:g} ")

  case "$sub" in
    push)
      for ((i=g;i<gn;i++)); do
        a="${G[i]}"
        case "$a" in
          --force|--force-with-lease*|--force-if-includes) force=1 ;;
          --mirror) deny "git push --mirror" ;;
          --all|--branches) allb=1 ;;
          --*) ;;
          -*) re='^-[a-z]*f'; [[ "$a" =~ $re ]] && force=1 ;;
          *)
            posn=$((posn+1)); ((posn==1)) && continue        # el remoto
            nref=$((nref+1))
            [[ "$a" == +* ]] && force=1
            a="${a#+}"; dst="${a##*:}"; src="${a%%:*}"; dst="${dst#refs/heads/}"
            [[ "$dst" == main || "$dst" == master ]] && deny "push directo a main/master (usa PR)"
            if [[ "$a" != *:* ]] && [[ "$src" == HEAD || "$src" == @ || "$src" == *'$'* ]]; then dyn=1; fi
            ;;
        esac
      done
      ((force)) && deny "git push forzado"
      if ((nref==0 || dyn || allb)); then
        t=$(current_branch)
        [[ "$t" == main || "$t" == master ]] && deny "git push estando en $t (crea una rama y abre PR)"
      fi ;;
    reset)
      re=' (origin/|@\{u|@\{upstream)'
      [[ "$rest" == *" --hard "* && "$rest" =~ $re ]] && deny "git reset --hard contra el remoto" ;;
    config)
      re=' core\.(hookspath|sshcommand|fsmonitor) '; [[ "$rest" =~ $re ]] && deny "git config que ejecuta programas (hooks/ssh)"
      re=' alias\.[^ ]+ +!';                          [[ "$rest" =~ $re ]] && deny "git config de un alias que ejecuta un programa" ;;
  esac
  shopt -s nocasematch
  return 0
}

# ── 4. Ejecutar ─────────────────────────────────────────────────────────────
# Fork bomb: es sintaxis, no un programa; se mira el texto.
grep -Eq ':\(\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:' <<<"$cmd" && deny "fork bomb"

parse "$cmd" -1
idx=0
while ((idx<nseg)); do   # nseg crece si un comando trae `bash -c '…'` o `eval`
  analyze "$idx"
  idx=$((idx+1))
done
exit 0
