---
name: review
description: Run the project's reviewer agents in parallel against the current diff and report findings in chat. Never posts to GitHub. Use when the user says "review my changes", "/review", or otherwise wants a quality check before commit, push, or merge.
---

# Review Skill

Run the project's reviewer agents in parallel against the current branch's diff vs `main`,
plus any uncommitted edits in the working tree. Collate their findings into a single chat
report. Do not post to GitHub.

The universal reviewers (shipped in `.claude/agents/`) are:

- `code-reviewer` — engineering-quality concerns: module boundaries, ad-hoc env access,
  swallowed errors, unbounded concurrency, type-system holes, missing tests, dependency
  drift. Whether tests *exist* for new behaviour is its call; their *quality* it hands to
  `test-reviewer`.
- `test-reviewer` — adversarial reviewer for changed tests: do they pin the real behaviour
  (not a mock or a proxy), are the failure/err branches and boundaries covered, should a
  test climb the fidelity ladder toward end-to-end.

**Project-specific reviewers** live alongside the universal ones in `.claude/agents/`. If
the project ships a domain reviewer (e.g. `geo-scoring-reviewer`, `payments-reviewer`),
run it here too — see the project's `CLAUDE.md` for what scope each one owns and what to
note about cross-running.

## Step 1: gather the diff

```sh
git diff --name-only main...HEAD       # committed branch changes
git diff --name-only                   # unstaged
git diff --name-only --staged          # staged
```

Deduplicate into one list of changed paths. If the list is empty, say so and stop — there
is nothing to review.

## Step 2: spawn all agents in parallel

Each agent already knows its own scope. Send all the tool calls in a single message so
they run concurrently. Each prompt should give the agent:

1. The diff source — "the diff `main...HEAD` plus any uncommitted edits in the working
   tree".
2. The list of changed paths.
3. A reminder that its output is collated into a single chat report, so it should be
   concrete (file path, line number, fix) and skip restating its own scope.

Don't pre-filter which agents to run based on which files changed. If a reviewer sees no
files in its scope, it returns "no issues found" in seconds — that's the expected outcome.

## Step 3: collate the report

Once all agents return, assemble a single chat report:

```
# Review of <diff source>

Changed files: <count> across <areas>.

## code-reviewer
<findings, or "No issues found.">

## test-reviewer
<findings, or "No issues found.">

## <other reviewers, one section each>
<findings, or "No issues found.">

## Summary
- <N findings across <K> reviewers, or "Clean across all reviewers.">

### Decision table

| # | Finding (file:line) | Decision | How / Why |
|---|---|---|---|
| 1 | <path>:<line> — <one-line summary> | **Fix** | <the concrete edit you'd make, ≤2 lines> |
| 2 | <path>:<line> — <one-line summary> | **Skip** | <why — out of scope, wrong framing, pre-existing pattern, etc.> |
| 3 | <path>:<line> — <one-line summary> | **Ask** | <the call the user needs to make> |

End with one line stating the net (e.g. "Net: 3 fixes, 2 skips, 1 question") and ask the
user whether to apply the **Fix** rows.
```

Keep it tight. Pull out the concrete findings — don't paste raw agent transcripts.

### Decision-table rules

The table is mandatory on every run — even a clean review shows the table with a single
"no findings" row, so the chat shape stays predictable.

- **Every finding gets exactly one row.** Don't drop findings into the prose sections
  without also surfacing them in the table; the table is the actionable artefact.
- **Three decisions only**: `Fix` (you'd apply it now), `Skip` (you wouldn't apply it,
  with a one-line reason), `Ask` (the call is the user's, not yours). Pick one — "fix
  later" is `Skip` with a reason, not its own column.
- **Be opinionated.** Don't fence-sit by labelling everything `Ask`. The user is asking
  you to triage; `Ask` is reserved for genuine judgement calls (e.g. naming choices,
  scope creep, tradeoffs where reasonable people disagree).
- **Skip reasons are terse and concrete** — "pre-existing pattern, not introduced here",
  "axis-mismatch with the surrounding doc", "different risk profile from the sibling
  case", "belongs to a separate hygiene PR". Vague reasons like "low priority" are the
  bug; if you can't articulate why you'd skip it, it's probably a Fix.
- **Each Fix row's How column is a concrete edit**, not a category — name the line and
  the new content (or the shape of it). If you can't, the finding hasn't landed yet —
  push back on the reviewer or do a focused re-read.
- **Pre-existing issues the diff didn't introduce go in the table as Skip rows**, so
  they're visible but explicitly scoped out. Don't omit them silently.

## Notes

- Never post GitHub review comments. This skill produces a chat report only.
- If an agent errors out or returns nothing, note that under its section rather than
  silently dropping it.
- Re-running this skill is cheap and expected — the user iterates.
