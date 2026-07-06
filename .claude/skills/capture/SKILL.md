---
name: capture
description: Capture an idea, feature, or bug as a GitHub issue — but only if it advances a felt product case. Use when the user says "/capture", "capture this", "open an issue", "file a bug", "file an idea", or wants to record work to do later without losing flow.
---

# Capture (to GitHub Issues)

Quickly record something worth doing as a GitHub issue, without breaking flow. The hard part
isn't creating the issue — it's deciding whether it deserves to exist. That decision is the
bar below, and it comes before everything else.

## The bar: felt product value (read this first — it overrides every rule below)

An issue earns its place only if you can name the product outcome it delivers *and that
outcome is felt when using the product*. "Value" means **product value**: does this make
the product more **useful, more trustworthy, or more pleasant to actually use**?

- **The gate is the outcome, not the category of work.** A feature, a bug fix, a refactor,
  or a performance change can each qualify — *if* it moves the product in a way you'd feel.
  Most candidate work does not.
- **Don't bank work that isn't felt.** If a step takes 100 ms and 100 ms is fine, making it
  50 ms is not an issue — there's no felt improvement. Optimize something only when its
  current state is an actual, noticeable problem in use.
- **Internal tidiness is not a product outcome.** "Cleaner code", "more testable", "best
  practice", "more modern", "nice to have" — none of these justify an issue on their own.
  Do that work inline while delivering something real.
- **The project's specific bar** lives in its `CLAUDE.md` (e.g. "the result stays trustworthy
  and explainable", "the latency budget stays under N", "the export is reproducible"). Read
  it and apply it as the test.

When this principle and the Step 2 heuristics disagree, **this principle wins** — in both
directions: a refactor that genuinely unblocks felt value *can* be an issue (framed by that
value); a "feature" nobody will notice should *not* be.

## Step 0: preconditions

Issues live on GitHub, so:

```sh
git remote -v                         # must have a GitHub remote
env -u GITHUB_TOKEN gh auth status    # keyring token (see below)
```

- **No remote** → the repo isn't on GitHub yet, so a capture has nowhere to go. Stop and say
  so; the repo needs to be pushed first (`gh repo create` / push). Don't fabricate an issue.
- **Auth quirk** → if the machine has a `GITHUB_TOKEN` env var with narrower scope than the
  `gh` keyring token, prefix every mutating `gh` call with `env -u GITHUB_TOKEN` (the same
  quirk the `ship` skill documents).

## Step 1: parse arguments

`$ARGUMENTS` is the raw capture. Forms:

- Title only: `/capture Show which items dragged the result down`
- Title + detail, split on `|`: `/capture Show which items dragged the result down | the
  report should call out the missing/distant categories (spec §6)`

If empty, ask for at least a one-line title.

## Step 2: value check (apply the bar)

Run the input through the bar above, then these heuristics. **The heuristics are a fast
filter, not the law — the bar decides.**

**Usually fails the bar — push back unless a felt outcome is named.** If the input is
primarily one of these, don't just create it; ask what felt product outcome it delivers. If
there's a real one, reframe the issue around that outcome. If there isn't, say it should be
done inline (or not at all):

- Refactoring / code moves / module extraction
- Tests or coverage as the deliverable
- Documentation / comments / type-system work as the deliverable
- Schema or column changes framed as the goal
- Internal tooling, dev-env, or CI tweaks
- Micro-optimizing something that is already fast enough

**Rewrite if the value is real but hidden behind a technical framing.** Confirm the rewrite
with the user. Pattern:

| Input | Rewrite | Why |
|---|---|---|
| Add a `<x>_cache` table | Repeat & nearby lookups stay fast and don't re-hit limits | The cache *enables* fast repeat lookups — that's felt |
| Return `unavailable` on 429 | Don't show a misleading result when source data is missing | The value is a result you can trust, not a silent zero |
| Add an `<x>` widget | Show <the felt thing the widget exposes> | The value is what the user sees, not the widget |

**Passes — create it.** A title a non-technical person would understand; one that describes
what you get when using the product; or a bug describing visibly broken product behaviour.

## Step 3: labels

The project may use an `area/*` label scheme (see its `CLAUDE.md` "Issue triage" section).
If so, pick **exactly one `area/*` label**, plus `bug` if it's a visibly broken behaviour,
plus `blocked` if it's waiting on another issue or milestone (the body should say what).

Don't apply `enhancement` or `chore` — those are GitHub-default labels we don't use.

Apply a label only if it exists (`env -u GITHUB_TOKEN gh label list`); otherwise stop and
ask — silently dropping the label loses the signal. If the work genuinely fits none of the
existing `area/*` labels, ask the user before inventing a new area; an area label is meant
to be stable across many issues.

**Appetite (optional second axis, PHILOSOPHY §29).** If the user names one, stamp an
`appetite/S|M|L` label — a fuzzy cap in *sittings* (one / a few / many supervision visits),
not a time estimate. Don't force it: a quick capture can stay un-sized and get its appetite at
`/shape` or pickup. Most single issues are **S** (one sitting). The `appetite/*` labels are
§29 system labels; create them once if missing (`gh label create appetite/S …`, see `shape`).

**Milestone (optional).** If this issue belongs to an initiative being shaped, attach it:
`--milestone "<title>"` on create (or `gh issue edit <N> --milestone …` after). Don't invent a
milestone here — that's `/shape`'s job; capture only *attaches* to one that exists.

## Step 4: create the issue

The body **leads with the felt outcome** — that's the whole point of the bar:

```sh
env -u GITHUB_TOKEN gh issue create \
  --title "<outcome-framed title>" \
  --label "area/<x>[,bug][,blocked]" \
  --body "$(cat <<'EOF'
**Product value:** <the felt outcome — what's better in the product, for whom, when>

<optional: detail, repro steps for a bug, links to spec sections, context from the
conversation>
EOF
)"
```

If the project has a GitHub Project board configured in `CLAUDE.md`, add the new issue to
the **Backlog** column (or whatever the project's default-landing column is). Capture lands
in Backlog by default — moving to Ready is a separate decision the user makes when they
decide to pick it up. The project number, owner, and field/option IDs live in the project's
`CLAUDE.md` "Issue triage" section (see CLAUDE.md for your board's ID/URL and field IDs).

```sh
env -u GITHUB_TOKEN gh project item-add <project#> --owner <owner> --url "<issue url>"
# Then set Status=Backlog (or equivalent) on the returned item.
```

Don't set assignee or milestone unless the user asked. Keep the body short — this is
capture, not planning; it gets refined when the work is picked up.

## Step 5: confirm

Report the number, labels, and column from the command output:

```
Captured #<N>: <title>  [area/<x>]
Backlog · <url>
```

## Board flow (if the project has a GitHub Project board)

Many projects track issues on a single shared **GitHub Project** board. The concrete board
coordinates — project number, owner, project id, the field ids, and the concrete label/field
option lists — are project-specific and live in the project's `CLAUDE.md`. See CLAUDE.md for
your board's ID/URL and field IDs.
<!-- TODO: point this at your board's coordinates in CLAUDE.md -->

Below is the generic mechanism. A well-run board has **orthogonal axes plus a flow column** —
keep them straight, each answers a different question:

1. **Product/app axis (label + board field) — *which* part of the system.** For a monorepo or
   multi-product board this axis names which app/product the work belongs to. Infer it from the
   issue's paths where you can; for a brand-new-product idea or pure research with no path yet,
   **ask** which one rather than defaulting. The concrete option list lives in `CLAUDE.md`.
   <!-- TODO: your board's product/app option list lives in CLAUDE.md -->
2. **`area/*` label — *kind* of work.** In addition to the product axis, not a replacement.
   Exactly one `area/*`. The concrete `area/*` taxonomy in use lives in `CLAUDE.md`; add a new
   `area/*` only when an issue genuinely fits none (ask first).
3. **Milestones — the *roadmap phase* axis.** Orthogonal to Status. The milestone list lives
   in `CLAUDE.md`. Stamp a milestone at capture only when the phase is obvious; otherwise leave
   it for pickup.
4. **`Status` board field — *where in the flow*.** Backlog → To research → Ready to build →
   In progress → Blocked → Done (+ Icebox). **Capture lands new issues in Backlog.**

**Board moves are manual — the board does NOT auto-move on issue close.** Whenever an issue
closes (or a PR closes it), set its `Status` to **Done** yourself. Every other transition is
manual too: `capture` lands Backlog, `research` promotes To research → Ready to build, `work`
sets Ready to build → In progress on pickup, a blocked issue gets the **`blocked` label +
the Blocked column** (both, so it's filterable and visible).

**Commands.** Always refetch field/option IDs (`gh project field-list <project#> --owner
<owner> --format json`) — never hardcode option ids, they can change. Prefix mutating
`gh project`/`gh issue` calls with `env -u GITHUB_TOKEN` when the ambient token lacks
`project` scope.

```sh
# 1. create with BOTH axes of labels (product axis + area/*)
env -u GITHUB_TOKEN gh issue create --title "<outcome-framed>" \
  --label "<product>,area/<area>[,bug][,blocked]" --body "..."
# 2. add to the board
env -u GITHUB_TOKEN gh project item-add <project#> --owner <owner> --url "<issue url>"
# 3. refetch field + option ids, then set Status=Backlog and the product field
env -u GITHUB_TOKEN gh project field-list <project#> --owner <owner> --format json
env -u GITHUB_TOKEN gh project item-edit --project-id <project-id> \
  --id <itemId> --field-id <Status-field-id> --single-select-option-id <Backlog-option-id>
env -u GITHUB_TOKEN gh project item-edit --project-id <project-id> \
  --id <itemId> --field-id <Product-field-id> --single-select-option-id <Product-option-id>
```

## Notes

- The value check is non-negotiable, and **felt product value is the test** — not whether
  something is a "feature" vs a "refactor". If you can't name what's better in the product,
  it isn't an issue.
- Quick capture, not a spec. Refine when the work is picked up.
- If it's tied to current work, reference the related issue/PR in the body (`Refs #N`).
- Re-running is cheap.

## Examples

```
/capture Show which items dragged the result down
→ #<N> [area/<x>] · Backlog — felt: you instantly see why a result scored low.

/capture Fix: result shows 0 when source times out instead of "unavailable"
→ #<N> [area/<x>, bug] · Backlog — felt: the result stops lying when data is missing.

/capture Refactor result.ts into smaller files
→ Pushed back: "Refactoring isn't a product outcome on its own. If splitting result.ts is
   blocking a feature you're about to build, do it as part of that work. What does using
   the product feel like differently afterward? If nothing, skip the issue."

/capture Make the query 2x faster
→ Probed: "Is a lookup actually slow enough that it bugs you in use? If lookups feel fine,
   there's no felt win here. If they're painfully slow and you avoid the tool because of it,
   let's capture 'A lookup returns in under N seconds' instead."
```
