# Changelog

All notable changes to ai-lordkit. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/).

## [Unreleased]

First public release, not tagged yet.

### Security

- `guard.sh` strips git's global options (`-C`, `-c`, `--git-dir`) before checking, so `git -C . push origin main` is blocked like `git push origin main`.
- `guard.sh` blocks any mention of an env file, whatever program reads it (`node -e`, `python -c`, `tac`, `find -exec`, `cp` elsewhere). Writing one, `-f .env` and `--env-file` stay allowed.
- `node *`, `cp *` and `mv *` are no longer auto-approved.
- Removed the `git push * main*` deny rules: they also blocked branches like `fix/main-menu`. `guard.sh` covers pushes to `main`.
- Third-party skills in `.claude-plugin/marketplace.json` are pinned to an upstream commit.
- `get.sh` installs the latest release by default instead of `main`.

### Added

- One-command installer `get.sh` for Linux and macOS (and Windows through WSL).
- Plugin marketplaces and enabled plugins in `settings.json`; `./install.sh plugins`.
- Native memory plus the `mem-search` skill, replacing claude-mem.
- Block-based development (vertical slices): skills `elegir-metodo`, `desarrollo-por-etapas` and `mapa-bloque` (interactive HTML map of a block, built from the TypeScript compiler).
- `.github/FUNDING.yml`: Sponsor button (GitHub Sponsors and PayPal).
- `./install.sh rollback`: puts back the config from before the last `update`.
- `./install.sh uninstall`: removes what the kit installed, with a backup.
- `hooks/notify.sh`: desktop alerts on Linux, macOS and WSL.
- `hooks/statusline.sh`: status line with model · folder · git branch.
- `SECURITY.md`, issue and PR templates, this changelog.
- CI: ShellCheck and a test of update, rollback and uninstall.

### Changed

- `update` no longer overwrites `~/.claude/settings.json`: the keys the kit declares are written, everything else you set is kept.
- Off by default: `superpowers`, `hookify`, `pr-review-toolkit`, `commit-commands`, `sentry`, `vercel`, `hostinger`. Turn on the ones you use in your private layer. If you installed the kit before, `update` marks them off.
- `settings.json` no longer pins `model` or `alwaysThinkingEnabled`.
- `CLAUDE.md` trimmed to 100 lines.
- A fresh Mac gets a `~/.zshrc` so `~/.local/bin` is in `PATH` and `claude --kimi` works.
