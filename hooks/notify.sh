#!/usr/bin/env bash
# Hook Notification: avisa en el escritorio cuando Claude Code necesita tu atención.
# Linux (notify-send), macOS (osascript), WSL y Git Bash (globo de Windows vía powershell.exe).
# Nunca falla: si no hay cómo avisar, no hace nada.

title="Claude Code"
msg="Necesita tu atención"

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) is_gitbash=1 ;; *) is_gitbash=0 ;; esac

if { grep -qi microsoft /proc/version 2>/dev/null || [[ "$is_gitbash" == 1 ]]; } && command -v powershell.exe >/dev/null 2>&1; then
  # En segundo plano: el globo tarda unos segundos y el hook no debe esperar.
  nohup powershell.exe -NoProfile -NonInteractive -Command "
    Add-Type -AssemblyName System.Windows.Forms
    \$n = New-Object System.Windows.Forms.NotifyIcon
    \$n.Icon = [System.Drawing.SystemIcons]::Information
    \$n.Visible = \$true
    \$n.ShowBalloonTip(5000, '$title', '$msg', 'Info')
    Start-Sleep -Seconds 6
    \$n.Dispose()" >/dev/null 2>&1 &
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "$title" "$msg" 2>/dev/null
elif command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null
fi
exit 0
