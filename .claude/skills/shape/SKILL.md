---
name: shape
description: Shape a raw initiative into a bettable milestone — name the felt outcome, set an appetite in sittings, sketch which issues are in vs out, and hunt the rabbit hole that could blow the appetite. The initiative-layer counterpart to capture (PHILOSOPHY §29). Use when the user says "/shape", "shape this", "shape <idea> into a milestone", "turn this into an initiative", or has a multi-issue effort worth planning before committing to it. Shaping is NOT betting — it leaves the milestone open and un-bet for /bet to commit later. Can conclude "don't build this," which is a success.
---

# Shape (an initiative → a bettable milestone)

The upper of the two altitudes (PHILOSOPHY §29). An **initiative** is a multi-issue effort (a
migration, a new service, a platform move), and a GitHub **milestone** is how we hold one.
`shape` takes a raw initiative idea and turns it into a *shaped milestone*: a felt outcome, a
declared appetite, a clear in/out boundary, and a killed rabbit hole. The milestone's
description **is** the pitch.

Shaping is the counterpart to `capture` one altitude up. `capture` decides whether a single
*issue* deserves to exist; `shape` decides whether an *initiative* is worth betting on, and
what its shape is if so. It does **not** place the bet — that's `/bet`, a separate act, so you
can shape several initiatives in one sitting and bet across them later.

## The bar: a felt outcome that fits an appetite

An initiative earns a shaped milestone only if you can name **the product outcome it
delivers** (the same felt-value bar `capture` applies, read its "felt product value" section)
**and** a believable **appetite** it fits inside. Shape Up's core trade is fixed appetite,
variable scope: you don't ask "how long will this take", you declare "this is worth *this
much*" and then cut scope to fit. If the felt outcome can't fit any sane appetite, the honest
shape is **don't build it** — say so and stop. That's the rabbit-hole hunt doing its job, not
a failure.

## Appetite, in sittings

Appetite is a **declared cap on your supervision attention**, counted in **sittings** — one
sitting is one time you sit down, check the agent, redirect it, and leave (PHILOSOPHY §29).
It is fuzzy and never auto-counted. Three bands:

- **S — one sitting.** Fire it once, one check, done.
- **M — a few sittings.** A handful of agent-runs and checks over a couple of days.
- **L — many sittings.** Many check-ins over a week or more of real calendar time.

An initiative is almost always **M or L** (a single-sitting effort is usually one issue, so
`capture` + `work` it instead of shaping a milestone). The band lives in the milestone
description; the per-issue `appetite/S|M|L` labels are set by `capture` on the issues inside.

## Step 0: parse the arg

`$ARGUMENTS` is either:

- a **raw initiative idea** (`/shape move every deploy onto one platform`), or
- an **existing milestone** to (re)shape (`/shape #M3`, `/shape "the cutover"`), e.g. when
  the circuit breaker kicked one back to the drawing board.

If empty, ask for a one-line initiative description.

## Step 1: fetch context (read-only)

The project board and repo are bound in CLAUDE.md (board ID/URL, owner, repo). Prefix `gh`
with `env -u GITHUB_TOKEN` if the ambient token lacks `project` scope.

```sh
# existing milestones (state, due_on = cutoff, description = prior shape)
env -u GITHUB_TOKEN gh api repos/<owner>/<repo>/milestones --jq \
  '.[] | {number, title, state, due_on, open_issues, closed_issues}'
# open issues that might already belong to this initiative
env -u GITHUB_TOKEN gh issue list --repo <owner>/<repo> --state open \
  --limit 200 --json number,title,labels,milestone,url,body
```

Also read CLAUDE.md (its milestone list + `area/*` taxonomy) and any roadmap doc, so the shape
lines up with what the project already calls its phases.

## Step 2: frame the shape (with the user)

Draft these four things and confirm them before writing anything:

1. **Felt outcome** — what's better in the product when this initiative ships, for whom, when.
   One or two sentences. If you can't write it, it's not an initiative, it's housekeeping.
2. **Appetite** — S/M/L, with a word on why (what makes it worth that much and no more).
3. **In / out** — the issues (existing or to-capture) that are *in*, and an explicit **out**
   list: the tempting things you're deliberately not doing to fit the appetite. The out-list
   is where scope gets hammered; name it, don't leave it implicit.
4. **Rabbit hole** — the one unknown that could blow the appetite (an unproven integration, a
   data-shape you haven't seen, a third-party limit). See Step 3.

## Step 3: hunt the rabbit hole

The rabbit hole is the thing that turns an M into a runaway L. Name it explicitly. Then:

- If it's answerable from what you already know, resolve it in the shape (or **de-scope** it to
  the out-list).
- If it genuinely needs investigation, this is **`/research` at the milestone altitude** —
  `research` runs at both altitudes (a milestone-scale feasibility question is exactly its
  upper-altitude use). Recommend `/research <the question>`, and don't finish shaping until the
  verdict is in. A shape built over an un-hunted rabbit hole is the exact failure §29 is
  guarding against.

If the rabbit hole can't be resolved or de-scoped inside the appetite, the verdict is **don't
build this** — record why (one paragraph) and stop. No milestone gets created.

## Step 4: write the shaped milestone

Create (or update) an **open** milestone. Open + **no due date** is the durable marker for
*shaped but not yet bet* — `/bet` sets the due date (the cutoff) when it commits the bet.

```sh
env -u GITHUB_TOKEN gh api repos/<owner>/<repo>/milestones \
  -f title="<initiative name>" \
  -f state="open" \
  -f description="$(cat <<'EOF'
**State:** shaped (not yet bet)
**Appetite:** <S|M|L> — <one line on why this much>
**App:** <the App-axis value — see CLAUDE.md>

**Felt outcome:** <what's better in the product, for whom, when>

**In:**
- #<N> <title>  (or "to capture: <one-liner>")
- ...

**Out (deliberately, to fit the appetite):**
- <the tempting thing we're not doing> — <why it's out>

**Rabbit hole:** <the unknown that could blow the appetite> — <resolved how / de-scoped to out / researched in #N>
EOF
)"
# To reshape an existing one instead, PATCH it:
# env -u GITHUB_TOKEN gh api repos/<owner>/<repo>/milestones/<num> -X PATCH -f description="..."
```

Then attach the **in** issues that already exist, and stamp their appetite:

```sh
# attach an existing issue to the milestone
env -u GITHUB_TOKEN gh issue edit <N> --repo <owner>/<repo> --milestone "<title>"
# per-issue appetite label (create the label once if missing — these are §29 system labels)
env -u GITHUB_TOKEN gh label list --repo <owner>/<repo> | grep -q 'appetite/' || \
  for s in S M L; do env -u GITHUB_TOKEN gh label create "appetite/$s" \
    --repo <owner>/<repo> --color BFD4F2 --description "Shape Up appetite ($s sittings)"; done
env -u GITHUB_TOKEN gh issue edit <N> --repo <owner>/<repo> --add-label "appetite/<S|M|L>"
```

For **in** items that don't exist yet, don't bulk-create them here — note them in the
milestone body and let the user `/capture` them (each one still has to clear capture's bar).
Shaping sketches the boundary; it doesn't manufacture the issues.

## Step 5: confirm

```
Shaped: <title>  (milestone #<num>, open, not yet bet)
Appetite: <S|M|L> · App: <app> · in: <k> issues, out: <j> things named
Rabbit hole: <one line — resolved / researching in #N>

Not a bet yet. Run /bet when you want to commit it (1–3 active bets, never four).
```

## Don't

- **Don't place the bet.** Shaping leaves the milestone open with no due date. `/bet` commits.
- **Don't skip the rabbit-hole hunt** — an un-hunted unknown is what makes appetites lie.
- **Don't bulk-create the in-issues** — note them; `/capture` is where each earns its place.
- **Don't force a shape.** "Don't build this" is a real, good outcome of shaping.
- **Don't set a calendar estimate.** Appetite is sittings, declared not measured.
