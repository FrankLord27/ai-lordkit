# Security policy

ai-lordkit changes how Claude Code runs commands on your machine, so security reports matter here.

## Reporting a vulnerability

**Don't open a public issue.** Use GitHub's private reporting instead: [Report a vulnerability](https://github.com/FrankLord27/ai-lordkit/security/advisories/new).

Please include what you ran, what you expected the kit to block or protect, and what happened instead. You'll get an answer within a week.

Examples of what counts:

- A command that gets past `hooks/guard.sh` or the `permissions` in `settings.json` and deletes data, reads an env file or key, or pushes to `main`.
- The installer (`get.sh`, `install.sh`) overwriting or exposing something it shouldn't.
- A token, a real email or personal data in the repo or its history (it will be rotated before anything is made public).

## What the kit does not promise

`guard.sh` compares the command text. A determined trick (building a file name from pieces, for example) can still get past it, which is why interpreters such as `node` and `python` are not auto-approved. Reports that make that net tighter are still welcome.

## Supported versions

Only the latest release and `main` get fixes.
