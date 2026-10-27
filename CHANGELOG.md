# Changelog

All notable changes to ai-lordkit. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added

- README rewritten: why the kit exists and its goals, what makes it different, Mermaid diagrams (install, session, agent team, block cycle, public/private layers), repository tree, full command reference (`get.sh`, every `install.sh` command, the `claude` wrapper, slash commands), every skill, agent and hook, author section and donations. Full Spanish version in `README.es.md`.
- Skill `crear-app`: when someone says they want to build an app and doesn't know what to use, an interactive picker (`AskUserQuestion`) asks the type of app, architecture, tools and platforms, recommended option first. The choice goes to `docs/METODO.md` (new `Herramientas:` line) and the project starts with Block 0. `elegir-metodo` asks its question with the same picker.

- Skill `blindar`: security audit of your own code, mandatory at the close of every block (gate C5 of `desarrollo-por-etapas`) and as a full 12-phase audit with `/blindar todo` (hardening stage D). Six checks: input validation, rate limiting per user and IP, error leaks, tokens and sessions, CORS, routes without auth or validation. Findings with `file:line`, fixes with tests, report in `docs/seguridad/`, depth by mode.
- Work modes `completo`, `intermedio` (default) and `ahorro` as output styles in `output-styles/`. `claude --modo <mode>` sets the style and the effort (`xhigh`, `medium`, `low`), and Sonnet in `ahorro`. Your own `--model` or `--effort` wins.
- The status line shows the mode, the effort and the estimated session cost.
- `desarrollo-por-etapas`: C1 now starts with concrete user scenarios, from which come the tasks and the Given/When/Then criteria that become tests. `elegir-metodo` finds blocks from one-line scenarios.
- `tests/modos/test.sh`: the launcher in bash and zsh, and the status line.
- `microservicios` skill: microservices as an alternative architecture, with when not to use it, the pieces (gateway, contracts, events with outbox, compose) and a Block 0 for services. `elegir-metodo` now also records the architecture in `docs/METODO.md`.

## [0.1.0] - 2026-10-27

First public release.

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

[Unreleased]: https://github.com/FrankLord27/ai-lordkit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/FrankLord27/ai-lordkit/releases/tag/v0.1.0
