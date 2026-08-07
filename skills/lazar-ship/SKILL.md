---
name: lazar-ship
description: >
  Land work on trunk end-to-end. jj-native (Jujutsu, colocated with git). Detect the current
  state (uncommitted @, branch commits, bookmark, PR) and run only the steps still missing:
  name a bookmark, commit the working copy atomically via the lazar-commit skill,
  `jj git push --bookmark`, open a PR that links the issue in the tracker's own format,
  confirm the project's check gate is green, rebase-merge, then forget the workspace, fetch
  so trunk picks up the merge, and close out the issue on whatever tracker owns it. Use when
  I say "ship", "/lazar-ship", "ship this", "ship it", "land this", "merge this", "merge this
  PR", or otherwise want the work landed without thinking about which step is missing.
---

# lazar-ship

End-to-end "land this on trunk". I may be anywhere in the flow: fresh changes, partially
committed, pushed-no-PR, or PR-no-merge. Ship works out where I am and runs only the missing
steps. It composes the `lazar-commit` skill for the atomic-commit step; everything else
(push, PR, merge, follow-ups) is inlined.

This skill is **jj-native** (PHILOSOPHY §28): the working copy is Jujutsu, colocated with
git. Local version control is jj: workspaces, `jj commit`, bookmarks, `jj git push`. The PR
and the merge belong to the code host, and git stays underneath only as the remote those talk
to.

**Merge style: `--rebase`** (linear history, no merge commit). Every commit on the branch
lands on trunk exactly as written, so the branch's commit messages are the durable record. If
the per-commit subjects would read badly in `jj log` on trunk, fix them on the branch before
merging. Squash is acceptable only when the branch's per-commit history is genuinely
throwaway (one logical change spread across "wip" commits) AND I explicitly OK the collapse.
Never `--merge`.

There is no auto-release workflow by default. The flow ends when the merge succeeds, the
branch is deleted, the issue is closed out on its tracker, and I'm prompted for follow-ups.

## The code host and the tracker are two different systems

The PR lives where the code lives, so `gh` is right for `gh pr create` and `gh pr merge`
whenever the remote is GitHub. **The issue does not necessarily live there.** Resolve
which tracker owns this repo's issues per **Tracker resolution** in `CLAUDE.md`. Once, at Step 1,
and use that tracker's own tooling for every issue step: `gh issue view` on GitHub, the
Linear MCP on Linear, and so on.

The two coincide on a personal GitHub repo. They come apart on a work repo whose code is on
GitHub and whose issues are in Linear.

## Auth quirk: gh keyring vs `GITHUB_TOKEN`

Where the host is GitHub, a `GITHUB_TOKEN` env var and a `gh auth login` keyring token can
both exist. `gh` prefers the env var, and an ambient one is usually narrower: a CI or
sandbox token with, say, only `read:packages`. Mutations (`gh pr create`, `gh pr merge`,
`gh issue create`) need the keyring's `repo` scope. That is the whole reason for the `env -u`
below, and it's why read calls (`gh pr view`, `gh pr checks`, `gh issue list`) work on either
token:

```sh
env -u GITHUB_TOKEN gh pr create --base <trunk> --title "..." --body "..."
env -u GITHUB_TOKEN gh pr merge <#> --rebase --delete-branch
```

Use it consistently rather than only on mutations, so a scope mismatch never depends on which
call happened to need which scope.

## Step 1: detect current state

`<arg>` may be empty or a PR number / URL.

**If a PR ref was passed**, use it directly and skip to Step 6:

```sh
env -u GITHUB_TOKEN gh pr view <ref> \
  --json number,title,headRefName,baseRefName,state,mergeable,mergeStateStatus
```

If the state is not `OPEN`, stop and explain (already merged, closed, draft). Don't
auto-create another PR, since I pointed at this one.

**If no ref was passed**, gather the local picture:

```sh
jj git fetch
jj st                              # is @ non-empty? (uncommitted work)
jj log -r 'trunk()..@'             # commits on this branch beyond trunk
jj bookmark list -r '::@'          # the bookmark, if any, and whether it has an @origin counterpart (pushed)
jj workspace root                  # which workspace we're standing in
env -u GITHUB_TOKEN gh pr view \
  --json number,title,headRefName,baseRefName,state,mergeable,mergeStateStatus 2>/dev/null
```

Resolve the tracker here too, per **Tracker resolution** in `CLAUDE.md`. Steps 5a, 8 and 8b
all need it, and resolving once means the answer is settled before anything outward happens.

Note which **workspace** you're standing in (`jj workspace root`; the convention is
`.jj/ws/<slug>`, see `CLAUDE.md`). Everything below runs the same from inside a workspace;
only the Step 7 cleanup differs. Stay in your workspace for every jj, `gh` and tracker
operation. Never `cd` into the default workspace to run a step, since its `@` belongs to
another run.

In jj there is no "current branch". The working copy is always some `@`, with or without a
bookmark that names it.
 So the state is just four questions. (a) Does `@` hold uncommitted work? (b) Are there
commits in `trunk()..@`? (c) Is there a bookmark for them, and is it pushed? (d) Is there an
open PR. Decide which steps need to run:

| If…                                                          | Run step(s)            |
| ------------------------------------------------------------ | ---------------------- |
| `@` empty, no commits in `trunk()..@`, no bookmark           | Stop, nothing to ship |
| `@` has uncommitted work, no bookmark yet                    | 2 → 3 → 4 → 5 → 6 → 7 → 8 |
| `@` has uncommitted work, bookmark exists                    | 3 → 4 → 5 → 6 → 7 → 8 |
| commits exist, `@` clean, no bookmark yet                    | 2 → 4 → 5 → 6 → 7 → 8 |
| commits exist, bookmark set, not pushed                      | 4 → 5 → 6 → 7 → 8 |
| bookmark pushed, no PR                                        | 5 → 6 → 7 → 8 |
| bookmark pushed, PR open                                      | 6 → 7 → 8 |
| PR state ≠ OPEN                                               | Stop and explain |

State the plan in one line before acting, e.g. "you've got uncommitted work and no bookmark
yet; I'll commit, name a bookmark, push (the check gate runs), open a PR, then merge". I can
redirect early.

## Step 2: name a bookmark for the work (only if none exists yet)

Unlike git, jj needs no branch switch: the changes already live in `@` regardless of any
bookmark, so there's nothing to carry.

Auto-generate a name from the changes. Pick the conventional-commit type that fits
(`jj diff --stat` plus a glance at the changed files) and a short hyphenated slug. The
convention is `<type>/<slug>`, with the issue key in it where the repo does that:
`feat/parser-rewrite`, `fix/decay-boundary`, `chore/12-claude-skills`.

Show the proposed name and the changed-files summary; proceed unless I rename it. Create the
bookmark after committing (Step 3) so it can point at the real tip:

```sh
jj bookmark create <name> -r @-     # @- is the tip commit, since jj commit leaves an empty @
```

Step 1 already ran `jj git fetch`. So if your commits sit on a now-stale trunk, rebase before
you push, and the PR isn't born stale: `jj rebase -d 'trunk()'` (see Step 6).

## Step 3: commit the dirty tree (only if uncommitted changes)

Invoke the `lazar-commit` skill. Don't reimplement its rules here. Two things are specific to
running it inside ship:

<!-- surface:local -->

- **Preview before committing.** Show the planned commit(s), one line per commit with the
  subject and the files. Proceed once I OK it. The standalone `lazar-commit` skill commits
  proactively; inside ship the preview gate is worth the extra beat, because I'm about to
  ship the result.

<!-- /surface:local -->

<!-- surface:sandbox -->

- **Commit without waiting to be OK'd.** Nobody watches a transcript here, so an approval
  gate on the first step is an approval that never arrives. Push, PR, gate, and merge all sit
  downstream of it. Waiting strands finished work uncommitted in a
  checkout that's torn down at the end of the run. Commit to `lazar-commit`'s rules and list the
  commits in the Step 9 report, which is the thing here that outlives the sandbox.

<!-- /surface:sandbox -->

- **Foreign changes in `@`.** jj has no staging area, so `@` already holds everything in the
  working copy. Step 1's `jj st` sometimes shows changes that predate this work and aren't ours.
  Don't sweep them in. Commit only our paths (`jj commit <paths>`), or stop and ask.

The `lazar-commit` skill runs the verification gate (the project's check commands; no git
hook fires under jj). If it fails, don't commit. Fix and retry before Step 4.

If the dirty tree spans multiple unrelated logical changes, split into multiple commits in
dependency order so each commit leaves the tree buildable.

## Step 4: push the branch (only if needed)

First make the bookmark point at your tip commit, then push it. After `jj commit` leaves an
empty `@` the tip is `@-`; if your latest work is still uncommitted in `@`, commit it first
(Step 3):

```sh
jj bookmark set <name> -r @-           # advance to the tip (create with `jj bookmark create` if new)
jj git push --bookmark <name>          # first push auto-tracks the remote; later pushes are force-with-lease
```

`jj git push --bookmark` is the whole reason not to reach for a raw `git push` here. It
auto-tracks the remote, and it is **force-with-lease by default**. It updates the remote
only where that remote still matches what jj last fetched. A clean rebase pushes without
ceremony, and no `--force` flag is ever needed. A raw `git push` leaves the bookmark untracked in jj and can
spawn divergent duplicates. The push sometimes reports that the remote moved underneath you, because someone
else advanced the branch. Surface it and re-fetch rather than forcing past the safety check.

Some projects run their check gate locally on push, through a wrapper that runs the gate
before `jj git push`. Push through that wrapper so the gate fires. A raw `jj git push` bypasses it.
See `CLAUDE.md` for how this project gates.

## Step 5: open a PR (only if no PR exists)

### 5a. Find the issue this closes

Scan for an issue reference in the tracker's own key format (`#12` on GitHub, `ICON-147` on
Linear, whatever Step 1 resolved), in order:

1. **The bookmark name**, e.g. `feat/12-parser-rewrite` or `feat/icon-147-parser-rewrite`.
2. **The commit descriptions**:
   `jj log -r 'trunk()..@' --no-graph -T 'description ++ "\n"'`. Look for the key, and for
   `Closes` / `Fixes` / `Refs` next to it.

Resolve to one closing issue. A single match, use it. Several, ask which one closes, because
the rest are references. None, ask once whether this PR closes one. Don't fabricate a closing
reference. A wrong auto-close is worse than none.

Read the issue with the tracker's own tooling. Write the PR body from what the issue asked
for, not from what the diff happens to do.

### 5b. Compose and open

Title: a short conventional-commit-style summary, under 70 chars, no trailing period. One
commit, that subject is the title; several, summarize the common theme.

Body via heredoc. How the issue is linked depends on whether the tracker *is* the code host:

- **Tracker is the code host** (GitHub issues on a GitHub repo): `Closes #N` at the top, so
  GitHub picks it up and auto-closes on merge.
- **Tracker is elsewhere**, meaning Linear issues over GitHub code. GitHub has no issue of
  its own to close. A `Closes #N` there would be a lie, or worse, would close an unrelated
  issue that happens to carry that number. Link the issue by key and URL instead, and close it out
  yourself in Step 8.

```markdown
Closes #N          <!-- or: ICON-147 https://linear.app/<org>/issue/ICON-147/<slug> -->

## Summary
<1-3 bullets, the why, pulled from the commit bodies>

## Changes
<high-level what, grouped by area / module>

## Test plan
- [ ] <project's check command> green
- [ ] <project's test command> green
- [ ] manual: <golden-path>
- [ ] manual: <edge case the change is most likely to break>

## Risks
<what a reviewer should look at closely: error paths, concurrency, perf-sensitive spots,
anything the change touches that's load-bearing elsewhere>
```

Drop the link line entirely if 5a resolved to no issue.

```sh
env -u GITHUB_TOKEN gh pr create --base <trunk> --title "..." --body "$(cat <<'EOF'
...body...
EOF
)"
```

Capture the new PR number from the output URL rather than inferring it. Don't `--draft`
unless asked.

## Step 6: pre-flight, gate green and branch mergeable

Confirm the project's check gate is green before merging. Whether that gate is a remote CI
run or a local pre-push gate is a per-project call (see `CLAUDE.md`):

- **Local pre-push gate** (no remote CI): the gate ran when you pushed through the project's
  push wrapper. Confirm you pushed that way, or ran the gate by hand. A raw `jj git push`
  skips it. `gh pr checks` reporting no checks is expected in this setup, not a problem.
- **Remote CI**: wait for the required checks (`gh pr checks <#> --watch`).

Then check the branch is mergeable:

```sh
jj git fetch
env -u GITHUB_TOKEN gh pr view <#> --json mergeStateStatus,mergeable
```

- The gate passed and `mergeable: MERGEABLE`, continue.
- The gate failed, or you skipped it: fix and re-push before merging. Don't merge a change
  that hasn't been through the gate without an explicit "merge anyway", and even then prefer
  fixing.
- `mergeStateStatus: BEHIND`: the branch is behind trunk. Since we rebase-merge, update by
  rebasing: `env -u GITHUB_TOKEN gh pr update-branch <#> --rebase`, or locally
  `jj git fetch && jj rebase -d 'trunk()' && <project check> && <project test> &&
  jj bookmark set <name> -r @- && jj git push --bookmark <name>`. jj's push is
  force-with-lease by default, so no force flag is needed. Don't use plain
  `gh pr update-branch <#>`, which creates a merge commit on the branch.

## Step 7: merge

```sh
env -u GITHUB_TOKEN gh pr merge <#> --rebase --delete-branch
```

Local cleanup once the merge succeeds. The shape depends on where you're standing (detected
in Step 1):

**In a jj workspace:**

```sh
jj git fetch                              # pick up the merge and the deleted remote branch
# a workspace can't be forgotten from inside itself, so step out to the repo root first
cd "$(jj workspace root)/../../.."        # out of .jj/ws/<slug> (three levels) to the repo root
jj workspace forget <slug>
rm -rf .jj/ws/<slug>
jj bookmark delete <name> 2>/dev/null || true   # drop the local bookmark; the remote is gone already
```

`jj git fetch` advances `trunk()` to include the merge, so the next workspace bases off it.
There's nothing to `pull` and no default-workspace `@` to disturb. Don't `cd` into another
workspace's `@`, which may belong to another agent mid-run.

**In the default workspace** (recovery path, no dedicated workspace):

```sh
jj git fetch                              # trunk() now includes the merge
jj bookmark delete <name> 2>/dev/null || true
```

There's no `git checkout main` / `git pull` equivalent to run. jj has no checked-out branch to
fast-forward; `jj git fetch` already moved `trunk()`, and your `@` rebases onto it whenever
you start the next change. Pass `--squash` instead of `--rebase` only for genuinely throwaway
"wip" history, with an explicit OK. Never `--merge`.

## Step 8: post-merge, close the issue out on its tracker (always yours)

**Closing the issue out is the agent's job, always. Never a manual step of mine, never
optional, never "to do later."** A merged PR whose issue still sits open, or still sits in
"In progress" on the board, is a bug in the ship. Do it in the same breath as the merge, for
every issue this PR closed.

What "close it out" means depends on what Step 1 resolved:

- **The tracker is the code host.** The merge already closed the issue via `Closes #N`. But a
  **board does not auto-move on close**, so the item sits stale in its old column and the
  board lies about what shipped. Move each closed issue to the board's done state.
- **The tracker is elsewhere.** Nothing closed automatically. Close the issue and move it to
  done through the tracker's own tooling (the Linear MCP, and so on).

Refetch the board's ids rather than trusting cached ones. They're stable in practice, but
refetching is free and correct. On GitHub Projects, with the board and owner the repo's
tracker config or note names:

```sh
# which issue(s) did this PR close? (empty for a docs-only PR, so nothing to move)
env -u GITHUB_TOKEN gh pr view <#> --json closingIssuesReferences \
  --jq '.closingIssuesReferences[].number'

PROJ=$(env -u GITHUB_TOKEN gh project view <board> --owner <owner> --format json --jq '.id')
read FIELD OPT < <(env -u GITHUB_TOKEN gh project field-list <board> --owner <owner> \
  --format json --jq '.fields[] | select(.name=="Status") | .id as $f
    | .options[] | select(.name=="Done") | "\($f) \(.id)"')

# for each closed issue #N: resolve its item id, set Status=Done
ITEM=$(env -u GITHUB_TOKEN gh project item-list <board> --owner <owner> --format json --limit 300 \
  --jq '.items[] | select(.content.number==<N>) | .id')
env -u GITHUB_TOKEN gh project item-edit --project-id "$PROJ" --id "$ITEM" \
  --field-id "$FIELD" --single-select-option-id "$OPT"
```

If the PR only references an issue without closing it (research, a partial that leaves the
issue open), that issue does **not** move to done. Leave it where it is. Done is for what
this merge actually closed. The `lazar-research` skill overrides this outright: it never
closes and never moves to done.

## Step 8b: post-merge follow-ups

Prompt once: *"Any follow-ups to file from this PR? Things that came up during
implementation, open seams worth tracking, deferred TODOs, regressions to investigate."*

For each follow-up I name, apply the felt-outcome gate in PHILOSOPHY §30 first. Name the
product outcome it delivers, and check it's one I would feel in the product.
"Cleaner" and "more testable" don't clear it. Then cross-check the tracker's open issues for
a duplicate. Comment there instead if one exists. If it's new, draft a one-paragraph body
that references the PR it surfaced in. File it with the tracker's own tooling
(`env -u GITHUB_TOKEN gh issue create` on GitHub, the Linear MCP on Linear).

No follow-ups, skip. Don't fabricate work.

## Step 9: report

Print a summary reflecting only the steps that fired:

```
✓ Named bookmark <name>               (only if Step 2 ran)
✓ Committed N change(s):              (only if Step 3 ran)
    <type>(<scope>): <subject>
✓ Pushed bookmark <name>              (only if Step 4 ran)
✓ Opened PR #<number>: <title>        (only if Step 5 ran)
✓ Merged PR #<number>: <title>        (--rebase → N commit(s) fast-forwarded onto trunk)
✓ Closed out <key> on <tracker>       (every issue the merge closed, Step 8)
✓ Forgot workspace <path>             (only if shipping from a jj workspace)
✓ trunk() advanced to <change-id>     (jj git fetch picked up the merge)
✓ <K> follow-up issue(s) filed        (only if Step 8b filed any)
```

## Don't

- **Don't** assume the tracker is the code host. Resolve it (Step 1) and use its own tooling
  for every issue step. A `Closes #N` aimed at the wrong system closes the wrong issue.
- **Don't** force past jj's lease. `jj git push` is force-with-lease by default; if it reports
  that the remote moved, re-fetch. Never reach for a raw `git push --force`.
- **Don't** touch the default workspace's `@` (`jj edit`, `jj new` there, or any mutation)
  when shipping from a dedicated workspace, since it may belong to another agent. Forget your
  workspace and stop; `jj git fetch` already advanced `trunk()` with the merge.
- **Don't** merge with `mergeStateStatus: BLOCKED` or a failing required check.
- **Don't** leave the issue open or the board stale after a merge. Step 8 is the agent's job,
  not mine.
- **Don't** silently bundle unrelated pre-existing changes into Step 3. Stop and ask.
- **Don't** auto-file follow-up issues without confirmation.
- **Don't** open a draft PR unless asked.
- **Don't** use `--merge`. The default is `--rebase`; `--squash` only with an explicit OK.
