#!/usr/bin/env bash
# Línea de estado de Claude Code: modelo · carpeta · rama de git.
# Claude Code le pasa un JSON por stdin; sin jq muestra solo la carpeta.

input=$(cat)
if command -v jq >/dev/null 2>&1; then
  model=$(jq -r '.model.display_name // empty' <<<"$input" 2>/dev/null)
  dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input" 2>/dev/null)
fi
dir="${dir:-$PWD}"
branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)

out="${model:+$model · }$(basename "$dir")"
[[ -n "$branch" ]] && out="$out · $branch"
printf '%s' "$out"
