---
name: viability
description: Assess the COMMERCIAL / IMPACT viability of a product, offering, or feature idea BEFORE betting on it — fan out market-research lenses (demand + willingness-to-pay, competitive landscape + pricing/features, market sizing + unit economics + CAC), adversarially audit the findings, and produce an honest, cited, verdict-first viability report with TAM/SAM/SOM, a competitor table, CAC/LTV, and revenue (or impact) scenarios. Read-only on the web + optional local doc; never builds the thing. Use when the user says "/viability", "is there a market for X", "would anyone pay for X", "size this idea", "TAM/SAM/SOM for X", "should I build/sell this", "market analysis for X", or wants to know if an idea is worth pursuing before shaping/betting it. The market-facing counterpart to /research (which does technical feasibility) and the evidence feeder for /shape and /bet.
---

# Viability (is this idea worth pursuing?)

`/research` answers **"can we build it?"** (technical feasibility). `viability` answers the
other half of the bet: **"should we, and what's the realistic payoff?"** — is there demand,
who pays, how much, against whom, how big, reachable how, and at what acquisition cost. The
deliverable is a *trustworthy go/no-go verdict* with the market evidence under it, not a pitch.

It sits one step **before** `/shape`: shaping names a felt outcome and an appetite; viability
tells you whether the market (or the portfolio payoff) justifies spending that appetite at all.
A viability verdict of **"don't build this"** is a success — it's the cheapest possible way to
kill a bad bet, before any code.

This skill is **read-only on the outside world** and touches no production code. It runs web
research + optional live data probes and writes a report. Any version-control step (saving the
report) borrows `commit`/`ship` mechanics; it never opens PRs against production paths.

## The three goals — set the lens FIRST (it sets what "success" means AND the pass bar)

A viability answer is only meaningful against the goal it's judged for. **The same SOM is a FAIL
for one goal and a WIN for another** — this is the single most common way a viability read goes
wrong (scoring a lifestyle idea against a venture bar, or vice versa). Establish which goal(s) up
front (ask in one line if not obvious). Crucially, **the goals STACK**: a tool the founder builds
for himself can be coffee-money *and* portfolio at once, and that combination clears a bar neither
would alone.

- **A — Real business (replace / meaningfully supplement income).** Success = MRR/ARR big enough
  to matter against a salary. Needs a reachable SOM in the ~tens-of-thousands/mo range, healthy
  **CAC < LTV**, a market big enough to compound. The hardest bar; most ideas fail it and that
  honest "no" is the point.
- **B — Coffee money (low-touch lifestyle supplement).** Success = a SMALL, mostly-passive net
  positive (order **~$500–$3k/mo**) on a product that is genuinely self-serve, low-maintenance,
  and ideally one the founder **would build/run anyway**. Here a SOM that FAILS goal A is a PASS:
  cost-covered + near-zero-marginal-time + additive to a life the founder already lives is a win,
  not a consolation prize. The bar is not "is it big" — it's "is it cost-covered, low-touch, and
  additive." Judge goal-B ideas against THIS bar; do not label a cost-covered $1.5k/mo self-serve
  tool a "no" because it can't replace a salary. (A part-time indie explicitly wants this option
  on the table — see the founder-fit note in the GTM section.)
- **C — Portfolio / impact (freelance credibility, reach, proof-of-skill).** Success is NOT money
  — it's reach, differentiation, a talked-about artifact that wins the next contract. Metrics
  shift to **audience size + reachability**, whether it's *novel enough to be talked about*, what
  it demonstrates, opportunity cost vs a higher-signal project. Size the *attention* market, not
  the wallet. Still run demand + competition (a portfolio piece nobody wants or that's been done
  100× is weak signal), but replace the revenue math with "does this earn attention/credibility,
  worth the appetite." Note **a real commercial surface (a pricing page, actual paying users)
  makes the artifact photograph BETTER** — so B and C reinforce each other, they don't trade off.

State the chosen goal(s) at the top of the report, and say **which bar each conclusion is judged
against**. A single idea often gets three different verdicts (fails A, passes B, passes C) — that
is a valid, useful answer, not a hedge. Report all three when they diverge.

## The bar: every number is sourced or labelled an estimate

Same discipline as `/research`: a market claim you can't trace to a **primary source** (a real
pricing page, a census/industry stat, a raw user thread, a published benchmark) or a **live
probe** is worse than no claim. **Vendor content-marketing blogs inflate pain** — cite them only
as "a company selling into this space says…", never as neutral fact. Every population/conversion
figure is tagged **sourced** (with a URL + year) or **estimate** (with the reasoning). This rule
exists because fabricated numbers are the failure mode this skill is built to catch (see the
audit step).

## Why this skill DOES fan out (unlike `/research`)

`/research` defaults to one mind, sequential. `viability` defaults to **parallel lenses**,
because the questions are genuinely independent broad dives that don't share context: *is there
demand*, *who are the competitors*, and *how big/reachable* are answered by different searches,
sources, and reasoning. Fan out one agent per lens, then **audit**, then synthesize yourself.

Scale the fan-out to the stakes:

- **Quick gut-check** (a small feature, a "is this even worth it") → 1–2 agents, no audit round.
- **A real bet** (a product, a new offering, a milestone-scale initiative) → the full 3 lenses
  + the adversarial audit round + an honest synthesis. This is the default when feeding `/bet`.
- **A big, expensive, or contested bet** → add the counterfactual/reframe lens and a redo pass
  (below). Worth it when the answer changes what you build for months.

## Flow at a glance

```
0. parse arg: the idea (+ goal lens, + auto)     4. AUDIT the findings (adversarial round)
1. frame the idea + the buyer hypothesis         5. (optional) counterfactual + redo pass
2. confirm the framing with the user (gate)      6. synthesize — the honest verdict
3. fan out the research lenses (parallel)         7. write docs/market/<slug>.md + report
```

In **autonomous mode** (`auto`, "let it rip", "on autopilot") the Step-2 gate is self-decided
and shown at the end instead; everything else runs to completion without stopping. The
adversarial-honesty discipline never relaxes — auto is not licence to soften a negative verdict.

## Step 0: parse the arg

`<arg>` is a product / offering / feature idea, optionally a goal lens, optionally `auto`.
Empty → ask for a one-line description of the idea and which goal(s): real-business revenue,
coffee-money supplement, or portfolio (they can stack — see "The three goals").

## Step 1: frame the idea + the buyer hypothesis

Before any research, write down — crisply — **what's being sold, to whom, for what job**:

- **The offering.** One sentence. The concrete thing and its novel element (the wedge).
- **The buyer hypothesis.** Who feels the pain, and is the buyer the same as the user? (The
  buyer ≠ user split changes everything — pricing, adoption, virality.)
- **The job.** What does someone hire this to do, and what do they do today instead (the real
  competitor is often a spreadsheet, a text file, or "nothing").
- **The assumed constraints** — and flag which are *choices* not laws (solo vs team, cheap vs
  premium, standalone vs a wedge into something else). Naming these as choices is what lets the
  audit and the counterfactual lens question them later.

## Step 2: confirm the framing (gate)

Show the framing + the lenses you'll run as one scannable block and wait. This is cheap
insurance against sizing the wrong buyer. (Auto mode: self-decide and show it at the end.)

```
# Viability scan: <idea>
Goal lens: <commercial | portfolio>
Buyer hypothesis: <who, and buyer-vs-user>
The job / today's alternative: <…>
Lenses I'll fan out: demand+WTP · competition+pricing · sizing+unit-economics  (+ counterfactual?)
Anything to reframe before I go deep?
```

## Step 3: fan out the research lenses (the core)

Spawn one agent per lens (via `Agent`), each told to run to completion, go web-heavy, cite
primary sources, label estimate-vs-sourced, be adversarially honest, and return a
verdict-first structured report. Give each the full framing from Step 1 so they're aimed
consistently.

**Before fanning out, verify the free thread-reading APIs actually respond from here** (a
`curl` to HN Algolia and Pullpush), and **paste the free-API cheat-sheet from Lens A into
every demand-touching agent's prompt** — a spawned agent only reads real threads if it's told
how, and web-search HTML is usually consent-walled. If an API is blocked, say so in the report
rather than letting an agent silently conclude "no demand" from a wall.

The three default lenses:

### Lens A — Demand & willingness-to-pay
Who is the buyer (segmented, highest-pain-with-budget called out); is the pain **real and
voiced**; would they pay and how much. **Non-negotiable rule: READ THE ACTUAL USER THREADS
before claiming demand exists or doesn't.** Web-search HTML is often consent-walled — do not
conclude "no one is asking for this" from a blocked search. Use the free unauthenticated APIs:

- **Hacker News (Algolia)** — fully readable, no auth:
  `curl -s "https://hn.algolia.com/api/v1/search?query=<q>&tags=comment&hitsPerPage=100"`
  (use **https**; `tags=story` too; `/api/v1/items/<id>` for a full thread).
- **Reddit JSON** — free, needs a User-Agent header, often still 403s in sandboxes:
  `curl -sH "User-Agent: research/1.0" "https://www.reddit.com/r/<sub>/search.json?q=<q>&restrict_sr=1&limit=100"`
  and append `.json` to any permalink for the comment tree.
- **Pullpush.io** (Pushshift successor) — historical Reddit search incl. comment bodies:
  `curl -s "https://api.pullpush.io/reddit/search/submission/?q=<q>&size=100"` (rate-limits fast;
  capture hits early, back off 20-30s).

Classify every hit: **DIRECT** (someone wants/wishes-for the exact thing), **SOLUTION-HACK**
(someone hand-rolling the workaround — *stronger* evidence than a feature request), or
**ADJACENT** (a related-but-different pain). Do not inflate ADJACENT into DIRECT. Report which
APIs worked vs were blocked, and roughly how many threads were actually read. Distinguish
*capture* demand from *retrieval* demand, and *retrospective* from *prospective* jobs — they
look similar and pay differently.

### Lens B — Competitive landscape + pricing + features
Map the real competitors by category with **current pricing (per-seat / per-plan) and the
specific features** that overlap the wedge — from vendor pricing pages and changelogs, not
listicles. Where does the idea sit pillar-by-pillar (who already covers each piece, how well)?
Is the wedge a **defensible moat** or just an **open gap** anyone can fast-follow (name the
incumbent most able to copy it and how long the lead lasts)? Saturation, and winner-take-most
vs long-tail. Include adjacent categories that could eat the value prop (the real competitor is
often in a different category).

### Lens C — Market sizing + unit economics + CAC
**Commercial lens.** Build TAM → SAM → SOM **bottom-up** from cited population data, and obey
the honest-sizing rules (below). Then the money mechanics:

- **Unit economics.** Variable cost per user (LLM inference, paid map/data APIs, infra), gross
  margin, and whether cost is even the constraint (usually it isn't — demand is). **The
  credit-burn guard:** when the product rides a metered paid upstream (a paid data API, an LLM), a
  free launch that goes viral spends the *founder's* budget with no revenue to offset it — that's
  a real failure mode of "keep it free," and the cleanest fix is a pricing model that passes
  per-use cost through to the buyer (see next bullet). For a metered price, verify **price per use
  > variable cost per use**; a passthrough model makes that structural.
- **CAC vs LTV — always include this, the user wants it.** For a *subscription*, LTV ≈ price ×
  gross-margin × average-lifetime (derive lifetime from a cited retention/churn benchmark). For a
  *one-off / metered* model, LTV is expected lifetime purchases × margin, not a monthly tail; for
  a *lifetime deal*, "LTV" is the single upfront sum **minus the ongoing usage-cost liability**
  (don't model it as pure margin). Healthy is **CAC < ~⅓ LTV** with payback under ~12 months. (For
  a goal-B coffee-money idea reached organically on a build-anyway product, acquisition cost is
  mostly the founder's own content/SEO time — near-free — so the ⅓-LTV gate loosens; say so
  rather than killing a lifestyle idea on a paid-CAC math it was never going to use.) Then sanity-check each channel: for a cheap prosumer
  tool, **paid ads usually can't pencil** (dev/niche CPCs are high, LTV is small) — say so
  explicitly and point to the channels that *do* work (marketplace, organic, word-of-mouth,
  one launch spike).
- **GTM / channels.** The realistic reach mechanism for *this* founder (app-store/marketplace,
  Product Hunt, Show HN, subreddits/communities, SEO, outbound), each with a cited conversion
  and reach ceiling. Reach and paid-conversion are **inversely coupled** (viral spike → tourists
  → low conversion; niche funnel → qualified → high) — never multiply high-reach × high-conversion.
- **Pricing model — do NOT default to subscription.** Match the model to the JOB SHAPE and the
  COST STRUCTURE, then size revenue in that model's native unit:
  - *Subscription (MRR)* fits a **recurring** job (used weekly). Wrong for a one-shot job — nobody
    keeps paying after the job is done (e.g. picking a place to live: you pay, you move, you stop).
  - *Pay-per-use / metered / credits* (CarVertical, cloud-API style) fits a **one-shot or bursty**
    job AND auto-passes real per-use cost (LLM, paid data APIs) through to the buyer — the fix for
    the credit-burn problem above. Size as purchases × price, not MRR.
  - *One-off purchase* fits a genuinely single-use job; no churn, no tail — revenue per transaction.
  - *Lifetime deal* trades all future revenue for cash-now + zero churn; **only safe when marginal
    cost per use ≈ 0.** With a real paid upstream, uncapped lifetime is a COST TRAP (one payment,
    unbounded usage liability) — back it with a credit/usage cap or don't offer it.
  A metered/one-off model can **rescue an idea that fails as a subscription** (wrong job shape),
  and is usually the right answer for a **goal-B coffee-money** target, where "cover costs + a bit
  over" is the whole bar. Name the model explicitly; don't let an agent silently assume MRR.
- **Revenue scenarios** (below) — in the chosen model's unit (MRR *or* purchases/mo *or* one-offs).

### The honest-sizing rules (load-bearing — these are the traps this skill exists to avoid)
1. **Never multiply correlated fractions as if independent.** "Freelance," "remote,"
   "multi-client," "power-user" cluster in the same person. Estimate the *clustered/conditional*
   population directly and say so; don't compound independent-looking percentages.
2. **Name any filter that's really a product-fit assumption** ("keyboard-first power-user") as
   soft — it's a restatement of who the product is for, not a measured demographic, and it
   usually swings the answer 2–3×. Flag it as the least-grounded step.
3. **Build SOM from a reach MECHANISM, not an asserted trier count.** Sum real channels with
   cited ceilings. SOM is almost always ceilinged by *reach*, not by audience size — a solo
   founder reaches tens of thousands over 12–24 months regardless of a millions-large TAM.
4. **Always give a sensitivity band** (pessimistic / base / optimistic) and show what each MRR
   milestone requires in paying users. If the "base" case only survives top-of-distribution
   inputs, it's the optimistic case wearing a base-case label — relabel it.

### Go-to-market motion & the self-serve price band (founder-fit filter)

On the commercial lens, judge whether the idea's likely price/ACV lets it be sold the way the
**founder is actually willing to sell it.** For a solo / part-time founder who wants **zero sales
motion** (no demos, no calls, no white-glove onboarding), the price bands are load-bearing — and
what matters is **total contract value per account, not the per-seat sticker.** Heuristics (mostly
operator lore; the ~$3k rep-affordability line is the well-sourced one — cite them in the report):

- **Self-serve sweet spot: ~$25–$300/mo per account (~$300–$3.6k ACV).** The product must and can
  sell itself; no rep is affordable in this band anyway, so touchless forgoes nothing.
- **Floor ~$10–$20/mo (~$120–$240 ACV):** below it you select for the most price-sensitive,
  highest-support, churniest customers (patio11 "charge more"; Rob Walling / MicroConf). Too-cheap
  is a customer-*quality* trap, not a margin one. If you must go cheaper, gate support to docs.
  (Heuristic, not hard data — the argument is strong, the exact number is a judgment call.)
- **Touchless ceiling ~$3k ACV (~$250–$300/mo):** the sourced line (SaaStr/Lemkin and Tunguz
  independently agree) where an inside rep becomes affordable AND buyers start expecting a demo.
  Product-led machinery can stretch it toward ~$10k ACV, but that's in-app upsell infrastructure,
  not "part-time indie."
- **Dead zone ~$3k–$25k ACV** (the widely-named "valley of death," worst around ~$10k): too dear
  to convert cold self-serve, too cheap to fund real sales. Steer around it unless you're
  deliberately building a low-touch inside-sales motion. (Tunguz dissents that survivors exist at
  every price point — so it's "hardest to *design* a motion for," not "impossible.")
- **The per-seat trap:** a "cheap" $8/seat is a $48k contract at 500 seats — which drags in
  procurement, security review, and an expected human *despite* the low sticker. To stay touchless,
  keep realistic account ACV under ~$3k (or cap self-serve seats) and route anything bigger to an
  unstaffed "contact us" you accept losing.

Janz's mice→whales frame anchors it: mice ~$100/yr, rabbits ~$1k, deer ~$10k, elephants ~$100k,
whales ~$1M ACV — the acquisition motion must match ARPA ("you can't hunt elephants with a
fly-swatter," and can't afford a rep to catch mice). A no-sales solo founder fishes in mice/rabbits,
reaching low-deer only if the product converts itself. **In the verdict, state which motion the
price implies, whether it matches the founder's willing motion, and flag a mismatch as a founder-fit
FAIL even when the market looks fine** — a great market you can't sell the way you're willing to
sell is not your bet. (If the project's owner is a part-time indie who wants self-serve only, treat
that as the default motion constraint unless told otherwise; CLAUDE.md is where that founder-fit
constraint is declared per repo.)

## Step 4: audit the findings (adversarial round — do this for any real bet)

The fan-out will produce confident reports; **audit them before trusting them.** Spawn two
auditors, each reading all lens reports, tasked to attack the research (not the business):

- **Evidence & citation auditor** — independently re-verify the load-bearing numbers from
  primary sources. Catch fabricated/misattributed stats, stale pricing, cherry-picks, and
  vendor-blog-as-fact. (Fabricated or misattributed pain stats — the exact kind of number a
  verdict rests on — are precisely what this auditor exists to catch.)
- **Reasoning & assumptions auditor** — attack the logical leaps, the sizing-math chain
  (correlation, reach-carries-everything), internal contradictions, and especially the **shared
  blind spots**: premises *all* lenses inherited from your framing and none questioned (buyer =
  user? standalone product? the constraint is a choice?). Convergence across lenses spawned from
  one brief is often shared-prior contamination, not independent agreement — name it.

**Require each auditor to hand back a correction, not just a critique.** The reasoning auditor
in particular returns the *single corrected number or model* where it found a flaw — e.g. if
one lens anchors the whole WTP ceiling on a wedge another lens says is fast-followed in weeks,
the correction is a **post-fast-follow declining SOM curve**, not a note saying the two lenses
disagree. Synthesis should inherit a fixed model, not a to-do list.

Fold the audit into the synthesis: strip the fabricated numbers, downgrade the overstretched
claims, adopt the corrected models, and surface the un-questioned premises.

## Step 5: (optional) counterfactual + redo pass

For a big or contested bet, when the audit exposes a load-bearing framing assumption, run the
**strongest reframe the original framing ruled out** (different buyer, buyer≠user B2B version,
a wedge-into-something-else, the mechanism the market actually rewards) as its own lens, and/or
**redo** a compromised lens on the cleaned-up evidence base. This is what turns "you asked the
wrong question" from an audit note into an actual answer.

## Step 6: synthesize — the honest verdict

You (not an agent) write the synthesis. Lead with the go/no-go verdict tied to the **chosen
goal lens**. Say plainly where the evidence is strong vs thin, what the audit changed, and what
the single biggest swing factor is. Resolve genuine disagreements between lenses rather than
averaging them. If the honest answer is "nice tool, no business" or "great portfolio piece, no
revenue," say exactly that — the value of this skill is the number the user can trust, not the
number they hoped for.

## Step 7: write the report + close the loop

Write `docs/market/<slug>.md` (verdict-first), commit it (`docs(market): …` via the `commit`
skill), and summarize in chat. Template:

```markdown
# Viability: <idea>

**Goal lens:** <commercial | portfolio>   **Date:** <YYYY-MM-DD>
**Buyer:** <who, buyer-vs-user>   **The wedge:** <the novel element>

## Verdict
<go / no-go / qualified — 3–5 bullets, EACH tagged with the goal it's judged against (A
real-business / B coffee-money / C portfolio). A single idea often fails A, passes B, passes C —
report that split, don't collapse it. A reader who stops here knows whether to bet, and for which
goal.>
The single biggest swing factor: <…>

## Demand & willingness-to-pay
<segments; is the pain voiced (DIRECT/SOLUTION-HACK/ADJACENT, with real quotes+links); WTP.>

## Competition
| Competitor | Category | Positioning | Pricing (cited) | Covers the wedge? |
|---|---|---|---|---|
<real rows>
Wedge vs moat: <defensible / open gap fast-followed by <incumbent> in <time>>.

## Sizing & economics   (goals A / B — real-business and coffee-money lenses)
- **Which bar** — state whether the verdict below is judged against goal A (replace income) or
  goal B (coffee money); the same SOM can fail A and pass B.
- **TAM / SAM / SOM** — funnel with each number sourced-or-estimated; SOM from a reach mechanism.
- **Pricing model** — subscription / metered-pay-per-use / one-off / lifetime; why it fits the job
  shape and cost structure (and the credit-burn guard if a paid upstream is metered).
- **Unit economics** — variable cost per use, gross margin, price-per-use > cost-per-use if metered.
- **CAC vs LTV** — LTV in the model's unit; healthy CAC < ⅓ LTV; which channels pencil, which
  don't (ads?). For a build-anyway goal-B idea, note CAC ≈ founder's own time.
- **Go-to-market motion** — which motion the price/ACV implies (self-serve / inside-sales /
  enterprise), whether it matches the founder's willing motion (self-serve only, by default), and
  whether the price lands in the sweet spot / floor / dead zone / ceiling. Flag a mismatch.
- **Sensitivity** — pessimistic / base / optimistic, in the model's unit (MRR *or* purchases/mo *or*
  one-offs), and what each revenue milestone requires. For goal B, show the cost-covered break-even.

## (portfolio lens) Attention & signal
<audience reach; is it novel enough to be talked about; what it proves; opportunity cost.>

## The reframe considered   (if Step 5 ran — often the whole story)
<the strongest reframe the original framing ruled out (different buyer / job / mechanism), and
whether it's IN (a better bet than the original) or OUT (and exactly why). Don't let this get
buried under audit citation-nits — if the verdict is "no on the frame, maybe on a reframe,"
this section is the load-bearing one.>

## What the audit changed
<fabricated/stale numbers stripped; overstretched claims downgraded; blind spots surfaced.>

## Confidence & what to verify next
<sourced vs estimated; load-bearing uncertainties; the cheapest real-world test to de-risk it.>

## Sources
<every load-bearing URL.>
```

Then close the loop by pointing at the next altitude tool, and let the user decide:

- Verdict is **go** and it's a multi-issue effort → nudge **`/shape`** (this report is the
  rabbit-hole evidence a shape needs).
- Verdict is **go** and it's one issue → nudge **`/capture`**.
- Verdict is **don't build** → say so; nothing gets shaped. That's a win.
- Verdict is **qualified / pivot** ("not this frame, but the reframe from Step 5 might, and
  here's the cheap test first") → this is the most common real outcome and it is NOT a binary
  go/no-go. Name the reframe, refuse to shape the *original* premise, and gate the pivot behind
  the cheapest real-world test below — don't launder a "no on the frame" into a "go."
- Always name the **cheapest real-world test** (a landing-page smoke test, a 30-day concierge,
  reading the still-unread communities) — market desk-research has a ceiling, and the honest
  report says where that ceiling is.

## Don't

- **Don't** conclude "no demand" from a blocked search. Read the real threads via the free APIs
  first, or say plainly you couldn't and that the claim is therefore unproven.
- **Don't** cite a vendor's content-marketing blog as neutral fact. Flag it as self-interested.
- **Don't** multiply correlated fractions, smuggle a product-fit assumption in as a demographic,
  or assert a SOM without a reach mechanism. These are the sizing traps the audit hunts.
- **Don't** present a "base case" built from top-of-distribution inputs. Relabel it optimistic.
- **Don't** skip CAC/LTV on a commercial verdict — "who could want it" is not "can you afford to
  reach them."
- **Don't** default to a subscription model or size everything in MRR. Pick the model that fits
  the job shape and cost structure (metered / one-off / lifetime / subscription); a one-shot job
  priced as a subscription is a self-inflicted "no."
- **Don't** score a coffee-money (goal B) idea against the venture (goal A) bar. A cost-covered,
  low-touch ~$500–3k/mo self-serve tool is a WIN for a part-time indie, not a failure — say which
  bar you're judging against, and report divergent A/B/C verdicts rather than averaging them.
- **Don't** average away a real disagreement between lenses — resolve it and say why.
- **Don't** soften a negative verdict in autonomous mode. A cheap, honest "no" is the deliverable.
- **Don't** build, shape, or bet here. Viability informs the decision; `/shape` and `/bet` make it.
- **Don't** touch production code — this is research + a doc.
```
