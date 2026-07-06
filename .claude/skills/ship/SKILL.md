---
name: ship
description: Land work on `main` end-to-end. jj-native (Jujutsu, colocated with git). Detect current state (uncommitted @, branch commits, bookmark, PR) and run only the steps still missing — name a bookmark if needed, commit the working copy atomically (via the `commit` skill), `jj git push --bookmark`, open a PR with a structured body and `Closes #N`, confirm the check gate is green, merge via `gh pr merge --rebase --delete-branch`, then forget the workspace and `jj git fetch` so trunk picks up the merge. Finishes with a post-merge prompt for follow-up issues. Use when the user says "ship", "/ship", "ship this", "ship it", "land this", "merge this", "merge this PR", or otherwise wants the work landed on `main` without thinking about which intermediate step is missing.
---

# Ship Skill

End-to-end "land this on `main`". The user may be anywhere in the flow — fresh changes on
`main`, partially committed on a branch, pushed-no-PR, PR-no-merge — and `ship` figures
out where they are and runs only the missing steps. It composes the `commit` skill for the
atomic-commit step; everything else (push, PR, merge, follow-ups) is inlined.

This skill is **jj-native** (PHILOSOPHY §28): the working copy is Jujutsu, colocated with
git. Local version control is jj (workspaces, `jj commit`, bookmarks, `jj git push`); the
PR and merge stay on `gh`, and git stays underneath only as the remote those talk to.

**Merge style: `--rebase`** (linear history, no merge commit). Every commit on the branch
lands on `main` exactly as written, so the branch's commit messages are the durable record
— if the per-commit subjects would read badly in `jj log` / `git log` on `main`, fix them
on the branch before merging. Squash is acceptable only when the branch's per-commit
history is genuinely throwaway (one logical change spread across "wip" commits) AND the
user explicitly OKs the collapse. Never `--merge`.

There is **no auto-release workflow** by default. The flow ends when the merge succeeds,
the branch is deleted, and the user is prompted for follow-up issues.

## Auth quirk: gh keyring vs `GITHUB_TOKEN`

If the user has both a `GITHUB_TOKEN` env var and a `gh auth login` keyring token, `gh`
prefers the env var — which often has narrower scope (e.g. only `read:packages`).
Mutations (`gh pr create`, `gh pr merge`, `gh issue create`) need the keyring's `repo`
scope. Force the keyring path per-command by clearing the env var:

```sh
env -u GITHUB_TOKEN gh pr create --base main --title "..." --body "..."
env -u GITHUB_TOKEN gh pr merge <#> --rebase --delete-branch
```

Read calls (`gh pr view`, `gh pr checks`, `gh issue list`) work on either token. Use
`env -u GITHUB_TOKEN` consistently to avoid scope-mismatch surprises.

## Step 1: detect current state

`<arg>` may be empty or a PR number / URL.

**If a PR ref was passed**, use it directly and skip to Step 6:

```sh
env -u GITHUB_TOKEN gh pr view <ref> \
  --json number,title,headRefName,baseRefName,state,mergeable,mergeStateStatus
```

If the state is not `OPEN`, stop and explain (already merged, closed, draft). Don't
auto-create another PR — the user pointed at this one.

**If no ref was passed**, gather the local picture:

```sh
jj git fetch
jj st                                          # is @ non-empty? (uncommitted work)
jj log -r 'trunk()..@'                          # commits on this branch beyond trunk
jj bookmark list -r '::@'                        # the branch bookmark, if any — and whether it shows an @origin counterpart (pushed)
jj workspace root                                # which workspace we're standing in
env -u GITHUB_TOKEN gh pr view \
  --json number,title,headRefName,baseRefName,state,mergeable,mergeStateStatus 2>/dev/null
```

Note which **workspace** you're standing in (`jj workspace root` — the `work` skill's
default is `.jj/ws/<slug>`). Everything below runs the same from inside a workspace; only
the Step 7 cleanup differs. Stay in your workspace for every jj/`gh` operation — never
`cd` into the default workspace to run a step, its `@` belongs to another run.

In jj there's no "current branch": the working copy is always some `@`, with or without a
bookmark naming it. So the state is just (a) does `@` hold uncommitted work, (b) are there
commits in `trunk()..@`, (c) is there a bookmark for them and is it pushed, (d) is there an
open PR. Decide which steps need to run:

| If…                                                          | Run step(s)            |
| ------------------------------------------------------------ | ---------------------- |
| `@` empty, no commits in `trunk()..@`, no bookmark           | Stop — nothing to ship |
| `@` has uncommitted work, no bookmark yet (worked outside `work`) | 2 → 3 → 4 → 5 → 6 → 7 → 8 |
| `@` has uncommitted work, bookmark exists (the `work` default) | 3 → 4 → 5 → 6 → 7 → 8 |
| commits exist, `@` clean, no bookmark yet                    | 2 → 4 → 5 → 6 → 7 → 8 |
| commits exist, bookmark set, not pushed                      | 4 → 5 → 6 → 7 → 8 |
| bookmark pushed, no PR                                        | 5 → 6 → 7 → 8 |
| bookmark pushed, PR open                                      | 6 → 7 → 8 |
| PR state ≠ OPEN                                               | Stop and explain |

State the plan in one line before acting — e.g. "you've got uncommitted work and no
branch yet; I'll commit, name a bookmark, push (the check gate runs), open a PR,
then merge". The user can redirect early.

## Step 2: name a bookmark for the work (only if none exists yet)

The `work` skill already created a bookmark at workspace setup, so this step usually only
fires on the recovery path — you did work directly in a workspace with no bookmark. Unlike
git, jj needs no branch switch: the changes already live in `@` regardless of any
bookmark, so there's nothing to carry.

Auto-generate a name from the changes — pick the conventional-commit type that fits
(`jj diff --stat` + a glance at the changed files), and a short hyphenated slug.
Convention is `<type>/<short-slug>`: `feat/parser-rewrite`, `fix/decay-boundary`,
`chore/claude-skills`.

Show the proposed name and changed-files summary; proceed unless the user renames. Create
the bookmark after committing (Step 3) so it can point at the real tip:

```sh
jj bookmark create <branch-name> -r @-     # @- is the tip commit after `jj commit` leaves an empty @
```

Because Step 1 already ran `jj git fetch`, if your commits sit on a now-stale trunk,
rebase before pushing so the PR isn't born stale: `jj rebase -d 'trunk()'` (see Step 6).

## Step 3: commit the dirty tree (only if uncommitted changes)

Invoke the `commit` skill (`.claude/skills/commit/SKILL.md`) — don't reimplement its rules
here. Two things specific to running it inside `ship`:

- **Preview before committing.** Show the planned commit(s) — one line per commit with the
  subject and the files. Proceed once the user OKs. The standalone `commit` skill commits
  proactively; inside `ship`, the preview gate is worth the extra beat because the user is
  about to ship the result.
- **Foreign changes in `@`.** jj has no staging area — `@` already holds everything in
  the working copy. If Step 1's `jj st` showed changes that predate this work and aren't
  ours, don't sweep them in: commit only our paths (`jj commit <paths>`), or stop and ask.

The `commit` skill runs the verification gate (the project's check commands — no git hook
fires under jj). If it fails, don't commit — fix and retry before Step 4.

If the dirty tree spans multiple unrelated logical changes, split into multiple commits in
dependency order so each commit leaves the tree buildable.

## Step 4: push the branch (only if needed)

First make the bookmark point at your tip commit, then push it. After `jj commit` leaves an
empty `@`, the tip is `@-`; if your latest work is still uncommitted in `@`, commit it
first (Step 3):

```sh
jj bookmark set <branch-name> -r @-           # advance the bookmark to the tip (create with `jj bookmark create` if new)
jj git push --bookmark <branch-name>          # first push auto-tracks the remote; later pushes are safe force-with-lease by default
```

Unlike git, `jj git push` is **force-with-lease by default** — it updates the remote only
if it still matches what jj last fetched, so a clean rebase pushes without ceremony and no
`--force` flag is ever needed. If the push reports the remote moved underneath you (someone
else advanced the branch), surface it and re-fetch rather than forcing past the safety
check.

If the project runs its check gate locally on push (a push wrapper that runs the gate
before `jj git push`), push through that wrapper so the gate fires; a raw `jj git push`
bypasses it. See `CLAUDE.md` for how this project gates.

## Step 5: open a PR (only if no PR exists)

### 5a. Detect linked issue

Scan for an issue reference, in order:

1. **Bookmark name** — e.g. `feat/12-parser-rewrite` → `#12`. Match `\b\d+\b` segments.
2. **Commit descriptions** — `jj log -r 'trunk()..@' --no-graph -T 'description ++ "\n"'`.
   Look for `#N` and `Closes #N` / `Fixes #N` / `Refs #N`.

Resolve to one closing issue: single match → use it; multiple → ask which to close (others
become `Refs #N`); zero → ask once whether this PR should close one. Don't fabricate a
`Closes #N` — a wrong auto-close is worse than none.

### 5b. Compose and open

Title: short Conventional-Commit-style summary, under 70 chars, no trailing period. One
commit → that subject is the title; multiple → summarize the common theme.

Body via heredoc — `Closes` at the top so GitHub picks it up:

```markdown
Closes #N

## Summary
<1–3 bullets, the why — pulled from commit bodies>

## Changes
<high-level what, grouped by area / module>

## Test plan
- [ ] <project's check command> green
- [ ] <project's test command> green
- [ ] manual: <golden-path>
- [ ] manual: <edge case the change is most likely to break>

## Risks
<anything reviewers should look at closely — error paths, concurrency, perf-sensitive
spots, anything the change touches that's load-bearing elsewhere>
```

Drop the `Closes` line if 5a resolved to no closing issue; use `Refs #M` for non-closing
references.

```sh
env -u GITHUB_TOKEN gh pr create --base main --title "..." --body "$(cat <<'EOF'
...body...
EOF
)"
```

Capture the new PR number from the output URL. Don't `--draft` unless asked.

## Step 6: pre-flight — gate green and branch mergeable

Confirm the project's check gate is green before merging. Whether that gate is a remote CI
run or a local pre-push gate is a per-project call (see `CLAUDE.md`):

- **Local pre-push gate** (no remote CI): the gate ran when you pushed via the project's
  push wrapper. Confirm you pushed through that wrapper (or ran the gate by hand); a raw
  `jj git push` skips it. `gh pr checks` reporting no checks is expected in this setup, not
  a problem.
- **Remote CI**: wait for the required checks to go green (`gh pr checks <#> --watch`).

Then check the branch is mergeable:

```sh
jj git fetch
env -u GITHUB_TOKEN gh pr view <#> --json mergeStateStatus,mergeable
```

- The gate passed and `mergeable: MERGEABLE` → continue.
- The gate failed (or you skipped it) → fix and re-push before merging. Don't merge
  a change that hasn't been through the gate without an explicit "merge anyway", and even then
  prefer fixing.

- `mergeStateStatus: BEHIND` → the branch is behind `main`. Since we rebase-merge, update
  by rebasing: `env -u GITHUB_TOKEN gh pr update-branch <#> --rebase`, or locally
  `jj git fetch && jj rebase -d 'trunk()' && <project check> && <project test> &&
  jj bookmark set <branch> -r @- && jj git push --bookmark <branch>`. jj's push is
  force-with-lease by default — no force flag needed. Don't use plain
  `gh pr update-branch <#>` — that creates a merge commit on the branch.

## Step 7: merge

```sh
env -u GITHUB_TOKEN gh pr merge <#> --rebase --delete-branch
```

Local cleanup once the merge succeeds — the shape depends on where you're standing
(detected in Step 1):

**In a jj workspace** (the `work` skill's default):

```sh
jj git fetch                              # pick up the merge + the deleted remote branch
# a workspace can't be forgotten from inside itself — step out to the repo root first
cd "$(jj workspace root)/../../.."        # out of .jj/ws/<slug> (three levels) to the repo root
jj workspace forget <slug>
rm -rf .jj/ws/<slug>
jj bookmark delete <branch> 2>/dev/null || true   # drop the local bookmark; the remote is already gone
```

`jj git fetch` advances `trunk()` to include the merge, so the next workspace bases off it
— there's nothing to `pull` and no default-workspace `@` to disturb. Don't `cd` into
another workspace's `@`: it may belong to another agent mid-run.

**In the default workspace** (recovery path, no dedicated workspace):

```sh
jj git fetch                              # trunk() now includes the merge
jj bookmark delete <branch> 2>/dev/null || true
```

There's no `git checkout main` / `git pull` equivalent to run — jj has no checked-out
branch to fast-forward; `jj git fetch` already moved `trunk()`, and your `@` rebases onto
it whenever you start the next change. Pass `--squash` instead of `--rebase` only for
genuinely throwaway "wip" history with explicit user OK. Never `--merge`.

## Step 8: post-merge follow-ups

```sh
env -u GITHUB_TOKEN gh pr view <#> --json body,closingIssuesReferences
```

Prompt once: *"Any follow-ups to file from this PR? Things that came up during
implementation, open seams worth tracking, deferred TODOs, regressions to investigate."*

For each follow-up named: cross-check open issues
(`env -u GITHUB_TOKEN gh issue list --state open`); if a dupe exists, comment there
instead. If new, draft a one-paragraph body referencing `Surfaced by #<PR-number>` and
file via `env -u GITHUB_TOKEN gh issue create`. No follow-ups → skip; don't fabricate work.

## Step 9: report

Print a summary reflecting only the steps that fired:

```
✓ Created branch <branch>             (only if Step 2 ran)
✓ Committed N change(s):              (only if Step 3 ran)
    <type>(<scope>): <subject>
✓ Pushed branch <branch>              (only if Step 4 ran)
✓ Opened PR #<number>: <title>        (only if Step 5 ran)
✓ Merged PR #<number>: <title>        (--rebase → N commit(s) fast-forwarded onto main)
✓ Forgot workspace <path>             (only if shipping from a jj workspace)
✓ trunk() advanced to <change-id>     (jj git fetch picked up the merge)
✓ <K> follow-up issue(s) filed        (only if Step 8 filed any)
```

## Don't

- **Don't** force past jj's lease. `jj git push` is force-with-lease by default; if it
  reports the remote moved, re-fetch — don't reach for a raw `git push --force`.
- **Don't** touch the default workspace's `@` (`jj edit`, `jj new` there, or any mutation)
  when shipping from a dedicated workspace — it may belong to another agent. Forget your
  workspace and stop; `jj git fetch` already advanced `trunk()` with the merge.
- **Don't** merge with `mergeStateStatus: BLOCKED` or a failing required check.
- **Don't** silently bundle pre-staged unrelated files into Step 3. Stop and ask.
- **Don't** auto-file follow-up issues without confirmation.
- **Don't** open a draft PR unless asked.
- **Don't** use `--merge`. Default is `--rebase`; `--squash` only with explicit OK.
