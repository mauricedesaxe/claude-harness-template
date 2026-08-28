---
name: lazar-commit
description: Commit the changes made in this session as one or more atomic conventional-commit-formatted commits, immediately. Use when a logical chunk of work is finished and ready to be recorded, preferably as you go rather than all at once at the end. Use when I say "commit", "/lazar-commit", "commit what we did", or whenever you've finished a discrete piece of work and want it on the branch before moving on.
---

# lazar-commit

Commit the work from this session, now. The bias is toward small, atomic commits that land as
soon as a logical chunk is finished. Not a session's worth of edits batched into one
megacommit at the end.

This skill is **jj-native** (PHILOSOPHY §28): the working copy is Jujutsu, colocated with
git. jj **auto-snapshots** the working directory into the working-copy commit `@`. There is
no index, no `git add`, no staging. A commit is `jj commit [paths] -m "..."`.

Two non-negotiables:

- **Conventional commits.** The subject must match
  `^(feat|fix|refactor|chore|docs|test|style|perf|ci|build|revert)(\(.+\))?: .+`.
  **jj fires no git hooks** (a colocated `commit-msg` hook won't run under `jj commit`), so
  hold the format by hand here. Where the project has CI, it re-enforces this server-side.
- **Run the checks yourself.** Same reason: no `pre-commit` hook fires under jj. Run the
  project's lint/typecheck/test gate (Step 5) *before* finalizing the commit, and only commit
  on green. Don't lean on a hook that isn't going to run.

**No `Co-Authored-By` trailer.** No "Generated with Claude Code" line. Commits carry no
AI-attribution trailers, ever, whatever the harness you're running under appends by default.

## Commit as you go

Don't accumulate a session's worth of edits into one commit:

- Atomic commits are cheaper to revert and easier to read in `jj log` and in blame.
- We **rebase-merge**, so every commit on the branch lands on trunk verbatim. Each one has to
  read well on its own.
- A failing check on a 200-line tangle is much harder to debug than on a 30-line change.

When you finish a discrete change (a feature, a fix, a refactor, a doc edit) invoke this
skill, commit, and continue. The atomic conventional-commit format *is* the discipline;
running it is the action.

## Step 1: see what's in the working copy

jj has no staging area. Everything in the working directory is already snapshotted into `@`.
Look at what `@` holds:

```sh
jj st                 # files changed in @ vs its parent
jj diff --stat        # the same, with line counts
```

Sometimes `@` already holds changes that predate this session, left in this workspace before
the conversation started. They are not yours to claim, and **not** ours to commit wholesale.
Carve only your files into their own commit with explicit paths (Step 5), or stop and ask. A
path-less `jj commit` would sweep everything in `@` into one commit and mix unrelated work
into our change.

## Step 2: identify what changed in this session

Walk the conversation: which files did you `Edit`, `Write`, or create? Cross-reference
against `@`:

```sh
jj st
jj diff --name-only
```

Only commit files that (a) we touched in this session AND (b) show as changed in `@` right
now. Other modified files in `@` are pre-existing work that belongs to a different commit.
Keep them out by naming paths explicitly when you commit.

## Step 3: group into atomic units

One commit is one logical change. The bar: would backing out this commit alone
(`jj backout -r <rev>`) leave the codebase in a sane state?

- A new module plus its unit tests is one commit (`feat: add <module> client`).
- A bug fix plus the regression test that pins it is one commit (`fix: <one-line>`).
- A bug fix in module A plus an unrelated refactor in module B is two commits.

If the session's work is one coherent thing, one commit. If it sprawled across separate
concerns, split before committing.

## Step 4: pick the conventional-commit type

| Type       | When                                              |
| ---------- | ------------------------------------------------- |
| `feat`     | new functionality                                 |
| `fix`      | bug fix in existing functionality                 |
| `refactor` | restructuring without behaviour change            |
| `chore`    | tooling, configs, agents/skills, lockfile bumps   |
| `docs`     | docs-only (`README.md`, `CLAUDE.md`, comments)    |
| `test`     | test-only changes                                 |
| `style`    | formatting only (rare, the formatter handles it)  |
| `perf`     | performance work without behaviour change         |
| `ci`       | CI workflows, hook configs                        |
| `build`    | build / package config, lockfiles                 |
| `revert`   | reverting a previous commit                       |

A scope (`feat(parser):`) is optional, and only worth it when the type alone is ambiguous.
Pick scopes from the project's own module names; don't invent freeform tags.

## Step 5: verify, then commit

**Verification gate.** No `pre-commit` hook fires under jj, so run the project's check
commands yourself and only commit on green. Search `CLAUDE.md` or the project README for the
exact commands (`pnpm check && pnpm test`, `just check && just test`, `make test`, and so
on). Because jj has already snapshotted everything into `@`, the checks run against exactly
what you're about to commit.

**Comment gate (harness).** Run the harness comment-lint over the change before committing.
It rejects every new prose comment token. Only shebangs, leading license headers, and recognized
tooling directives pass. Unchanged comment tokens in edited context do not fail.
It is also the runtime-neutral backstop for the Claude Code write-time hook, so it catches a
comment written under OpenCode or a sandbox where that hook never fired.

```sh
LINT="$HOME/.lazar-harness/bin/comment-lint"
if [ -x "$LINT" ]; then jj diff --git <paths> | "$LINT" diff; fi
```

The `if` guard is load-bearing. On a machine without the harness bin, the whole gate is
skipped and exits 0, so an absent linter never blocks a commit. When it's present, the pipe's
exit status is comment-lint's. Exit 0, proceed.

Nonzero output lists the new comment tokens. Make the code say it, or move longer explanation to
docs. Fix the working copy and re-run the gate. Don't commit over it.

**Complexity gate (harness).** Run complexity-lint after comment-lint. It checks each changed
production JavaScript, TypeScript, or Python file with that file's nearest repository-local
Oxlint or Ruff. It never downloads a tool and fails open when no local tool can run.

```sh
COMPLEXITY_LINT="$HOME/.lazar-harness/bin/complexity-lint"
if [ -x "$COMPLEXITY_LINT" ]; then jj diff --git <paths> | "$COMPLEXITY_LINT"; fi
```

Scores from 11 through 20 are advisory. Scores above 20 block the commit. The linter checks each
whole touched file, so a small edit can expose old complexity outside the changed lines. Fix the
finding or split the commit only when the split matches the intended logical unit.

Replace `<paths>` in both gates with the exact paths for the logical unit you are about to commit.
This keeps unrelated work in `@` from blocking an otherwise valid atomic commit.

Commit by **naming the paths** for this logical unit. Never a path-less `jj commit` when `@`
holds more than one unit, which would sweep it all into one commit. `jj commit <paths>`
finalizes just those paths into a commit and moves the rest to a fresh `@` on top:

```sh
jj commit path/to/file.ts path/to/file.test.ts \
  -m "feat: add <module> client" \
  -m "Short body explaining the why (not the what). Wrap ~72 chars."
```

Each `-m` becomes its own paragraph. Subject first; the rest become the body. **No
trailers**, no `Co-Authored-By`.

For **multiple atomic commits** from one working copy, run `jj commit <paths>` once per unit
in **dependency order**. The base change goes first, because each commit becomes the parent of
the next. Then run a final path-less `jj commit -m "..."` to sweep any remainder. Each commit should
leave the tree buildable. When the whole session is one coherent change, a single path-less
`jj commit -m "..."` is right.

The branch bookmark is advanced to your tip commit at push time by the `lazar-ship` skill, so
you don't need to move it per commit.

## When the checks fail

If the verification gate fails, **don't commit**. Read the output and fix the underlying problem in
the working copy: a lint error, a type error, a failing test. jj re-snapshots it into `@`
automatically. Re-run the checks, and commit once green. There's nothing to `--amend`: the
fix just lands in `@` before you finalize it.

If it's already committed, fold the fix in with `jj squash --from <fix> --into <commit>`. No
fixup commits, and never a `--no-verify` equivalent.

## Style for messages

- Subject: imperative mood, lowercase first word, no trailing period, ~50 chars.
  - `feat: add walking-time matrix lookup`
  - `fix: treat 429 as retryable`
  - `refactor: extract decay curve from score.ts`
- Body (optional, second `-m`): explain *why*, not *what*. Wrap ~72 chars. Skip it when the
  subject is enough.
- **An issue reference is in the tracker's own key format**, and only where the repo's
  history already does this. Resolve which tracker per **Tracker resolution** in `CLAUDE.md`:
  `#12` on GitHub, `ICON-147` on Linear, whatever the repo says. The `lazar-ship` skill reads
  these back out to link the PR, so a guessed reference aims the PR at the wrong issue. Never
  invent one.

If `jj st` shows `@` is empty (nothing from this session survived), say so and stop. Never
create empty commits.
