---
name: commit
description: Commit the changes made in this session as one or more atomic conventional-commit-formatted commits, immediately. Use when a logical chunk of work is finished and ready to be recorded — preferably as you go, not all at once at the end. Use when the user says "commit", "/commit", "commit what we did", or whenever you've completed a discrete piece of work and want it on the branch before moving on.
---

# Commit Skill

Commit the work from this session, now. The bias is toward landing small, atomic commits
as soon as a logical chunk is finished — not batching a session's worth of edits into one
megacommit at the end.

This skill is **jj-native** (PHILOSOPHY §28): the working copy is Jujutsu, colocated with
git. jj **auto-snapshots** the working directory into the working-copy commit `@` — there
is no index, no `git add`, no staging. A commit is `jj commit [paths] -m "..."`.

Two non-negotiables in this repo:

- **Conventional commits.** Subject must match
  `^(feat|fix|refactor|chore|docs|test|style|perf|ci|build|revert)(\(.+\))?: .+`.
  **jj does not fire git hooks** (a colocated `commit-msg` hook won't run under
  `jj commit`), so hold the format by hand here; CI re-enforces it server-side.
- **Run the checks yourself.** Same reason — no `pre-commit` hook fires under jj. Run the
  project's lint/typecheck/test gate (Step 5) *before* finalizing the commit, and only
  commit on green. Don't lean on a hook that isn't going to run.

**No `Co-Authored-By` trailer.** No "Generated with Claude Code" line. Commits carry no
AI-attribution trailers.

## Commit as you go

Don't accumulate a session's worth of edits into one commit:

- Atomic commits are cheaper to revert and easier to read in `jj log` / blame.
- Because we **rebase-merge**, every commit on the branch lands on `main` verbatim — so
  each one must read well on its own.
- A failing check on a 200-line tangle is much harder to debug than on a 30-line change.

When you finish a discrete change — a feature, a fix, a refactor, a doc edit — invoke this
skill, commit, and continue. The atomic conventional-commit format *is* the discipline;
running it is the action.

## Step 1: see what's in the working copy

jj has no staging area — everything in the working directory is already snapshotted into
`@`. Look at what `@` holds:

```sh
jj st                 # files changed in @ vs its parent
jj diff --stat        # the same, with line counts
```

If `@` already contains changes that predate this session (work left in this workspace
before the conversation started, not yours to claim), they are **not** ours to commit
wholesale. Carve only your files into their own commit with explicit paths (Step 5), or
stop and ask — a path-less `jj commit` would sweep everything in `@` into one commit and
mix unrelated work into our change.

## Step 2: identify what changed in this session

Walk the conversation: which files did you `Edit`, `Write`, or create? Cross-reference
against `@`:

```sh
jj st
jj diff --name-only
```

Only commit files that (a) we touched in this session AND (b) show as changed in `@` right
now. Other modified files in `@` are pre-existing work that belongs to a different commit —
keep them out by naming paths explicitly when you commit.

## Step 3: group into atomic units

One commit is one logical change. The bar: would backing out this commit alone
(`jj backout -r <rev>`) leave the codebase in a sane state?

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

## Step 5: verify, then commit

**Verification gate.** No `pre-commit` hook fires under jj, so run the project's check
commands yourself and only commit on green — search `CLAUDE.md` or the project README for
the exact commands (`pnpm check && pnpm test`, `just check && just test`, `make test`,
etc.). Because jj has already snapshotted everything into `@`, the checks run against
exactly what you're about to commit.

Commit by **naming the paths** for this logical unit — never a path-less `jj commit` when
`@` holds more than one unit, which would sweep it all into one commit. `jj commit <paths>`
finalizes just those paths into a commit and moves the rest to a fresh `@` on top:

```sh
jj commit path/to/file.ts path/to/file.test.ts \
  -m "feat: add <module> client" \
  -m "Short body explaining the why (not the what). Wrap ~72 chars."
```

Each `-m` becomes its own paragraph. Subject first; the rest become the body. **No
trailers** — no `Co-Authored-By`.

For **multiple atomic commits** from one working copy, run `jj commit <paths>` once per
unit in **dependency order** (the base change first, since each commit becomes the parent
of the next), then a final path-less `jj commit -m "..."` to sweep any remainder. Each
commit should leave the tree buildable. When the whole session is one coherent change, a
single path-less `jj commit -m "..."` is right.

The branch bookmark is advanced to your tip commit at push time by the `ship` skill — you
don't need to move it per commit.

## When the checks fail

If the verification gate fails, **don't commit**. Read the output, fix the underlying
problem (lint error, type error, failing test) in the working copy — jj re-snapshots it
into `@` automatically — re-run the checks, and commit once green. There's nothing to
`--amend`: the fix just lands in `@` before you finalize it.

## Style for messages

- Subject: imperative mood, lowercase first word, no trailing period, ~50 chars:
  - `feat: add walking-time matrix lookup`
  - `fix: treat 429 as retryable`
  - `refactor: extract decay curve from score.ts`
- Body (optional, second `-m`): explain *why*, not *what*. Wrap ~72 chars. Skip it when
  the subject is enough.

If `jj st` shows `@` is empty (nothing from this session survived), say so and stop. Never
create empty commits.
