---
name: research
description: Research a GitHub issue's open/contentious questions WITHOUT implementing it — go deep on the open web (official docs, Stack Overflow, upstream issues, methodology sources) and the codebase, write live probes/spikes when needed, and produce a cited, verdict-first feasibility write-up. NEVER closes the issue; any PR references it (`Refs #N`), never closes it; any code is research-grade and lives in `scripts/` + `docs/research/`, never the production paths. Use when the user says "/research", "research #12", "research this issue", "look into #12", "investigate #12", "is X feasible", "explore #12 before we build it", or wants to explore an issue (optionally with specific questions) before committing to an approach. The counterpart to `/work`, which implements and closes.
---

# Research Skill

Deep, honest exploration of an issue **before** committing to an approach — the counterpart
to `work`. `work` takes an issue from picked-up to merged-and-closed. `research` answers the
open questions the implementation would surface, writes the findings down, ships any
reusable probe, and **leaves the issue open**. The deliverable is a *trustworthy verdict*,
not a closed ticket.

The bar is the project's bar: a finding you can't trace to a source or a live probe is worse
than no finding. Every empirical claim cites a real probe (numbers from the actual data
path, not estimates) or a primary source (a URL, not a vibe).

This skill is **jj-native** where the repo uses Jujutsu (a `.jj` dir at the root): every
local version-control step is jj; git stays underneath only as the remote `origin` that
`jj git push` and `gh` talk to. In a plain-git repo, use the git equivalents.

## What makes this NOT `work` (read first — these are hard rules)

- **NEVER close the issue.** Not via `gh issue close`, not via a `Closes #N` / `Fixes #N`
  in a PR or commit. Research informs the issue; it does not complete it. Any PR uses
  **`Refs #N`** only. (This skill exists because "work on #N" wrongly implies "close #N".)
- **NEVER move a board item to Done.** Research is not the implementation finishing. The one
  board move research *may* suggest: when the verdict settles the open question and a
  concrete build shape falls out, propose promoting the item toward "ready to build" (if the
  project's board has such a column). If the verdict is "infeasible / not worth it", leave it
  where it is for the user to close or re-scope. Never jump to Done.
- **Code is research-grade only.** Anything you write lives in `scripts/` (spikes, probes,
  calibration tools) and `docs/research/` (the write-up). **Do not touch the production
  paths** — the directories your application actually ships — except read-only, to understand
  them. If the research concludes a production change is needed, that conclusion is *the
  finding*, recorded in the doc — it is not made here. (A probe may import production modules
  to exercise the real path; it must not modify them.)
- **No plan-approval gate, but a question gate.** `work` gates on a plan. `research` gates on
  the **agenda** — the set of questions you're about to chase — so you go deep on the right
  things. Lighter, earlier, cheaper.

## Flow at a glance

```
0. parse arg: issue [+ question(s)]       5. research deep (web + code + live probes)
1. resolve the issue (don't gate on OPEN) 6. write up docs/research/<N>-<slug>.md
2. frame the research agenda              7. land artifacts (PR uses Refs #N, never Closes)
3. user confirms/extends the agenda       8. post the write-up as an issue comment
4. workspace (only if you'll write code)  9. close the loop WITHOUT closing the issue
```

Step 7 borrows the `commit`/`ship` *mechanics* (atomic commits, rebase-merge, the
`env -u GITHUB_TOKEN` auth quirk) but **overrides** ship's `Closes #N` auto-detection — see
Step 7. Everything else is research-specific.

## Autonomous mode (`auto`)

By default this skill gates **at the start** (Step 3, the agenda) and again when it
publishes. Autonomous mode keeps both as *your* decisions and collapses to a **single
load-bearing gate at the very end — after the research is done and the PR is open, before
you merge it and before you post the issue comment.** Those two are the outward,
hard-to-walk-back steps; opening the PR and running CI is not (it's reversible).

**When it's on — explicit opt-in only.** The `auto` keyword (`/research <N> auto`) or
unambiguous natural language ("let it rip", "yolo", "review at the end"). No opt-in → run
the normal gated flow (which keeps the up-front agenda gate at Step 3). Borderline wording →
ask one line first. Be sure which mode you're in before Step 2.

**What changes:**

- **Step 3 (agenda gate)** → frame the agenda yourself (Step 2) and go straight into the
  deep dive. You still show the agenda you pursued at the end gate; if it was the wrong one,
  that surfaces there and you go deeper before publishing.
- **Steps 5–7 (research → write-up → land)** → do the full research, write
  `docs/research/<N>-<slug>.md`, commit, push, and **open** the PR (`Refs #N`, never
  `Closes`); let CI run. **Do not merge yet.**
- **Steps 8–9 (issue comment + close-the-loop)** → held behind the end gate.

**The end gate** presents the research for discussion and waits:

```
# Research on #<N>: <title> — ready to publish

## Verdict
<TL;DR, 3–5 bullets>

## What the evidence showed
<key findings, the strongest probe results>

## What we cannot do
<honest limits>

## Artifacts
docs/research/<N>-<slug>.md · scripts/<probe>.ts (+ tests)   PR: <link> (CI: <status>)

## Agenda I pursued
<the questions, so you can see if I aimed right>

Merge the PR and post the verdict to the issue?
```

Only on the user's go: merge the PR, post the issue comment (Step 8), and run the
close-the-loop step (Step 9 — which still asks how the issue should stand; that question is
part of this same end conversation, never decided for them).

**What never changes, in any mode:** the adversarial-honesty discipline (Step 5) holds —
auto is not licence to soften a negative verdict. You still **stop mid-research for a
genuine blocker**: a question too vague to frame as falsifiable, a probe that needs a
credential/access decision, or a finding that changes what the issue even is. And research
**never closes the issue**, in any mode.

## Step 0: parse arg

`<arg>` is an issue ref, optionally followed by one or more questions, and optionally the
`auto` keyword. Forms:

- `12`, `#12`, a GitHub issue URL → research the issue; you derive the open questions.
- `12 | <question>` or `12 | <q1> | <q2>` → research the issue **with these questions
  pinned** as must-answers (you may add more you judge necessary).
- A bare question with no issue → allowed, but ask once whether it should be anchored to an
  issue (most research belongs to one). If the user says no, proceed issue-less — Step 8 and
  the board parts then no-op.
- A **milestone / initiative** ref (`/research milestone:5`, `/research the cutover
  initiative`) → research at the **initiative altitude**. This is `research` doing the
  rabbit-hole hunt that `/shape` calls for (PHILOSOPHY §29): the target is the milestone, and
  the agenda is framed around the unknown that could blow the appetite (Step 2). It's the same
  machinery one level up. Differences at this scope: the write-up lands as
  `docs/research/<slug>.md` (no issue number); Step 8 posts the verdict into the **milestone
  description** (and back to `/shape`), since a milestone has no comment thread; the board's
  "promote to Ready to build" move doesn't apply — the output feeds the bet decision instead.
- Empty → ask which issue or milestone (and any specific questions). Don't guess.

A trailing `auto` (or a clear "let it rip" intent) selects **Autonomous mode** (see that
section); strip it from the ref, and settle which mode you're in here, at Step 0.

**Fetch first, before you read or explore anything.** `jj git fetch` so your reading of the
issue and the codebase (Lane B in Step 5) is against the current `main@origin`, not a stale
local checkout. This holds even for **doc-only** research that never creates a workspace —
a feasibility verdict built on a stale tree can be wrong about what the code already does:

```sh
jj git fetch                # ALWAYS first — research the latest main, not a stale checkout
jj st                       # working-copy status: what's in @, which commit it sits on
jj log -r 'trunk()..@'      # any local commits not yet on trunk
```

A research run that writes code creates its own change off freshly-fetched trunk (Step 4),
so uncommitted changes in the current `@` aren't a blocker — but surface what you see; if
they look like they belong to *this* research, ask before continuing.

## Step 1: resolve the issue

```sh
env -u GITHUB_TOKEN gh issue view <#> --json number,title,body,labels,state,url,comments
```

Unlike `work`, **do not gate on `state == OPEN`** — research is legitimate on a closed issue
too (someone may want a question chased after the fact). If it's closed, note that and **do
not reopen it** as part of research.

Read the body *and the existing comments* (prior research may already live there — don't
re-run it). Pull out the **decision the issue is blocked on**: what must be true for the
implementation to be worth building, and what's genuinely uncertain. That uncertainty is
your research target.

## Step 2: frame the research agenda

Turn the issue (+ any pinned questions) into a short list of **concrete, answerable
questions** — the things that, once answered, let someone commit to an approach (or rule it
out). A good research question is falsifiable and names how you'd answer it.

Weak: "look into the caching layer." Strong: "Does the upstream API return a `Last-Modified`
header we can key a cache on, or do we have to hash the body — and what's the hit rate on a
day of real traffic?" — answerable by a live probe against the real endpoint.

For each question, note the **method**: live probe (which upstream / data path), open-web
search (which sources), codebase read, or a small spike. Numbers come from the real path,
not estimates — that's the house style.

Keep it to ~3–7 questions. If the issue only really has one, that's fine — say so.

**At the milestone altitude**, the agenda has one mandatory question above the rest: *what is
the rabbit hole — the single unknown that could blow this initiative's appetite?* (an unproven
integration, a data shape you haven't seen, a ToS/limit you're assuming.) Frame it falsifiably
and answer it for real; the whole point of milestone-scope research is to resolve or de-scope
that unknown *before* `/shape` commits to an appetite. A verdict of "this rabbit hole can't be
closed inside the appetite" is a valid, valuable "don't build it."

## Step 3: user confirms/extends the agenda

Present the agenda as one scannable block and **wait**:

```
# Research agenda for #<N>: <title>

The decision this unblocks: <one line — what committing to an approach needs to be true>

| # | Question | How I'll answer it |
|---|---|---|
| 1 | <falsifiable question> | live probe against the real endpoint |
| 2 | <question> | official API docs + a small spike |
| 3 | <question> | codebase read (the relevant module) |

Pinned by you: <the question(s) from the arg, or "none">.
Anything to add, drop, or reframe before I go deep?
```

This is the gate. The user adds questions, kills dead-ends, or says go. Don't start the deep
dive until they respond — the whole point is to spend the expensive effort on the right
questions. (In **Autonomous mode** this gate is self-decided: frame the agenda and go, and
show it at the end gate instead — see Autonomous mode.)

## Step 4: workspace (only if you'll write code)

If the research is **doc-only** (no probe, no spike), you don't need an isolated workspace —
the write-up commit can be made directly and pushed at Step 7.

If you'll **write code** (a probe, a spike), do it in an isolated **jj workspace** off
freshly-fetched trunk, so iterating can't disturb other work:

```sh
jj git fetch
jj workspace add --name research-<N> ../<repo>-research-<N>   # its own working-copy @
# work there; create the research change with: jj new trunk()
```

When done (after Step 7), retire it: `jj workspace forget research-<N>` and remove the dir.
(In a plain-git repo, use a git worktree instead: `git worktree add … -b research/<N>-slug`.)
The change/branch name carries the issue number so the Step 7 PR can reference it — but as
`Refs`, never `Closes`. Don't share `node_modules` assumptions across workspaces; install
from the frozen lockfile inside it before running tooling.

## Step 5: research deep — the heart of the skill

This is where research earns its name. **Go deep.** Do not settle for the first plausible
answer; chase the contrary case. Three lanes, used as the question needs:

### Lane A — the open web (use it liberally)

`WebSearch` and `WebFetch` are first-class here. For each question:

- **Search broadly, then read primary sources.** Official docs and API references, the
  upstream project's docs for semantics, **Stack Overflow** / GitHub Discussions for the
  gotchas, the upstream's **GitHub issues** for known limitations, methodology papers for the
  "how is this normally measured". Prefer the primary source over a blog's summary of it —
  fetch the actual page and read it.
- **Follow the trail.** A doc cites an endpoint's quota; fetch the quota page. A SO answer
  references a flag; find it in the official docs. Two hops deep beats one shallow skim.
- **Record every load-bearing URL.** A claim sourced from the web carries its link into the
  write-up's Sources. An unsourced web claim is a guess wearing a fact's clothes.

### Lane B — the codebase

Read how the relevant path works today. The issue's framing is sometimes wrong about the
current code — e.g. "the client already returns geometry" when the call site uses an endpoint
that returns none. Catching that is a finding.

### Lane C — live probes / spikes (the strongest evidence)

When the question is "is the data actually there / good enough", **measure it**. Write a
probe in `scripts/` that exercises the real upstream through the existing client/concurrency
stack, and report real numbers. The pattern:

- A **pure summary core** (`scripts/<name>Rows.ts`) — deterministic given its inputs,
  **unit-tested** in `scripts/__tests__/`. New behaviour ships with tests, same as
  production.
- A **thin live runner** (`scripts/<name>-probe.ts`) — loads config, hits the real path,
  prints the table. Fail-loud: an upstream failure prints the typed error and exits non-zero,
  never a summary built on a silent empty fetch.
- It **does not change production** — it's a calibration tool the eventual implementation
  tunes against.

### Adversarial honesty (the load-bearing discipline)

A research conclusion that looks clean deserves a second probe aimed at *breaking* it.
Distinguish **what the data shows** from **what you hoped it would show**. When a metric
sorts the cases the way you want, test the case that should break it — the clean-looking
headline signal that ranks the worst case best is exactly the trap this rule exists to
catch. State limits plainly; a "we cannot do X" section is a feature of a good write-up, not
a failure.

### Parallelism — only when it genuinely helps

**Do not spawn agents by default.** Most research is one mind going deep, sequentially.
Spawn subagents (via the `Agent` tool) **only** when the agenda has **independent, broad**
questions that each warrant their own deep dive and don't share context — then give each
agent **one** question, tell it to research deep (web + code) and return structured findings,
and synthesize the results yourself. Two related questions are one sequential dive, not two
agents. If you're unsure whether parallelism helps, it doesn't — stay inline.

## Step 6: write up `docs/research/<N>-<slug>.md`

The write-up is the deliverable — **verdict first**, evidence second, limits explicit:

```markdown
# Research: <topic> (#<N>)

**Question:** <the decision this unblocks, in one or two sentences>

**Date:** <YYYY-MM-DD>. <How the numbers were obtained — "from live probes, not estimates",
or which sources.>

## TL;DR
- <the verdict, up front — feasible / not / feasible-with-caveats, and the recommended
  direction. A reader who stops here knows what to do.>

## <What the data source / system gives us>
<the raw material: the fields, the endpoint, the quota — with sources.>

## Empirical findings
<tables of real numbers from the probes. Show the discriminating cases.>

## Feasibility verdict
| Approach | Verdict |
|---|---|
| (a) <the recommended one> | **Buildable now / start here** — why. |
| (b) <a gated alternative> | Buildable but <cost/risk>. After (a). |
| (c) <a tempting-but-wrong one> | Disfavoured — <the contrary evidence>. |

## What we cannot do (honest limits)
<the things the data/approach genuinely can't deliver. Be specific.>

## Reusable artifact
<the probe: what it is, how to run it, what it does NOT claim.>

## Sources
<load-bearing URLs from Lane A, if any.>
```

If the research recommends an implementation, **describe its shape** here (the modules it'd
live in, the interfaces, how it stays testable) — but do **not** build it. That's the next
issue's job.

## Step 7: land the artifacts (PR references the issue — NEVER closes it)

Commit atomically via the `commit` skill (`.claude/skills/commit/SKILL.md`) — typically a
`feat(scripts): …` commit for the probe + tests and a `docs(research): …` commit for the
write-up. Pre-commit hooks run; a failure is the bug, fix it, never `--no-verify`.

Then push and open a PR. Reuse the `ship` skill's **mechanics** (the `env -u GITHUB_TOKEN`
auth quirk, `jj git push` / `--rebase --delete-branch`, the CI-wait loop) but **override two
things**:

- **`Refs #N`, never `Closes #N`/`Fixes #N`.** This is the rule that makes research not
  `work`. Ship auto-detects a closing issue from the branch name — here that auto-close is
  **wrong**. Compose the PR body yourself with `Refs #N` at the top. Double-check the
  rendered body before merge: if it says "Closes", fix it.
- **No board move to Done.** Skip it entirely.

```sh
env -u GITHUB_TOKEN gh pr create --base main --title "Research: <topic> (#<N>)" \
  --body "$(cat <<'EOF'
Refs #<N>.

A **research** session — feasibility + sources, no production change. Ships a reusable probe
+ a verdict (`docs/research/<N>-<slug>.md`). The issue stays open for implementation.

## Verdict
<the TL;DR, 3–5 bullets>

## What's here
- `scripts/<probe>.ts` (+ pure core + tests) — calibration tool.
- `docs/research/<N>-<slug>.md` — the write-up.
EOF
)"
```

**Merge only if the artifact is reusable** (a probe/tool worth keeping) and CI's blocking
checks are green. A doc-only research PR is still worth merging so the write-up is
version-controlled. If the user would rather not merge, leave the PR open — the research is
captured either way. (In Autonomous mode, opening the PR happens before the end gate; the
merge waits for it.)

If you used a workspace/worktree, retire it after merge.

## Step 8: post the write-up as an issue comment

The doc lives in the repo, but a copy on the issue makes it referenceable inline. Post the
**verbatim** write-up as a comment:

```sh
env -u GITHUB_TOKEN gh issue comment <N> --body-file docs/research/<N>-<slug>.md
```

Note in your final report that the comment is a point-in-time snapshot — the repo file is
canonical and won't auto-update if the doc changes later.

## Step 9: close the loop — WITHOUT closing the issue

This is the step that distinguishes the skill. The research is done; the issue is **not**.
Leave a short comment that (a) states the research is complete and where it lives, (b)
summarizes the verdict, and (c) names the **remaining work** so the implementation intent
isn't lost:

```
Research complete (see the write-up above / PR #<PR>). Verdict: <one line>.

Remaining to satisfy this issue: <the implementation, in the shape the research recommends>.
Calibrate against `scripts/<probe>.ts`.
```

Then **ask the user** how the issue should stand, and do not decide it for them:

- **Leave #N open** as the implementation tracker (the research is its groundwork), **or**
- **File a focused implementation follow-up** issue (via the `capture` skill / its
  felt-value bar) and let the user decide whether to then close #N as research-only.

Either way the issue does **not** get closed by this skill and the board does **not** move to
Done. If the user explicitly wants #N closed-as-research, that's their call to make — hand it
off, don't pre-empt it.

## Report

Print a summary reflecting only what fired:

```
✓ Researched #<N>: <title>
✓ <K> questions answered (agenda in chat)
✓ Probe: scripts/<probe>.ts (+ tests)        (only if code was written)
✓ Write-up: docs/research/<N>-<slug>.md
✓ PR #<PR> merged (Refs #<N> — issue NOT closed)   (only if a PR was opened/merged)
✓ Write-up posted as a comment on #<N>
○ Issue #<N> left OPEN — implementation still owed: <one line>
```

## Don't

- **Don't** close the issue, ever — not directly, not via `Closes #N`. `Refs #N` only.
- **Don't** move the board item to Done. Research is not the implementation finishing.
- **Don't** touch production paths (the directories your app ships) except read-only. A
  needed production change is a *finding*, not an edit.
- **Don't** spawn agents unless the agenda has genuinely independent, broad questions.
  Default is one mind, sequential, deep.
- **Don't** report a finding you can't trace to a live probe or a cited source. "From the
  data" beats "presumably".
- **Don't** stop at the answer you wanted. Probe the case that should break it.
- **Don't** skip the agenda gate (Step 3) in the normal flow. Going deep on the wrong
  questions is the expensive mistake research is supposed to avoid. (In Autonomous mode the
  agenda is self-decided and shown at the end gate instead — that's the one exception.)
- **Don't** start writing code before the agenda is confirmed (normal flow), and don't write
  production code at all — spikes live in `scripts/`.
