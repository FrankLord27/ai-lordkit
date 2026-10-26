# ai-lordkit

⚡ One-command Claude Code setup kit: agents, skills, hooks & MCP servers, ready to use.

> **Not an official Anthropic project.** This is a community setup for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It is not affiliated with or endorsed by Anthropic.

What you get:

- **Global instructions** (`CLAUDE.md`) and a risk-based workflow (`WORKFLOW.md`).
- **13 subagents**: planner, backend architect, frontend specialist, QA, code reviewer, security auditor, debugger, DevOps and more. Models by alias, never pinned IDs.
- **Skills** for a NestJS + Next.js + Prisma + PostgreSQL + Redis stack, plus security hardening, HTTP QUERY, Memory Bank and ERP/POS rules.
- **A block-based method for building with AI**: the AI proposes how to work on each project, then builds one usable, tested block at a time instead of layer by layer.
- **`/mapa-bloque`**: an interactive map of any block of your TypeScript code, with unused variables, dead exports and import cycles marked in red.
- **Safety hooks**: `guard.sh` blocks destructive commands, reading env files and keys, `curl | sh`, force pushes and pushes to `main`.
- **MCP servers** defined in the repo, with tokens read from environment variables.
- **A private layer** for everything personal, applied on top, so this repo stays generic.
- **A one-command installer** for Linux (apt) and macOS (Homebrew) that takes a freshly formatted machine to a working setup.

> Instructions and skills are written in **Spanish**. Issues and PRs in English or Spanish are welcome.

## Install

One command, no clone needed (Linux and macOS):

```bash
curl -fsSL https://raw.githubusercontent.com/FrankLord27/ai-lordkit/main/get.sh | bash
```

`get.sh` downloads the kit to `~/.ai-lordkit` and runs its installer:

- **No `~/.claude` yet** → full setup: dependencies (apt on Linux, Homebrew on macOS), Claude Code, the config, pnpm hardening and the MCP servers.
- **`~/.claude` already exists** → `update`: only applies the config, backing up your current files first.

When it finishes, open a new terminal, run `claude` and log in. Running the same command again updates the kit (the previous copy is kept in `~/.ai-lordkit.prev`).

Options:

```bash
# A different installer command (doctor, verify, mcp…)
curl -fsSL https://raw.githubusercontent.com/FrankLord27/ai-lordkit/main/get.sh | bash -s -- doctor

# A fixed version: a tag, or better, a commit SHA (it can't change under you)
curl -fsSL https://raw.githubusercontent.com/FrankLord27/ai-lordkit/<sha>/get.sh | AI_LORDKIT_REF=<sha> bash
```

| Variable          | Default                  | What it does                                              |
| ----------------- | ------------------------ | --------------------------------------------------------- |
| `AI_LORDKIT_REF`  | `main`                   | Branch, tag or commit SHA to install                      |
| `AI_LORDKIT_DIR`  | `~/.ai-lordkit`          | Where the kit lives. If it is a git clone, it isn't touched |
| `CLAUDE_YES`      | unset                    | `1` confirms the cleanup step on machines without a terminal |

### Review before you run it

Piping a script into `bash` means trusting it. To read it first:

```bash
curl -fsSL https://raw.githubusercontent.com/FrankLord27/ai-lordkit/main/get.sh -o get.sh
less get.sh        # ~85 lines: downloads a tarball and runs install.sh
bash get.sh
```

`get.sh` only downloads the kit and runs `install.sh`, so review that one too ([install.sh](install.sh)). The whole script is wrapped in a function, so a cut download never runs half of it.

### Install from a clone

If you want to contribute or use `backup` / `sync` (they need a git repo):

```bash
git clone https://github.com/FrankLord27/ai-lordkit ~/ai-lordkit && ~/ai-lordkit/install.sh
```

The full setup **moves** your current `~/.claude` to `~/.claude-backups/` first (nothing is deleted). Already have Claude Code and only want the config? Run `./install.sh update` (it backs up first).

| Command                     | What it does                                                          |
| --------------------------- | --------------------------------------------------------------------- |
| `./install.sh update`       | Applies the kit (and your private layer) to `~/.claude`, with backup  |
| `./install.sh verify`       | Checks structure, runs the hook tests and the leak scanner, and checks the plugins loaded |
| `./install.sh doctor`       | Checks git, gh, Node 24, pnpm, jq, docker                             |
| `./install.sh mcp`          | Registers the MCP servers from `mcp/servers.json` and your private layer |
| `./install.sh plugins`      | Adds the plugin marketplaces and installs the plugins `settings.json` enables |
| `./install.sh private-init` | Creates your private layer in `~/ai-lordkit-private`                  |
| `./install.sh sync`         | Sends your live changes back: public via a PR branch, private directly |
| `./install.sh scan`         | Looks for tokens, real emails, personal paths and your private terms  |

## What's inside

| Path                | Contents                                                              |
| ------------------- | --------------------------------------------------------------------- |
| `CLAUDE.md`         | Global instructions (short on purpose: it loads in every session)     |
| `WORKFLOW.md`       | Detailed flow for medium/high-risk tasks                              |
| `settings.json`     | Permissions, hooks, model, plugin marketplaces and enabled plugins    |
| `.claude-plugin/`   | A catalog that points to third-party skills upstream (nothing copied) |
| `agents/`           | 13 subagents                                                          |
| `skills/`           | Stack and domain skills (`fullstack`, `nestjs-security-hardening`, `erp-saas-core`…) |
| `hooks/`            | `guard.sh` (blocking), `format.sh` (project-local Prettier), `test-guard.sh` |
| `mcp/servers.json`  | Public MCP servers, tokens as `${VARIABLES}`                          |
| `private-template/` | Template for your private layer                                       |
| `scripts/`          | `scan-leaks.sh`, used by `verify`, `sync` and CI                      |
| `tests/`            | Sample project and test for `mapa-bloque`, run in CI                  |
| `bin/`              | `claude --kimi`: same config on Kimi models                           |
| `commands/`         | `/new-project`                                                        |

## Public layer and private layer

This repo is **generic**: no clients, project names, emails or tokens. Your own stuff goes in a **private layer** applied on top:

```
~/ai-lordkit           ← this repo (public)
~/ai-lordkit-private   ← your PRIVATE repo: own CLAUDE.md, own skills, settings, MCPs, private-terms.txt
```

1. `./install.sh private-init` creates it from `private-template/` and runs `git init`.
2. Push it to a **private** repo of yours. On another machine, clone it into `~/ai-lordkit-private` before installing (or point `CLAUDE_PRIVATE_DIR` at it).
3. `./install.sh update` applies the public layer, then the private one: your `CLAUDE.md` is appended, `settings.json` is merged (permission arrays are added together), and your skills, agents and commands are copied.

`./install.sh sync` goes the other way without mixing them:

- Anything that already exists in the public repo goes back to it. **Anything new goes to the private layer.** To publish a new skill, move it yourself.
- `settings.json` is never copied back automatically, because the live one may hold tokens in `env`.
- Before pushing the public side, the scanner runs. A token, a real email, a `/home/<user>` path or a word from your `private-terms.txt` aborts the sync.
- The public side is pushed to a `sync/<date>` branch so it goes through a PR, never straight to `main`.
- The private side is scanned too: names are fine there, tokens are not.

## MCP servers and connectors

`mcp/servers.json` lists the MCP servers installed for everyone. Tokens never live in the file: they are written as `${VARIABLE}` and read from your environment when you run `./install.sh mcp`. If a variable is missing, that server is skipped.

| Server     | Needs                                                                          |
| ---------- | ------------------------------------------------------------------------------ |
| `context7` | Nothing. Up-to-date official library docs                                      |
| `github`   | `GITHUB_MCP_TOKEN`: your own fine-grained GitHub token, with the scopes you choose |

Private MCP servers (your hosting provider, for example) go in your private layer's `mcp.json`, same format. The token value only ends up in that machine's `~/.claude.json`, which `sync` never touches.

**claude.ai connectors** (Gmail, Drive, Notion, Slack…) can't be exported: they belong to each account. Connect your own in claude.ai under Settings → Connectors.

## Plugins

The kit doesn't copy other people's skills. `settings.json` declares the marketplaces under `extraKnownMarketplaces` and turns plugins on under `enabledPlugins`, so every machine downloads them from their source and they keep updating (`autoUpdate: true`).

| Plugin | Marketplace | What it adds |
| ------ | ----------- | ------------ |
| `prisma` | `claude-plugins-official` | Prisma MCP servers (local and Prisma Postgres) |
| `typescript-lsp` | `claude-plugins-official` | TypeScript language server: go to definition, diagnostics. Needs `typescript-language-server` in your `PATH` |
| `security-guidance` | `claude-plugins-official` | Hooks that warn about insecure patterns while Claude edits |
| `pr-review-toolkit` | `claude-plugins-official` | Specialized PR review agents and `/review-pr` |
| `commit-commands` | `claude-plugins-official` | `/commit`, `/commit-push-pr`, `/clean_gone` |
| `hookify` | `claude-plugins-official` | Turn "don't do X again" into hooks |
| `claude-md-management` | `claude-plugins-official` | Audit and improve `CLAUDE.md` files |
| `playwright` | `claude-plugins-official` | Playwright MCP: drive a real browser |
| `sentry` | `claude-plugins-official` | Sentry MCP and skills for issues and alerts |
| `vercel` | `claude-plugins-official` | Vercel MCP, skills and hooks |
| `hostinger` | `claude-plugins-official` | Hostinger MCP and hosting skills |
| `superpowers` | `claude-plugins-official` | [obra/superpowers](https://github.com/obra/superpowers): brainstorm, plan, TDD, systematic debugging |
| `skill-creator` | `claude-plugins-official` | Anthropic's skill for writing and testing skills ([anthropics/skills](https://github.com/anthropics/skills)) |
| `react-best-practices` | `ai-lordkit` | [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills): React and Next.js performance rules |
| `composition-patterns` | `ai-lordkit` | vercel-labs/agent-skills: React composition patterns |
| `web-design-guidelines` | `ai-lordkit` | vercel-labs/agent-skills: review UI against the Web Interface Guidelines |
| `claude-mem` | `thedotmack` | Memory across sessions. Installed by `./install.sh claudemem` |

Where each one comes from:

- **`claude-plugins-official`** ([anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official)) is Anthropic's marketplace. It already lists `superpowers`, `context7` and `skill-creator`, so the kit uses those entries instead of adding `obra/superpowers`, `upstash/context7` or `anthropics/skills` as separate marketplaces.
- **`ai-lordkit`** is [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json) in this repo. `vercel-labs/agent-skills` isn't a Claude Code marketplace, so this catalog points to each skill's folder upstream (a `git-subdir` source). Only that file is cloned (`sparsePaths`).
- **Context7** is not enabled as a plugin because `mcp/servers.json` already installs the same server. Two copies would only duplicate tools.

`./install.sh plugins` (also part of `all` and `update`) adds the marketplaces and installs whatever is missing. Claude Code would register the marketplaces by itself at the next interactive session, but not from scripts, so the installer does it. `./install.sh verify` fails if a plugin's marketplace isn't declared or if a plugin repeats another plugin, a bundled skill or an MCP server, and on a machine with Claude Code it warns about plugins that aren't installed, are turned off or failed to load.

More plugins are not better: every enabled plugin adds tools and skill descriptions to each session, and Claude picks worse with too many. To add your own or turn one off, use your private layer's `settings.json`, which is merged on top: `"vercel@claude-plugins-official": false` under `enabledPlugins` turns it off on your machines. `claude plugin disable` alone doesn't last, because `update` writes `settings.json` again.

In cloud sessions (claude.ai/code) plugins from settings files don't load; this list applies to your machines.

## Security model

Claude Code runs in `auto` mode, so there are three layers:

1. **`permissions.allow`:** only specific dev commands (`pnpm`, `git`, `gh`, `docker compose`, `npx prisma`…). Nothing generic that reads arbitrary files (`cat`, `grep`) or runs downloaded packages (`npx *`, `docker *`).
2. **`permissions.ask`:** always asks before `curl`, `docker run`, `pnpm dlx`, `rm -rf`, `git reset --hard`, `prisma migrate reset`.
3. **`hooks/guard.sh`:** the last net, which blocks even if something was approved: deleting `/` or `$HOME`, reading or sending env files and keys, full `printenv`, `curl | sh`, `docker run --privileged`, force pushes and pushes to `main` (including a bare `git push` while on main). It fails closed if `jq` is missing.

If you change `guard.sh`, run `./hooks/test-guard.sh`. `./install.sh verify` runs it too.

Left out on purpose:

- **Official docs:** served by the Context7 MCP, always current.
- **Expo/EAS skills:** they come from the official Expo plugin. Install it from `/plugin` inside Claude Code.
- **Credentials:** `~/.claude/.credentials.json`, `~/.claude/kimi.key` and any env file are kept out by `.gitignore` and by the scanner.

## Building by blocks

AI agents lose the thread when you build a whole layer at a time (all screens, then the whole database, then the whole API). This kit builds **by blocks** instead: a block is one flow a user can finish ("log in", "register a student", "charge an invoice"). Each block goes through UI, data and API, gets an end-to-end test, and is usable before the next one starts.

| Skill | What it does |
| ----- | ------------ |
| `elegir-metodo` | At the start of a project or big feature, asks a few questions and recommends **one** method: a throwaway spike when the idea is uncertain, a full definition plus blocks when requirements are clear, a short spec for large features. Saves the decision in `docs/METODO.md`. |
| `desarrollo-por-etapas` | Definition → Block 0 (the skeleton every block copies) → one block at a time, each with a quality gate that needs evidence → hardening → pilot. Short versions for features and bugs. |
| `mapa-bloque` | Only when you call it: `/mapa-bloque login`. Runs the TypeScript compiler over the block's folder and writes an interactive HTML map, a JSON file and a Markdown summary with a Mermaid diagram to `docs/mapas/`. |

What `/mapa-bloque` shows, all computed by the compiler, not guessed by the AI:

- Which files are in the block, their role (module, controller, service, DTO, component, hook…) and who outside the block uses them.
- Every top-level declaration in each file and whether it is used.
- Variables, imports and parameters that are never read, exports nothing imports, files nobody imports, code only the tests use, and circular imports.

The map works offline. It bundles its own TypeScript 6 (TypeScript 7 no longer ships the JavaScript API it needs); `./install.sh update` installs it.

## Support the project

ai-lordkit is free and MIT-licensed. If it saves you time, you can help keep it going:

- **[GitHub Sponsors](https://github.com/sponsors/FrankLord27)**: the Sponsor button at the top of this repo.
- **[PayPal](https://www.paypal.me/frankfelixr)**: one-time donations in any amount.
- Starring the repo and sharing it also helps.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
