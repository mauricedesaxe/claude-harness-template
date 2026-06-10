---
name: work
description: Start working on a GitHub issue end-to-end — jj workspace off latest main, plan, adversarially review the plan, gate on the user, implement, run the reviewer agents, triage findings, then ship. Use when the user says "/work", "/work #12", "work on this issue", "start working on #12", "let's implement #12", or otherwise wants to take an issue from "picked up" to "merged" via the default workflow.
---

# Work Skill

End-to-end workflow for picking up an issue and landing it. Composes the existing
`review` and `ship` skills for the steps they already own, and adds two pieces specific
to picking up new work: a **rough plan** and an **adversarial plan review** that runs
*before* implementation, not after.

The point of the plan-first beat is to catch design mistakes when they cost a paragraph
to fix, not after the diff is written. The user approves the plan before any code is
touched.

## Flow at a glance

```
0. parse arg + sanity-check     5. user approval gate (plan)
1. resolve the issue            6. implement
2. jj workspace off latest main 7. /review
3. draft the plan               8. user triage gate (findings)
4. plan-reviewer agent          9. /ship
```

This skill is **jj-native** (PHILOSOPHY §28): the working copy is Jujutsu, colocated
with git. git stays underneath only as the remote (GitHub, `origin`) that `jj git push`
and `gh` talk to; every local version-control step is jj.

Steps 7 and 9 are not reimplemented here — they invoke the existing
`.claude/skills/review/SKILL.md` and `.claude/skills/ship/SKILL.md` and inherit their
rules (decision table, rebase-merge, `Closes #N`, no `--no-verify`, etc.).

## Step 0: parse arg + sanity-check

`<arg>` is usually an issue ref. Forms:

- Empty → ask which issue (or "freeform" + one-line description). Don't guess.
- `12`, `#12`, `https://github.com/.../issues/12` → fetch with `gh issue view`.
- Freeform description (no `#` and no URL) → proceed without an issue, but ask once
  whether to `/capture` it first. A linked issue is the default; freeform is a
  deliberate skip.

Sanity-check the local state before doing anything mutating:

```sh
jj st                       # working-copy status: what's in @, which commit it sits on
jj log -r 'trunk()..@'      # any local commits in this workspace not yet on trunk
```

Because Step 2 creates a fresh **workspace** with its own `@` off freshly-fetched
trunk, uncommitted changes in the current workspace's `@` (or local commits sitting on
it) are **not** a blocker — the new workspace starts off trunk and can't sweep anything
in. But surface what you see: if those changes look like they were meant to be part of
*this* issue's work, ask before continuing (they won't follow you into the new
workspace).

## Step 1: resolve the issue

```sh
env -u GITHUB_TOKEN gh issue view <#> --json number,title,body,labels,state,url
```

If `state != OPEN`, stop and explain. Read the body. **Pull the felt product outcome
out of it** — that's what the plan delivers, and what the review at the end will be
judged against. If the issue is vague (no clear outcome, no acceptance criteria), don't
paper over it: ask the user to clarify the outcome before continuing.

If the user invoked `/work` with no arg, suggest the top-of-Ready item from the project
board if one exists — that column's order *is* the priority. Don't grab from Backlog
without prompting; Backlog items haven't been scoped yet. Skip items carrying the
`blocked` label and surface what they're waiting on instead of picking them up. The
project number, owner, and field IDs live in the project's `CLAUDE.md` "Issue triage"
section (set them up once after the repo's GitHub Project is created).

## Step 2: create a jj workspace off the latest main

Work happens in a **dedicated jj workspace**, not by moving the shared working copy's
`@`. Multiple agents (and the user) routinely work this repo concurrently (PHILOSOPHY
§14 + §28): the default workspace's `@` belongs to no one in particular, and jj has a
single `@` per workspace — so the isolation unit is a **workspace, not a git worktree**
(a git worktree wouldn't isolate jj's `@`; running jj from it still snapshots the
default workspace and concurrent agents collide). The workspace isolates the code; the
shared repo, `.git`/`.jj` metadata, and GitHub state stay shared.

Generate a branch (bookmark) name from the issue: `<type>/<#>-<short-slug>`. Pick the
conventional-commit type that fits the work (`feat`, `fix`, `refactor`, `chore`,
`docs`, `test`, `perf`, `ci`, `build`). Examples: `feat/12-parser-rewrite`,
`fix/47-decay-boundary`.

Including the issue number in the slug means the `ship` skill auto-detects the
`Closes #N` reference later (see `ship` Step 5a).

Base the workspace on **freshly fetched trunk** — `jj git fetch` first so `trunk()`
resolves to the current `main@origin`, never a stale local ref:

```sh
jj git fetch
mkdir -p .jj/ws                           # jj workspace add won't create parent dirs
jj workspace add --name <#>-<short-slug> --revision 'trunk()' .jj/ws/<#>-<short-slug>
cd .jj/ws/<#>-<short-slug>
jj bookmark create <branch-name> -r @     # reserve the branch name; ship advances it to the tip at push
```

The new workspace's `@` is a fresh empty commit on top of trunk. The bookmark is jj's
branch; it's created here so the name is reserved and discoverable (`jj bookmark
list`), and `ship` moves it forward to your tip commit right before pushing — jj
bookmarks don't auto-follow new commits.

If `.jj/ws/` isn't in `.gitignore`, add it as part of this work's first commit
(colocated jj already excludes `.jj/`, but the explicit entry documents intent and
survives a non-colocated checkout).

From here on, **every command in this workflow runs inside the workspace** — the
implement step, `/review`, `/ship`, every jj and `gh` operation. Don't `cd` back into
the main checkout or another workspace to run something "real quick"; that `@` belongs
to another run.

Show the proposed branch name and workspace path; proceed unless the user renames.

If the project has a board configured in `CLAUDE.md`, move the issue's board item from
**Ready → In progress** so the board reflects what's actually being worked. Field/option
IDs live in `CLAUDE.md` "Issue triage". (When the issue closes at `/ship` time, GitHub
auto-moves the item to Done.)

## Step 3: draft the plan

The plan is a short, scannable Markdown block — not a spec, not a design doc. The bar
is "could a careful reader spot a wrong call from this?" Keep it under ~40 lines.

Required sections:

```markdown
## Outcome
<one sentence: what's better in the product after this lands — pulled from the issue,
not invented. This is the bar the final review judges against.>

## Approach
<3–8 bullets: the shape of the change. New modules, modified modules, the data flow.
Name the files you expect to touch.>

## Type-system shape
<the load-bearing types: discriminated unions, the `Result` error union, any new `as
const` keys. If the change introduces a new external response, name the parser schema.>

## Failure paths
<for each fallible step: what does "unavailable" (upstream failure) look like? what does
"empty result" (legitimately nothing to return) look like? — the "two zeros" distinction
made explicit.>

## Tests
<what lands in the same commit: unit fixtures (boundary cases, edge cases), the
failure-branch test, any recorded integration fixture. If a load-bearing change ships
without tests, the plan is wrong.>

## Out of scope
<what this PR explicitly does NOT do — drift insurance. Be specific.>
```

Do not start writing code yet. The plan is a text artefact for review.

## Step 4: adversarial plan review

Spawn the `plan-reviewer` agent (`.claude/agents/plan-reviewer.md`) with the plan and
the issue body. Its job is to attack the plan against `CLAUDE.md`, any product spec
(`docs/PRD.md` if present), and the business logic — *before* any code exists. It
returns concrete findings (rule, why it matters, what to change), not vibes.

Run it once per plan revision. If the plan changes materially after Step 5 (user said
"do it differently"), re-run Step 4 on the new plan. Re-running is cheap and expected.

The agent reads `CLAUDE.md`, any project spec, and the issue body itself; you do not
have to inline those into the prompt. Give it:

1. The plan as written in Step 3.
2. The issue ref and one-line summary (so it can re-read context if needed).
3. A reminder that its output is collated into a chat report for the user — concrete
   findings, no scope-restating.

## Step 5: user approval gate (plan)

Present a single chat block:

```
# Plan for #<N>: <title>

<the plan from Step 3, verbatim>

## plan-reviewer findings
<findings, or "No issues found.">

### Decision table

| # | Finding | Decision | How / Why |
|---|---|---|---|
| 1 | <one-line summary> | **Fix** | <how the plan changes, ≤2 lines> |
| 2 | <one-line summary> | **Skip** | <why — out of scope, wrong framing, etc.> |
| 3 | <one-line summary> | **Ask** | <the call the user needs to make> |

Net: <N fixes, K skips, M questions>. Ready to implement, or change the plan?
```

The decision-table rules mirror the `review` skill: every finding gets one row, three
decisions only (`Fix` / `Skip` / `Ask`), reasons are terse and concrete. Even a clean
plan-review shows the table with one "no findings" row.

**Wait for the user.** Do not proceed to Step 6 until they say go (or hand you a
revised plan). If they revise, update the plan and re-run Step 4 on the new version.

If the plan-reviewer finds a structural issue the user agrees with (e.g. the plan
violates the "two zeros" rule, or routes an external call outside its integration
module), fix the plan first and re-review — do not "remember to fix it during
implementation". The plan is the design; the design is wrong.

## Step 6: implement

Now write the code. The plan is the spec; deviating mid-implementation is a signal to
pause and update the plan, not to silently drift. If the plan turns out to be wrong
once you have your hands on the code, stop, say so, and revise the plan with the user
before continuing — don't paper over it.

**Commit as you go**, atomically, via the `commit` skill (see
`.claude/skills/commit/SKILL.md`). Don't batch a session's worth of edits into one
megacommit. New behaviour ships with tests in the same commit — the plan's "Tests"
section is the checklist.

## Step 7: /review

Invoke the `review` skill (`.claude/skills/review/SKILL.md`). It runs the reviewer
agents in parallel against the diff and produces a single chat report with a decision
table. Don't reimplement its logic here.

If anything significant came up during implementation that the plan didn't anticipate
(a new module, a new failure mode, a tuning tweak), note it briefly so the user has
context heading into triage.

## Step 8: user triage gate (findings)

Present the `review` skill's output as-is. **Wait for the user** on the decision table:
they confirm what to fix, what to skip, and answer the `Ask` rows. Apply only the
**Fix** rows.

Re-run `/review` after the fixes if anything substantial changed — a new finding can
surface from a fix, and the second pass is cheap. Stop iterating when the diff is
either clean or the remaining rows are explicit `Skip`s the user has signed off on.

If the user pushes back on a finding the reviewers raised, take their call — that's
what the gate is for — but don't quietly delete the finding from the table; mark it
`Skip` with a one-line reason so the trail is visible in the chat record.

## Step 9: /ship

Invoke the `ship` skill (`.claude/skills/ship/SKILL.md`). It handles the rest end-to-end
— push, PR (with `Closes #<N>` auto-detected from the branch name), CI wait, rebase-merge,
workspace cleanup, follow-up prompt.

If the user wants to pause before merging (e.g. for a manual verification on a preview
deploy), stop at PR-open and let them resume `ship` later. The `ship` skill already
handles "resume from wherever we are".

## Don't

- **Don't** move the default workspace's `@` or use a git worktree in a jj repo. Work
  happens in a dedicated **jj workspace** off freshly fetched trunk (Step 2); a git
  worktree wouldn't isolate jj's single `@`.
- **Don't** base a workspace on a stale local trunk ref. `jj git fetch` first; base on
  `trunk()`.
- **Don't** start coding before Step 5 (user approval of the plan). The plan-first beat
  is the whole point.
- **Don't** skip the adversarial review just because the change "feels small". The
  load-bearing rules (Result-not-throw, two-zeros, boundary parsing) are exactly the
  things that look small in a plan and bite in implementation.
- **Don't** quietly revise the plan during implementation. If the plan is wrong, pause
  and re-plan with the user.
- **Don't** re-implement what `review` or `ship` already do. Invoke them. They own the
  decision-table format and the rebase-merge mechanics; matching their rules is their
  job.
- **Don't** drop findings from either decision table without a `Skip` row. Visible
  trail beats silent omission.
- **Don't** invent a `Closes #N` when there's no linked issue (freeform mode). The
  `ship` skill explicitly refuses to fabricate this.
