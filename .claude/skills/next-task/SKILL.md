---
name: next-task
description: Surface the top 3 highest-impact, most-immediate things to work on next — repo-wide or scoped to one area. Use when the user says "/next-task", "/next-task <area>", "what should I work on next", "what's next", or wants a ranked shortlist pulled from the board, open issues, and roadmap docs.
---

# Next-task Skill

Answer one question: **what are the top 3 things to pick up right now**, across the whole
repo or scoped to a single area/app. The output is a tight ranked shortlist (~10 lines),
not a report.

The heavy lifting — reading the board, every open issue's body/labels/milestone, comments,
and the roadmap docs — happens in a **single spawned subagent**, so the caller's context
stays clean. This mirrors how `review` and `work` already spawn agents from a skill. The
main thread does three things only: parse the optional area arg, spawn the gather+rank
subagent, and relay back the subagent's ranked block verbatim.

## Step 0: parse the optional area arg

`$ARGUMENTS` is an optional scope:

- empty → **repo-wide** (rank across everything).
- an area/app name → scope the ranking to that area (boost items with that `App` field /
  `app:*` label; still surface a cross-area blocker if one gates the top item — see the
  ranking rules). CLAUDE.md names the valid area/App values for this repo.

If the arg is something else, ask once whether they meant one of the known area values or
repo-wide. Don't guess.

## Step 1: spawn the gather+rank subagent

Spawn ONE general-purpose subagent with the instructions below. It does all reads and
returns ONLY the final ranked block (Step 3 format). Do not gather in the main thread.

Give the subagent:

1. The area scope from Step 0 (or "repo-wide").
2. The gather instructions (Step 2).
3. The ranking rules + output format (Step 3) — and a hard instruction to return *only*
   that block, nothing else.

## Step 2: gather (subagent, read-only — never mutate)

Use the project board — see CLAUDE.md for its ID/URL/owner. Prefix `gh` calls with
`env -u GITHUB_TOKEN` if the ambient token lacks `project` scope.

- **Board state** — items with their fields (`gh project item-list …`, `gh project
  field-list …` with the board's number and owner from CLAUDE.md). Read each item's
  `Status`, `App`, `Milestone`, and `updatedAt`.
- **Open issues** with bodies, labels, milestones:
  ```sh
  env -u GITHUB_TOKEN gh issue list --state open --limit 200 \
    --json number,title,labels,milestone,updatedAt,url,body
  ```
- **Comments** on each surviving candidate (after a first-pass cut) for the latest signal:
  `env -u GITHUB_TOKEN gh issue view <N> --json comments`.
- **Milestones + active bets** (the Shape Up initiative layer): `env -u GITHUB_TOKEN gh api
  repos/<owner>/<repo>/milestones?state=all` (owner/repo from CLAUDE.md). An **active bet**
  is an *open* milestone with a `due_on` set (the cutoff); note which those are and their due
  dates — issues under an active bet are what you're committed to right now.
- **Roadmap docs**: any `docs/**` or per-area roadmap/PRD files. These name what's "next" on
  each area's roadmap.

Read-only throughout. This skill never edits the board, never creates issues, never moves a
column.

## Step 3: rank and format (subagent returns ONLY this block)

**Ranking signals** — every one must come from a readable source; do not invent
"owner-signaled" or other unfalsifiable inputs:

- **Flow column** (board `Status`): favor **In progress**, then **Ready to build**. Penalize
  **Blocked**. **Exclude** Icebox, Done, and closed issues entirely.
- **Unblocked beats blocked.** An item carrying the `blocked` label or sitting in Blocked
  drops below any actionable item.
- **Unblocks others** — an item that other open issues say `Depends on #this` ranks up
  (source: backlinks / `Depends on #N` in bodies).
- **Active bet (strong boost)** — an item under an *active bet* (its milestone is open with a
  `due_on`) is something you've committed to; boost it hard. This is the main signal:
  `next-task` picks the next *issue inside a bet*. A near-due cutoff boosts further (the
  circuit breaker is approaching). An item under *no* active bet can still surface — a small
  high-impact issue floats up on its own merits — but flag it as off-bet so the user sees it
  isn't part of a committed initiative.
- **Impact** — how much the item moves the product's felt value (the `capture` bar, read from
  the body: a trust/usefulness/pleasantness gain beats internal tidying). Weigh impact
  *alongside* appetite: a small `appetite/S` high-impact issue can outrank a big `appetite/L`
  one. Cheap ≠ worth it; worth it ≠ affordable right now — it's the product of the two.
- **Milestone phase** = the board `Milestone` field or issue milestone. Independent of the bet
  signal: boost items on the area's current (open, nearest-due) milestone; the roadmap docs say
  which phase is current.
- **Recency / priority** = board item `updatedAt` + latest issue/comment timestamp + any
  explicit priority label. Mild staleness penalty for items untouched for a long time.
- **Area focus** (when scoped): boost items whose `App`/`app:*` matches the arg.

**Deterministic tie-break (so the top-3 is stable run to run):** after scoring, break ties
by board column order (In progress > Ready to build > To research > Backlog > Blocked), then
by ascending issue number.

**Edge cases — handle explicitly, don't force a top-3:**

- **No actionable items** (nothing In progress or Ready to build): say so plainly, then
  surface the top **Blocked** items and, for each, what unblocks it. Don't manufacture a
  ranked three out of backlog noise.
- **Area scope with a cross-area blocker**: if the scoped area's top item is blocked by a
  shared or other-area issue, name that cross-area blocker (`#N`, its area) in the output so
  the dependency is visible.

**Output (~10 lines):**

```
Next up <(repo-wide) | for <area>>:

1. #<N> <title>
   <area> · <Status> · <milestone or "—"> · <url>
   <one-line rationale: why it's #1 right now>
2. #<N> <title>
   <area> · <Status> · <milestone or "—"> · <url>
   <one-line rationale>
3. #<N> <title>
   <area> · <Status> · <milestone or "—"> · <url>
   <one-line rationale>

<optional one-line note: e.g. a cross-area blocker, "nothing actionable — top blocked item
is #N, waiting on #M", or a staleness flag>
```

## Step 4: relay

Return the subagent's block to the user verbatim. Don't re-rank, don't expand it into a
report, don't act on it — `next-task` only *recommends*. Picking one up is `/work <N>`.

## Don't

- **Don't** gather in the main thread. The reads are heavy; they belong in the subagent so
  caller context stays clean.
- **Don't** mutate anything — no board moves, no label edits, no issue creation.
- **Don't** invent ranking signals with no readable source.
- **Don't** force a top-3 when nothing is actionable — say so and surface blockers instead.
