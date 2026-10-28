# Changelog

All notable changes to ai-lordkit. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added

- Skill `testing-actions`: layered testing strategy and GitHub Actions pipelines in stages (`needs:`) with one icon per category (🧹 Lint, 🔎 Type Check, 🧪 Unit, 🔗 Integration, 🏗️ Build, 🎭 E2E, 💨 Smoke, ♿ Accessibility, 🏁 Pipeline Summary). The summary job reads the real results of every stage into `$GITHUB_STEP_SUMMARY` and fails if any stage failed. Rules against hiding failures, minimal permissions, and notes for self-hosted runners (cleanup between runs, ports, no sudo, security). Includes the full audit prompt and a workflow template in `references/`.
- Native Windows support through Git Bash (`get.sh` and `install.sh` accept `MINGW*`/`MSYS*`). `./install.sh deps` installs `jq`, `gh`, Node 24 LTS, `uv` with `winget` and pnpm through `corepack` into `~/.local/bin` (no admin needed). WSL keeps working.
- `.gitattributes`: bash scripts, hooks and JSON always use LF, even with `core.autocrlf=true` (CRLF broke them when cloned on Windows).
- `guard.sh` blocks recursive `rm` on a drive root (`C:\`, `C:/`, `/c/`) and on the user folder (`/c/Users/<name>`, `$USERPROFILE`), with tests.
- `windows` job in `.github/workflows/check.yml` (Git Bash on `windows-latest`).
- README (en/es): animated platform strip (`assets/platforms-light.svg`, `assets/platforms-dark.svg`) and badges for Windows, macOS, Linux and WSL, plus a Windows note next to the install command. Official logos (Apple, Tux, Ubuntu from [Simple Icons](https://simpleicons.org), CC0; Windows 11 four-pane mark); the names and logos belong to their owners. The animation respects `prefers-reduced-motion`.

### Changed

- Hooks convert `C:\...` paths from Claude Code (`cygpath`) in `guard.sh` and `format.sh`; `notify.sh` shows a balloon from Git Bash too.
- `jq.exe` ends lines with CRLF: a wrapper strips the `\r` in the hooks, `install.sh` and `mem-search.sh`.
- `write_settings` uses a temp file instead of `<(...)`, which `jq.exe` cannot open.
- Tests run with a `PATH` that also holds `jq` and `git` (they do not live in `/usr/bin` on Windows).

## [0.2.0] - 2026-10-27

### Added

- README rewritten: why the kit exists and its goals, what makes it different, Mermaid diagrams (install, session, agent team, block cycle, public/private layers), repository tree, full command reference (`get.sh`, every `install.sh` command, the `claude` wrapper, slash commands), every skill, agent and hook, author section and donations. Full Spanish version in `README.es.md`. Hand-made SVG banner, feature cards and donation buttons in `assets/`, with light and dark versions.
- Skill `brechas`: checks `pnpm-lock.yaml` or `package-lock.json`, the MCP servers in the kit, the private layer and `.mcp.json`, and the Claude Code version against OSV.dev (GitHub Advisory Database and OpenSSF malicious packages), CISA KEV and EPSS. Report with links and fixed versions in `docs/seguridad/`, accepted risks in `.brechas-ignorar`, optional recent news with sources. Node 24, no dependencies, no API keys. `blindar todo` delegates the dependency phase to it.
- Optional hook `supply-guard.sh` (off by default, `AI_LORDKIT_SUPPLY_GUARD=1`): blocks installing or running a package version flagged as malicious and asks before one published less than 7 days ago.
- Skill `crear-app`: when someone says they want to build an app and doesn't know what to use, an interactive picker (`AskUserQuestion`) asks the type of app, architecture, tools and platforms, recommended option first. The choice goes to `docs/METODO.md` (new `Herramientas:` line) and the project starts with Block 0. `elegir-metodo` asks its question with the same picker.

- Skill `blindar`: security audit of your own code, mandatory at the close of every block (gate C5 of `desarrollo-por-etapas`) and as a full 12-phase audit with `/blindar todo` (hardening stage D). Six checks: input validation, rate limiting per user and IP, error leaks, tokens and sessions, CORS, routes without auth or validation. Findings with `file:line`, fixes with tests, report in `docs/seguridad/`, depth by mode.
- Work modes `completo`, `intermedio` (default) and `ahorro` as output styles in `output-styles/`. `claude --modo <mode>` sets the style and the effort (`xhigh`, `medium`, `low`), and Sonnet in `ahorro`. Your own `--model` or `--effort` wins.
- The status line shows the mode, the effort and the estimated session cost.
- `desarrollo-por-etapas`: C1 now starts with concrete user scenarios, from which come the tasks and the Given/When/Then criteria that become tests. `elegir-metodo` finds blocks from one-line scenarios.
- `tests/modos/test.sh`: the launcher in bash and zsh, and the status line.
- `microservicios` skill: microservices as an alternative architecture, with when not to use it, the pieces (gateway, contracts, events with outbox, compose) and a Block 0 for services. `elegir-metodo` now also records the architecture in `docs/METODO.md`.

### Changed

- `elegir-metodo` recommends with pros and cons, shows the alternatives, waits for your choice and records method changes in `docs/METODO.md`.
- `backend-quality-gate` is now the "backend first, module by module" method: `elegir-metodo` offers it as an alternative to blocks, and it only runs when you pick it.
- `WORKFLOW.md` links the block method skills; `/new-project` ends in `elegir-metodo` and Block 0; `CLAUDE.md` says when to use each agent.
- CI: actions on Node 24 pinned by SHA, fixed runner versions (`ubuntu-26.04`, `macos-26`), monthly Dependabot with a 7-day cooldown, ShellCheck over every test.
- `fullstack` CI templates: actions on Node 24 pinned by SHA, Node 24, pnpm from `packageManager`, `setup-buildx-action` for the build cache, and a Dependabot section.

### Fixed

- Broken references: `backend-architect` pointed to an old path, and `erp-saas-core`, `memory-bank-context` and `blindar` cited skills the kit doesn't ship.
- `CHECKLIST.md` installs pnpm with Corepack instead of npm.

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

- One-command installer `get.sh` for Linux and macOS (and Windows: native Git Bash or WSL).
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

[Unreleased]: https://github.com/FrankLord27/ai-lordkit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/FrankLord27/ai-lordkit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/FrankLord27/ai-lordkit/releases/tag/v0.1.0
