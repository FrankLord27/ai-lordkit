# ai-lordkit

⚡ One-command Claude Code setup kit: agents, skills, hooks & MCP servers, ready to use.

> **Not an official Anthropic project.** This is a community setup for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It is not affiliated with or endorsed by Anthropic.

What you get:

- **Global instructions** (`CLAUDE.md`) and a risk-based workflow (`WORKFLOW.md`).
- **13 subagents**: planner, backend architect, frontend specialist, QA, code reviewer, security auditor, debugger, DevOps and more. Models by alias, never pinned IDs.
- **Skills** for a NestJS + Next.js + Prisma + PostgreSQL + Redis stack, plus security hardening, HTTP QUERY, Memory Bank and ERP/POS rules.
- **Safety hooks**: `guard.sh` blocks destructive commands, reading env files and keys, `curl | sh`, force pushes and pushes to `main`.
- **MCP servers** defined in the repo, with tokens read from environment variables.
- **A private layer** for everything personal, applied on top, so this repo stays generic.
- **An installer** (Linux / apt) that takes a freshly formatted machine to a working setup.

> Instructions and skills are written in **Spanish**. Issues and PRs in English or Spanish are welcome.

## Install

```bash
git clone https://github.com/FrankLord27/ai-lordkit ~/ai-lordkit && ~/ai-lordkit/install.sh
```

This installs the dependencies, Claude Code, the config, pnpm hardening and the MCP servers. Your current `~/.claude` is **moved** to `~/.claude-backups/` first (nothing is deleted). When it finishes, run `claude` and log in.

Already have Claude Code and only want the config? Run `./install.sh update` (it backs up first).

| Command                     | What it does                                                          |
| --------------------------- | --------------------------------------------------------------------- |
| `./install.sh update`       | Applies the kit (and your private layer) to `~/.claude`, with backup  |
| `./install.sh verify`       | Checks structure, runs the hook tests and the leak scanner            |
| `./install.sh doctor`       | Checks git, gh, Node 24, pnpm, jq, docker                             |
| `./install.sh mcp`          | Registers the MCP servers from `mcp/servers.json` and your private layer |
| `./install.sh private-init` | Creates your private layer in `~/ai-lordkit-private`                  |
| `./install.sh sync`         | Sends your live changes back: public via a PR branch, private directly |
| `./install.sh scan`         | Looks for tokens, real emails, personal paths and your private terms  |

## What's inside

| Path                | Contents                                                              |
| ------------------- | --------------------------------------------------------------------- |
| `CLAUDE.md`         | Global instructions (short on purpose: it loads in every session)     |
| `WORKFLOW.md`       | Detailed flow for medium/high-risk tasks                              |
| `settings.json`     | Permissions, hooks, model                                             |
| `agents/`           | 13 subagents                                                          |
| `skills/`           | Stack and domain skills (`fullstack`, `nestjs-security-hardening`, `erp-saas-core`…) |
| `hooks/`            | `guard.sh` (blocking), `format.sh` (project-local Prettier), `test-guard.sh` |
| `mcp/servers.json`  | Public MCP servers, tokens as `${VARIABLES}`                          |
| `private-template/` | Template for your private layer                                       |
| `scripts/`          | `scan-leaks.sh`, used by `verify`, `sync` and CI                      |
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

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MIT](LICENSE).
