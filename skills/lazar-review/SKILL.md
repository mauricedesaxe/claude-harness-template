---
name: lazar-review
description: The one review command. Runs the global reviewer agents, whatever reviewer agents the repo ships, and matt-code-review, then converges everything into a single verdict delivered to whoever is there to read it: chat on a laptop, a posted PR comment in an unattended sandbox. Use when the user says "review my changes", "/lazar-review", or otherwise wants a quality check before commit, push, or merge.
---

# lazar-review

One review, one verdict. It always runs my global agents, and whatever reviewer agents the
repo ships. It folds in `matt-code-review` too, which is why I never invoke that one by hand.

## Step 1: gather the diff

The base is freshly fetched trunk, not a stale local ref. In a jj workspace the local trunk
bookmark may lag or belong to another workspace.

Two inputs are the same wherever this runs. An inherited `GITHUB_TOKEN` outranks `gh auth`'s
own credentials, so unset it or `gh` may answer as the wrong account:

```sh
jj git fetch
env -u GITHUB_TOKEN gh pr view --json number,body 2>/dev/null   # "no PR yet" if this errors
jj log -r 'trunk()..@' --no-graph -T 'description'              # the stack's messages
```

The stack messages and the PR body are where the originating issue is named (`Closes #N`).
Step 4 needs it.

What the reviewers actually read is the part that differs, because it turns on whether they can
see this working copy at all.

<!-- surface:local -->

**The reviewers share this filesystem.** A subagent here is a tool call on the same disk, so
it reads work that exists nowhere else yet. A review of uncommitted edits is most of the value.

jj snapshots the working copy into `@`, so committed work and uncommitted edits come out in
one diff. There's no separate staged gather.

```sh
jj diff --from 'trunk()' --to @ --name-only   # changed paths
jj diff --from 'trunk()' --to @               # the diff the reviewers read
```

If the path list is empty, say so and stop. There's nothing to review.

<!-- /surface:local -->

<!-- surface:sandbox -->

**Each reviewer is a sandbox of its own and cannot see this working copy.** A spawned agent
boots a clean clone of the repo's base branch and never receives this checkout. So a prompt that names a
path here resolves to nothing on the machine that reads it. Every reviewer then fails
identically after booting a full sandbox to do it.

The review is therefore of the **pushed PR**, which a child fetches for itself:

```sh
env -u GITHUB_TOKEN gh pr diff <n> --name-only     # changed paths
env -u GITHUB_TOKEN gh pr diff <n>                 # the diff the reviewers read
env -u GITHUB_TOKEN gh pr view <n> --json commits  # the stack, for git-hygiene-reviewer
```

**Push first, then fan out.** Reviewers may check the head out to read around a hunk and inspect
call sites, rather than reading the diff alone. So the head has to be pushed and current before
a single agent is spawned. A reviewer spawned ahead of the push races a ref that isn't there.

**Nothing pushed means stop.** No PR is not a small diff to review, it's no diff any reviewer
can reach. Say there's nothing pushed, name what the review would cover, and spawn nobody.
Pushing belongs to `lazar-ship`, not here, so hand it back rather than pushing to make the
review possible.

**Only what's pushed reaches a reviewer.** Uncommitted or unpushed work is invisible to every
child, and a review of a stale head reads exactly like a review of the work:

```sh
jj diff --from 'trunk()' --to @ --name-only   # what's actually here
```

If that names paths the PR diff doesn't, push them before reviewing, or name them in the report
as changes nobody reviewed. Silently reviewing the older thing is the failure to avoid.

<!-- /surface:sandbox -->

## Step 2: build the roster

The roster is the union of two sets of **names**. Never hardcode either set, which would rot
the first time an agent was added or renamed.

**The harness's global agents, discovered.** The installer keeps both runtime directories in
parity. Read both so the skill works under either runtime, take each filename without `.md`,
and deduplicate the union:

```sh
for agents_dir in \
  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/agents" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/agents"; do
  for agent in "$agents_dir"/*.md; do
    [ -f "$agent" ] && basename -- "$agent" .md
  done
done
```

Every name discovered there runs on every review. They're what make the code read as if I'd
written it.

**The repo's own, discovered.** A repo's reviewers live in its `.claude/agents/`. Read the
directory and take each agent's `name:` frontmatter:

```sh
ls .claude/agents/*.md 2>/dev/null   # empty is normal and fine
```

Read the `description:` of each one you find. That's how the agent tells you what it covers
and when it applies. Two things it may say:

- **It's scoped to an area.** Skip it when the diff doesn't touch that area, and list it as
  skipped in the report so the omission is visible.
- **It runs in place of another reviewer** (a stack-tuned `code-reviewer`, say). Honour that
  and don't spawn the one it replaces.

Nothing else is inferred from the description. If it doesn't scope itself, it runs.

**On shadowing.** Agents resolve by name, and a repo's agent wins over a global one with the
same name. So a repo that ships its own `yagni-reviewer` doesn't add a name to the roster. It
changes what that name resolves to, and the global copy becomes unreachable. That's the
repo's call to make and the union already handles it. Just don't claim the global one ran:
note in the report that the repo's version shadowed it.

## Step 3: spawn the roster in parallel

Send every agent call in one message so they run concurrently. Each agent knows its own scope
already, so give it the inputs and nothing more:

1. The diff source, worded as below.
2. The list of changed paths.
3. That its findings converge into one report with everyone else's. So it should be concrete,
   with path, line, and the fix, and it should skip restating its own scope.

The diff source is the one input that changes with where this runs, and Step 1 already resolved
which one applies. Hand it over verbatim:

<!-- surface:local -->

> the branch diff `jj diff --from 'trunk()' --to @`, committed plus uncommitted, since jj
> snapshots the working copy into `@`

<!-- /surface:local -->

<!-- surface:sandbox -->

> the pushed PR, `env -u GITHUB_TOKEN gh pr diff <n>`, which you fetch yourself in your own
> sandbox. There is no parent working copy for you to read, and no path from one to quote back

<!-- /surface:sandbox -->

Don't pre-filter a reviewer by which files changed, beyond the description-scoping in Step 2.
A reviewer that sees nothing in its scope returns "no issues found" in seconds, which is the
expected outcome, not a waste.

`git-hygiene-reviewer` reads the commit graph and the PR, not just the file diff. So its prompt
gets what the others don't. The resolved base (`trunk()`). The stack as Step 1 resolved it. The
PR number from Step 1, or "no PR yet" where Step 1 allowed one. Tell it not to re-run
`jj git fetch`, so it judges the same snapshot everyone else did.

## Step 4: run matt-code-review with its inputs pinned

Invoke the `matt-code-review` skill. It asks for a fixed point and hunts for a spec, so hand
it both up front and it won't ask:

- **The fixed point** is the `trunk()` commit Step 1 already resolved. Pass the resolved
  commit, not the name, so it reads the same snapshot as the agents.
- **The spec** is the issue named in the stack messages or the PR body from Step 1. Fetch it
  with `env -u GITHUB_TOKEN gh issue view <n>`, same reason as Step 1, and pass it.
- **No issue named** means there's no spec. Say so explicitly, so its Spec axis skips and
  reports that rather than asking where the spec is. Note the skip in the report.

Its two axes are sub-agents of its own, separate from the roster. That's intended: Standards
and Spec are axes of a diff, not reviewers of a repo.

## Step 5: converge into one verdict

Every reviewer filing its own report is the thing this skill exists to end. Converge by
**finding**, not by reviewer. The reviewer is attribution on a row, not a heading.

```
# Review of <N> files vs trunk

Ran: <roster, comma-separated> + matt-code-review (standards, spec).
Skipped: <agent> (<reason>), or omit this line entirely when nothing was skipped.

| # | Finding | From | Decision | How / Why |
|---|---|---|---|---|
| 1 | <path>:<line>, <one line> | code-reviewer | **Fix** | <the concrete edit, ≤2 lines> |
| 2 | <path>:<line>, <one line> | yagni, clarity | **Skip** | <why> |
| 3 | <path>:<line>, <one line> | spec | **Ask** | <the call I need to make> |

Net: <N fixes, N skips, N questions>. Apply the fixes?
```

The table is the artefact and it's mandatory on every run, including a clean one, where it
gets a single "no findings" row. A predictable shape is most of the value.

- **One row per finding.** When two reviewers land on the same line for the same reason,
  that's one row attributed to both. Overlap is expected and healthy. Duplicate rows aren't.
- **Three decisions.** `Fix` (I'd apply it now), `Skip` (I wouldn't, with a reason), `Ask`
  (the call is mine, not yours). "Fix later" is a `Skip` with a reason, not a fourth column.
- **Be opinionated.** Triage is the job. `Ask` is for genuine judgement calls, not fence-sitting.
- **Skip reasons are concrete.** "Pre-existing, not introduced here", "belongs to a separate
  hygiene PR". "Low priority" is the bug. If you can't say why you'd skip it, it's a Fix.
- **Each Fix names the edit**, not a category. If you can't name it, the finding hasn't landed.
  Push back on the reviewer or re-read the code yourself.
- **Pre-existing issues get Skip rows**, so they're visible and explicitly out of scope. Don't
  drop them silently.
- **An agent that errored or returned nothing** gets a row saying so. A reviewer that silently
  didn't run is worse than one that failed loudly.

Convergence ranks findings against each other. It does not let one axis mask another. That is
what `matt-code-review` keeps its two axes apart to protect. A Spec finding never gets dropped
because Standards came back clean.

Pull out the findings. Don't paste raw agent transcripts.

<!-- surface:local -->

## This never posts to GitHub

Nothing goes out under my name without me seeing it first. This is a hard rule, not a default.

GitHub is read-only here. `gh pr view` and `gh issue view` are the whole surface. Never
`gh pr review`, never `gh pr comment`, never `gh api` with a write method. Tell the reviewers
the same, and pass it on to `matt-code-review`: the output is a chat report and nothing else.

<!-- /surface:local -->

<!-- surface:sandbox -->

## Post the review

**Posting is the deliverable here.** There is no chat for anyone to read, and this sandbox is
torn down when the run ends. A report you keep to yourself is a review that never happened.

The rule this replaces exists to stop anything going out **under Alex's name** that he hasn't read.
That concern doesn't arise here: the review carries the bot's identity, not his. If a runtime ever
posts under his personal token, the local rule applies again and this section does not.

Post the converged report as a PR review or a PR comment. Two limits hold:

- **Only the review.** A merge, a close, an edit to an issue body, or any other `gh api` write
  is out of scope. The read-only rule covers everything except the report you publish.
- **Say what didn't run.** A reviewer that was skipped, a `gh` call that failed, a `§N` you couldn't
  open: name it in the posted review. Nobody watches the transcript to notice a silent gap.

<!-- /surface:sandbox -->
