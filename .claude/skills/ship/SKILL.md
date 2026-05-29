---
name: ship
description: Land work on `main` end-to-end. Detect current state (branch, tree, remote, PR) and run only the steps still missing — branch off `main` if needed, commit the dirty tree atomically (via the `commit` skill), push, open a PR with a structured body and `Closes #N`, wait for CI, merge via `gh pr merge --rebase --delete-branch`, then fast-forward `main` locally. Finishes with a post-merge prompt for follow-up issues. Use when the user says "ship", "/ship", "ship this", "ship it", "land this", "merge this", "merge this PR", or otherwise wants the work landed on `main` without thinking about which intermediate step is missing.
---

# Ship Skill

End-to-end "land this on `main`". The user may be anywhere in the flow — fresh changes on
`main`, partially committed on a branch, pushed-no-PR, PR-no-merge — and `ship` figures
out where they are and runs only the missing steps. It composes the `commit` skill for the
atomic-commit step; everything else (push, PR, merge, follow-ups) is inlined.

**Merge style: `--rebase`** (linear history, no merge commit). Every commit on the branch
lands on `main` exactly as written, so the branch's commit messages are the durable record
— if the per-commit subjects would read badly in `git log` on `main`, fix them on the
branch before merging. Squash is acceptable only when the branch's per-commit history is
genuinely throwaway (one logical change spread across "wip" commits) AND the user
explicitly OKs the collapse. Never `--merge`.

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
git branch --show-current
git status --short
git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null
git log --oneline @{u}..HEAD 2>/dev/null
env -u GITHUB_TOKEN gh pr view \
  --json number,title,headRefName,baseRefName,state,mergeable,mergeStateStatus 2>/dev/null
```

Decide which steps need to run:

| If…                                              | Run step(s)            |
| ------------------------------------------------ | ---------------------- |
| On `main`, tree clean                            | Stop — nothing to ship |
| On `main`, tree dirty                            | 2 → 3 → 4 → 5 → 6 → 7 → 8 |
| On feature branch, tree dirty                    | 3 → 4 → 5 → 6 → 7 → 8 |
| On feature branch, clean, unpushed               | 4 → 5 → 6 → 7 → 8 |
| On feature branch, clean, pushed, no PR          | 5 → 6 → 7 → 8 |
| On feature branch, clean, pushed, PR open        | 6 → 7 → 8 |
| Detached HEAD, or PR state ≠ OPEN                | Stop and explain |

State the plan in one line before acting — e.g. "you're on main with uncommitted changes;
I'll branch, commit, push, open a PR, wait for CI, then merge". The user can redirect
early.

## Step 2: create a feature branch (only if currently on `main`)

Auto-generate a branch name from the dirty changes — pick the conventional-commit type
that fits (`git diff --stat` + a glance at the changed files), and a short hyphenated
slug. Convention is `<type>/<short-slug>`: `feat/parser-rewrite`,
`fix/decay-boundary`, `chore/claude-skills`.

Show the proposed name and changed-files summary; proceed unless the user renames:

```sh
git switch -c <branch-name>
```

`git switch -c` carries the uncommitted changes onto the new branch — no stashing.

## Step 3: commit the dirty tree (only if uncommitted changes)

Invoke the `commit` skill (`.claude/skills/commit/SKILL.md`) — don't reimplement its rules
here. Two things specific to running it inside `ship`:

- **Preview before committing.** Show the planned commit(s) — one line per commit with the
  subject and the files. Proceed once the user OKs. The standalone `commit` skill commits
  proactively; inside `ship`, the preview gate is worth the extra beat because the user is
  about to ship the result.
- **Pre-staged files that aren't ours.** If `git diff --cached --name-only` returned
  anything at the start of the run that doesn't belong to this work, stop and ask.

The `commit` skill runs the verification gate (the `pre-commit` hook, or the project's
check commands). If it fails, the commit doesn't happen — fix and retry before Step 4.

If the dirty tree spans multiple unrelated logical changes, split into multiple commits in
dependency order so each commit leaves the tree buildable.

## Step 4: push the branch (only if needed)

```sh
git push -u origin "$(git branch --show-current)"   # no upstream → first push
git push                                            # has upstream, ahead
```

If the upstream is behind a local rebase that hasn't been force-pushed, `git push` will
reject. Surface the conflict; offer `git push --force-with-lease` only if the user
explicitly asked for the rebase. Never plain `--force`, never silently force-push.

## Step 5: open a PR (only if no PR exists)

### 5a. Detect linked issue

Scan for an issue reference, in order:

1. **Branch name** — e.g. `feat/12-parser-rewrite` → `#12`. Match `\b\d+\b` segments.
2. **Commit subjects + bodies** — `git log main..HEAD --pretty=format:'%s%n%n%b'`. Look
   for `#N` and `Closes #N` / `Fixes #N` / `Refs #N`.

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

## Step 6: pre-flight — CI green and branch mergeable

```sh
git fetch origin main
env -u GITHUB_TOKEN gh pr view <#> --json mergeStateStatus,mergeable
env -u GITHUB_TOKEN gh pr checks <#>
```

- All required checks passing → continue.
- Failing → show the output and ask whether to wait, fix, or override. Don't merge a red
  PR without an explicit "merge anyway", and even then prefer fixing.
- Pending → wait. Use Bash with `run_in_background` and an `until`-loop:

  ```sh
  until env -u GITHUB_TOKEN gh pr checks <n> --json bucket \
          --jq 'all(.bucket != "pending")' 2>/dev/null | grep -q true; do
    sleep 20
  done
  env -u GITHUB_TOKEN gh pr checks <n>
  ```

- `mergeStateStatus: BEHIND` → the branch is behind `main`. Since we rebase-merge, update
  by rebasing: `env -u GITHUB_TOKEN gh pr update-branch <#> --rebase`, or locally
  `git fetch origin main && git rebase origin/main && <project check> && <project test> &&
  git push --force-with-lease`. Don't use plain `gh pr update-branch <#>` — that creates a
  merge commit on the branch.

## Step 7: merge

```sh
env -u GITHUB_TOKEN gh pr merge <#> --rebase --delete-branch
```

Local cleanup once the merge succeeds:

```sh
git checkout main
git pull --ff-only
git branch -D <branch>     # remote already deleted by --delete-branch
```

Don't delete the local branch before confirming the remote was deleted. Pass `--squash`
instead of `--rebase` only for genuinely throwaway "wip" history with explicit user OK.
Never `--merge`.

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
✓ Local main fast-forwarded to <sha>
✓ <K> follow-up issue(s) filed        (only if Step 8 filed any)
```

## Don't

- **Don't** plain `--force` push. `--force-with-lease`, only with explicit consent.
- **Don't** merge with `mergeStateStatus: BLOCKED` or a failing required check.
- **Don't** silently bundle pre-staged unrelated files into Step 3. Stop and ask.
- **Don't** auto-file follow-up issues without confirmation.
- **Don't** open a draft PR unless asked.
- **Don't** use `--merge`. Default is `--rebase`; `--squash` only with explicit OK.
