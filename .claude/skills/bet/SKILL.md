---
name: bet
description: The betting table (PHILOSOPHY §29) — commit a shaped milestone to the active set with a cutoff, after first running the circuit breaker on any expired or over-budget bet. Shows what's already active and what was recently finished before presenting the table, because how full the pipe is and what you just shipped both inform what to take on next. Enforces a hard WIP cap of 1–3 active bets. Use when the user says "/bet", "let's bet", "what should I commit to next", "place a bet", or wants to pick the next initiative to actively work. Separate from /shape (which prepares initiatives) and /next-task (which picks the next issue inside a bet).
---

# Bet (the betting table)

The periodic ritual where you commit to what gets actively worked next, at the **initiative
altitude** (PHILOSOPHY §29). A **bet** = a shaped milestone moved into the active set with a
**cutoff**. This is deliberately separate from `/shape` (you may shape several initiatives,
then bet across them later) and from `/next-task` (which picks the next *issue* inside an
already-active bet).

Bet-state is encoded on native milestone fields, no parallel store:

- **shaped, not bet** = open milestone, **no due date**.
- **active bet** = open milestone **with a due date** (the due date is the cutoff).
- **done** = closed milestone (its body says shipped or dropped).

So "active bets" = open milestones whose `due_on` is set, and the **WIP cap is a count of
them: 1–3, never 4.**

## Step 1: show the lay of the land (always, before any table)

Read and report two things first — they're the context that makes a good bet. The board and
repo coordinates are bound in CLAUDE.md; prefix `gh` with `env -u GITHUB_TOKEN` if the ambient
token lacks `project` scope.

```sh
env -u GITHUB_TOKEN gh api repos/<owner>/<repo>/milestones?state=all --jq \
  '.[] | {number, title, state, due_on, open_issues, closed_issues, description}'
```

- **Active bets** — open milestones with a `due_on`. List each with its cutoff, appetite (from
  the description), and progress (`closed_issues`/`open_issues`). This is the WIP gauge.
- **Recently finished** — the last few **closed** milestones. What you just shipped informs
  what's worth taking on next (and flags whether you're on a roll or running on fumes).

## Step 2: circuit breaker — resolve expired / over-budget bets FIRST

Before placing any new bet, run the breaker on every active bet that has **reached its cutoff**
(`due_on` is in the past) **or** has plainly **burned past its appetite in sittings** (your
read, from how many times you've come back to it — soft context here, not a meter). Fixed
appetite, variable scope: it does **not** auto-extend. For each tripped bet, force one of three
resolutions (PHILOSOPHY §29) — never a silent extension:

- **Ship what's done.** Close the milestone; move its finished issues to Done; `/capture` any
  unfinished slice as a fresh standalone issue if it still clears the bar (don't keep the whole
  milestone open to carry it).
- **Re-shape.** Send it back to `/shape` (Shape Up's step 6) — the appetite was wrong or the
  scope wasn't hammered. Clear the due date (back to shaped-not-bet) and stop; reshape is its
  own act.
- **Drop.** Close the milestone, body `State: dropped — <why>`; detach or close its issues.

The default bias is **the project loses, the appetite holds.** Don't offer "just give it more
time" as a fourth option — that's the failure mode the breaker exists to prevent. Surface the
tripped bets, recommend a resolution for each, and get the user's call before moving on.

## Step 3: enforce the WIP cap

Count active bets *after* Step 2's resolutions.

- **At 3 already** → you cannot place a fourth. Say so plainly and stop: "3 bets active
  (<names>), that's the cap. Resolve one first." Don't quietly allow a fourth.
- **At 0–2** → you have room for `3 − n` new bets. Continue.

## Step 4: the table — shaped milestones, weighed appetite × impact

List the **shaped-but-unbet** milestones (open, no due date). For each, show the felt outcome,
appetite (S/M/L), and a one-line **impact** read (how much the felt outcome moves the product).
The pick is **appetite against impact** — a high-impact M beats a low-impact L; a big L is only
worth a bet when the payoff justifies eating the attention. Don't rank by appetite alone (cheap
≠ worth it) or impact alone (worth it ≠ affordable right now).

If there are no shaped milestones, say so and point at `/shape`. Don't invent a bet out of an
unshaped idea — betting on an un-hunted rabbit hole is exactly what §29 forbids.

## Step 5: place the bet(s)

For each milestone the user commits to, set its **cutoff** (the `due_on`) and flip its state
line. The cutoff is a **backstop revisit date** for the breaker, not a deadline the appetite is
measured against — set it generously (the appetite in sittings is the real budget; the date
just stops a bet from living forever in calendar terms). The user names the date; don't invent
one — and `new Date()` is unavailable to you, so ask for the cutoff rather than computing it.

```sh
# set the cutoff (places the bet) and mark it active
env -u GITHUB_TOKEN gh api repos/<owner>/<repo>/milestones/<num> -X PATCH \
  -f due_on="<YYYY-MM-DDT00:00:00Z>" \
  -f description="$(...prior description with State changed to: betting (cutoff <date>)...)"
```

Optionally set the milestone's issues to **Ready to build** on the board so `/next-task`
surfaces them (refetch field/option IDs first — never hardcode; see `capture`'s board section
for the exact `gh project item-edit` calls).

## Step 6: confirm

```
Active bets after this round (<n>/3):
- <title>  cutoff <date>  appetite <S|M|L>  (<closed>/<total> issues)  [new]
- ...

Resolved by the breaker: <title> → shipped | reshaped | dropped   (if any)

Next: pick the next issue inside a bet with /next-task.
```

## Don't

- **Don't place a 4th bet.** The cap is 1–3. Resolve one first.
- **Don't let a tripped bet auto-extend.** Ship / reshape / drop — never "more time".
- **Don't bet on an unshaped idea.** Send it through `/shape` first.
- **Don't invent the cutoff date** (you can't read the clock anyway) — ask the user.
- **Don't pick the next *issue* here.** That's `/next-task`, one altitude down.
