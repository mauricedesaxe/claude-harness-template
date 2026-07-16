---
name: lazar-review
description: The one review command. Runs the global reviewer agents, whatever reviewer agents the repo ships, and matt-code-review, then converges everything into a single verdict in chat. Never posts to GitHub. Use when the user says "review my changes", "/lazar-review", or otherwise wants a quality check before commit, push, or merge.
---

# lazar-review

One review, one verdict. It always runs my three global agents, it runs whatever reviewer
agents the repo ships, and it folds in `matt-code-review`, which is why I never invoke that
one by hand.

## Step 1: gather the diff

The base is freshly fetched trunk, not a stale local ref. In a jj workspace the local trunk
bookmark may lag or belong to another workspace.

jj snapshots the working copy into `@`, so committed work and uncommitted edits come out in
one diff. There's no separate staged gather.

```sh
jj git fetch
jj diff --from 'trunk()' --to @ --name-only   # changed paths
jj diff --from 'trunk()' --to @               # the diff the reviewers read
```

If the path list is empty, say so and stop. There's nothing to review.

Grab two more inputs while you're here. An inherited `GITHUB_TOKEN` outranks `gh auth`'s own
credentials, so unset it or `gh` may answer as the wrong account:

```sh
env -u GITHUB_TOKEN gh pr view --json number,body 2>/dev/null   # "no PR yet" if this errors
jj log -r 'trunk()..@' --no-graph -T 'description'              # the stack's messages
```

The stack messages and the PR body are where the originating issue is named (`Closes #N`).
Step 4 needs it.

## Step 2: build the roster

The roster is the union of two sets of **names**. Never a hardcoded list of the repo's
reviewers, which would rot the first time a repo renamed one.

**The global three, always.** `git-hygiene-reviewer`, `clarity-reviewer`, `yagni-reviewer`.
They run on every review, in every repo, whether or not the repo ships anything of its own.
They're what make the code read as if I'd written it.

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
same name. So a repo that ships its own `yagni-reviewer` doesn't add a name to the roster, it
changes what that name resolves to, and the global copy can't be reached at all. That's the
repo's call to make and the union already handles it. Just don't claim the global one ran:
note in the report that the repo's version shadowed it.

## Step 3: spawn the roster in parallel

Send every agent call in one message so they run concurrently. Each agent knows its own scope
already, so give it the inputs and nothing more:

1. The diff source: "the branch diff `jj diff --from 'trunk()' --to @`, committed plus
   uncommitted, since jj snapshots the working copy into `@`".
2. The list of changed paths.
3. That its findings get converged into one report with everyone else's, so it should be
   concrete (path, line, the fix) and skip restating its own scope.

Don't pre-filter a reviewer by which files changed, beyond the description-scoping in Step 2.
A reviewer that sees nothing in its scope returns "no issues found" in seconds, which is the
expected outcome, not a waste.

`git-hygiene-reviewer` reads the commit graph and the PR, not just the file diff, so its
prompt gets what the others don't: the resolved base (`trunk()`), the stack range
(`trunk()..@`), and the PR number or "no PR yet" from Step 1. Tell it not to re-run
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

Convergence ranks findings against each other. It does not let one axis mask another, which is
the thing `matt-code-review` keeps its two axes apart to protect: a Spec finding never gets
dropped because Standards came back clean.

Pull out the findings. Don't paste raw agent transcripts.

## This never posts to GitHub

Nothing goes out under my name without me seeing it first. This is a hard rule, not a default.

GitHub is read-only here. `gh pr view` and `gh issue view` are the whole surface. Never
`gh pr review`, never `gh pr comment`, never `gh api` with a write method. Tell the reviewers
the same, and pass it on to `matt-code-review`: the output is a chat report and nothing else.
