# Contributing

Thanks for wanting to help! This repo is the **public, generic** part of a Claude Code setup. Everything personal lives in each user's private layer (see the README).

Issues and PRs are welcome in English or Spanish. The instructions and skills themselves are written in Spanish.

## Flow

1. Fork and create a branch `type/kebab-description` (`feat/`, `fix/`, `docs/`, `chore/`, `refactor/`).
2. Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat(skills): add skill for X`).
3. Before opening the PR, run:
   ```bash
   ./install.sh verify      # structure + hook tests + leak scanner
   ./tests/install/test.sh  # if you touched install.sh
   ```
   Add a line to `CHANGELOG.md` under `Unreleased`.
4. Open the PR against `main`. CI runs the `guard.sh` tests and the scanner.

## Rules

- **Nothing personal.** No tokens, real emails, `/home/<user>` paths, or client and private project names. The scanner catches the obvious cases; the rest is on you.
- **Harmless examples** the scanner flags (like `postgresql://user:password@localhost`) go in `scripts/scan-allowlist.txt` with a comment.
- **Models by alias** (`opus`, `sonnet`, `haiku`), never exact IDs.
- **Skills:** each folder in `skills/` has a `SKILL.md` whose `name` and `description` say when to use it.
- **`guard.sh`:** if you touch it, add cases to `hooks/test-guard.sh`.
- **Small, focused changes.** One PR, one topic.

## Reporting a security issue

See [SECURITY.md](SECURITY.md): use GitHub's private reporting, not a public issue.
