# Cursor Rules — Memory Bank Protocol

> Guardar este archivo como `.cursorrules` en la raíz del repo.
> Cursor lo lee automáticamente como system prompt.

---

You are an assistant working in a long-running project. Before responding
to ANY substantive request, you MUST follow this protocol.

## Step 1 — Read the Memory Bank

Read the 6 files in `memory-bank/`:

1. `projectbrief.md` — project constitution, almost never changes.
2. `productContext.md` — why the product exists.
3. `systemPatterns.md` — architectural patterns currently in use.
4. `techContext.md` — stack and versions.
5. `activeContext.md` — TODAY's state.
6. `progress.md` — historical log + backlog.

## Step 2 — Read relevant skills

If applicable to the task:

- `erp-saas-core/SKILL.md` and its references (for ERP/SaaS/POS work).
- Other skills referenced in `techContext.md`.

## Step 3 — Confirm understanding

In 3–5 bullets, summarize:

- What project this is.
- What was done in the last session (from `activeContext.md`).
- What is pending (next 1–3 items from `progress.md`).
- Any blocking decisions awaiting human input.

## Step 4 — Wait

Do NOT write code until explicitly instructed.

---

## Immutable rules (from erp-saas-core)

1. `tenantId` from JWT only, never from body.
2. Soft delete via `deletedAt`, never DELETE physically.
3. Money as `Decimal`, never `number`.
4. Banker's rounding `ROUND_HALF_EVEN`.
5. Double-entry: lines sum to 0, validated in domain.
6. Ledger immutable via PostgreSQL triggers; corrections via compensating entries.
7. Idempotency-Key header required on financial mutations.
8. `prisma.$transaction` for multi-table operations.
9. Zero `any`, zero `ts-ignore`, zero unsafe casts.
10. TDD-first for financial logic.
11. Clean Architecture import direction: Domain ← Application ← Infrastructure/Presentation.

---

## Workflow

For any non-trivial task:

1. Propose a plan (files to create/modify, layer order, tests first). Wait for approval.
2. Implement ONE layer at a time (Domain → Application → Infrastructure → Presentation).
3. For financial logic, write tests BEFORE implementation.
4. After implementation, propose diffs to `activeContext.md` and `progress.md`.

If your suggestion contradicts `systemPatterns.md`, notify the user with
2–3 options to resolve, do not silently override.

---

## Closing a session

When user signals end of session, or when context degrades:

1. Propose a unified diff for each Memory Bank file that needs updating.
2. Wait for user approval per file.
3. Remind user to commit the Memory Bank to git.

---

## Output style

- Concrete, not poetic.
- Code first, prose second.
- Maximum 3 options with explicit trade-offs.
- No apologetics. Direct action.

## Language

[Set per project: Spanish / English / etc.]
