---
name: commit
description: Commit the changes made in this session as one or more atomic conventional-commit-formatted commits, immediately. Use when a logical chunk of work is finished and ready to be recorded — preferably as you go, not all at once at the end. Use when the user says "commit", "/commit", "commit what we did", or whenever you've completed a discrete piece of work and want it on the branch before moving on.
---

# Commit Skill

Commit the work from this session, now. The bias is toward landing small, atomic commits
as soon as a logical chunk is finished — not batching a session's worth of edits into one
megacommit at the end.

Two non-negotiables in this repo:

- **Conventional commits.** Subject must match
  `^(feat|fix|refactor|chore|docs|test|style|perf|ci|build|revert)(\(.+\))?: .+`.
  Wire a `commit-msg` hook (lefthook / husky / pre-commit) to enforce it; until then, hold
  the format by hand.
- **No `--no-verify`.** Any `pre-commit` hook (lint, typecheck, test) is there because the
  cost of bypassing it once is higher than fixing the underlying problem. If something
  fails, fix the cause and try again.

**No `Co-Authored-By` trailer.** No "Generated with Claude Code" line. Commits carry no
AI-attribution trailers.

## Commit as you go

Don't accumulate a session's worth of edits into one commit:

- Atomic commits are cheaper to revert and easier to read in `git blame` / `git log`.
- Because we **rebase-merge**, every commit on the branch lands on `main` verbatim — so
  each one must read well on its own.
- A failing hook on a 200-line tangle is much harder to debug than on a 30-line change.

When you finish a discrete change — a feature, a fix, a refactor, a doc edit — invoke this
skill, commit, and continue. The atomic conventional-commit format *is* the discipline;
running it is the action.

## Step 1: check what's already staged

```sh
git diff --cached --name-only
```

If anything is listed, those files were staged from before this conversation started.
They are not ours to commit. Either unstage them (`git reset <file>`) or stop and ask —
sweeping them in would mix unrelated work into our change.

## Step 2: identify what changed in this session

Walk the conversation: which files did you `Edit`, `Write`, or create? Cross-reference
against the working tree:

```sh
git status --short
git diff --stat
```

Only commit files that (a) we touched in this session AND (b) have uncommitted changes
right now. Other modified files are pre-existing work that belongs to a different commit.

## Step 3: group into atomic units

One commit is one logical change. The bar: would `git revert <sha>` of this commit alone
leave the codebase in a sane state?

- A new module + its unit tests → one commit (`feat: add <module> client`).
- A bug fix + the regression test that pins it → one commit (`fix: <one-line>`).
- A bug fix in module A + an unrelated refactor in module B → two commits.

If the session's work is one coherent thing, one commit. If it sprawled across separate
concerns, split before committing.

## Step 4: pick the conventional-commit type

| Type       | When                                                          |
| ---------- | ------------------------------------------------------------- |
| `feat`     | new functionality                                             |
| `fix`      | bug fix in existing functionality                             |
| `refactor` | restructuring without behaviour change                        |
| `chore`    | tooling, configs, agents/skills, lockfile bumps               |
| `docs`     | docs-only (`README.md`, `CLAUDE.md`, comments)                |
| `test`     | test-only changes                                             |
| `style`    | formatting only (rare — the formatter handles it)             |
| `perf`     | performance work without behaviour change                     |
| `ci`       | CI workflows, hook configs                                    |
| `build`    | build / package config, lockfiles                             |
| `revert`   | reverting a previous commit                                   |

A scope (`feat(parser):`) is optional — only worth it when the type alone is ambiguous.
Pick scopes from the project's own module names; don't invent freeform tags.

## Step 5: verify, then stage and commit

**Verification gate.** If the repo wires `pre-commit` (lint/typecheck/test), it runs for
you. If it doesn't, run the project's check commands yourself and only commit on green —
search `CLAUDE.md` or the project README for the exact commands (`pnpm check && pnpm test`,
`just check && just test`, `make test`, etc.).

Stage files explicitly — never `git add -A` or `git add .`, which risks pulling in
pre-staged or unrelated work. Then commit using multiple `-m` flags so the subject and
body are joined with blank lines without HEREDOC ceremony:

```sh
git add path/to/file.ts path/to/file.test.ts
git commit \
  -m "feat: add <module> client" \
  -m "Short body explaining the why (not the what). Wrap ~72 chars."
```

Each `-m` becomes its own paragraph. Subject first; the rest become the body. **No
trailers** — no `Co-Authored-By`.

## When the hook fails

If the pre-commit hook fails, **the commit did not happen**. Read the output, fix the
underlying problem (lint error, type error, failing test), re-stage, and create a NEW
commit attempt. Don't reach for `--amend` — there is no commit to amend.

## Style for messages

- Subject: imperative mood, lowercase first word, no trailing period, ~50 chars:
  - `feat: add walking-time matrix lookup`
  - `fix: treat 429 as retryable`
  - `refactor: extract decay curve from score.ts`
- Body (optional, second `-m`): explain *why*, not *what*. Wrap ~72 chars. Skip it when
  the subject is enough.

If `git status` is clean (nothing from this session survived), say so and stop. Never
create empty commits.
