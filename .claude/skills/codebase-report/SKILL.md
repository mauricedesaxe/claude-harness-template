---
name: codebase-report
description: Produce a two-perspective codebase report — (business) what shipped lately and what it achieved, (engineering) where complexity concentrates and what to tackle. Runs a deterministic metrics collector and narrates over it: real-vs-generated LOC by category, week/6-week/quarter evolution, a merged-PR changelog in business terms, an import-coupling graph, and a test-health read. Use when the user says "/codebase-report", "codebase report", "how big is the codebase", "what have we shipped lately", or wants a complexity/health snapshot.
---

# Codebase-report Skill

Answer two questions on demand, for the whole repo or one scoped area:

1. **Business** — what have we shipped lately, and what did it actually achieve?
2. **Engineering** — where does complexity concentrate, and what's worth tackling?

The deterministic heavy lifting (counting lines, walking history, tallying imports) lives in
**`collect-metrics.sh`**, which emits one JSON document. The skill's job is to run it, do the
small amount of judgement the collector deliberately leaves open, and narrate the two
perspectives. The gather-and-narrate runs in a **single spawned subagent** so the caller's
context stays clean — same pattern as `next-task`, `research`, and `review`.

**This skill is read-only.** It never mutates the repo, never commits, never posts to GitHub.
It only reads files and runs `cloc` / `git log` / `gh pr list` (read) / `rg`. The collector
adds no runtime dependency on the project — nothing the app imports.

## Step 0: parse the optional scope arg

`$ARGUMENTS` is an optional scope:

- empty → **whole repo**.
- a top-level dir / package / area name (e.g. a directory under `apps/` or `packages/`, or any
  top-level source dir) → narrate the whole collection but **lead with that area**: its `by_area`
  slice, its PRs, its modules in the import graph. Still surface a cross-area signal if it's
  load-bearing.

If the arg doesn't match any area the collector reports in `by_area`, ask once whether they meant
a specific area or the whole repo.

## Step 1: run the collector

The script lives next to this file. **Run it from a full checkout**, not from inside an isolated
workspace/worktree: an isolated workspace may not materialise committed-but-gitignored files (e.g.
generated bundles), so the `generated` bucket is undercounted there. From the default checkout the
numbers are complete.

```sh
bash .claude/skills/codebase-report/collect-metrics.sh > /tmp/codebase-metrics.json
```

Hard deps: `cloc` and `fd` (the script errors with an install hint if either is missing).
`gh` is optional — without it (or unauthenticated/offline) the report still renders and the
PR changelog section says it was unavailable and why.

If you need an explicit root: `collect-metrics.sh <path>`.

## Step 2: spawn the gather+narrate subagent

Spawn one subagent. Give it: the path to the JSON, the scope from Step 0, and the
instructions below. It returns the finished report as text; relay it to the user verbatim.

The subagent does three things the collector deliberately left to judgement:

1. **Split `source` into core vs app.** The collector tags every handwritten source file
   `bucket: "source"` and leaves the core-vs-app call to you (it's a judgement, not a path
   rule). Read the paths (and sample a file when a directory is ambiguous) and split:
   - **core / business logic** — the stuff that would hurt to lose: the domain engine, the
     algorithms, the state model, the integrations the product is built on. This is the crown
     jewels; call out its size explicitly.
   - **app / glue** — components, routes, UI, wiring around the core.
   Also resolve the handful of files the collector marks `bucket: "unclassified"`.

2. **Narrate the merged PRs in business terms.** `merged_prs` ships titles + numbers, not
   meaning. Group them by what they *achieved* for the product (e.g. "map UX: satellite
   toggle + report-compat guard"), not by commit type. If `available` is false, say the PR
   changelog was unavailable and why — don't silently omit it.

3. **Read a sample of test bodies for the behavior read.** Counts alone can't tell behavior
   tests from mock-theatre (PHILOSOPHY §18). Open 3–5 of `test_health.sample_test_files` and
   judge: do they pin real behaviour (the domain output, the state transition) or just assert
   a mock was called? Say which, with one concrete example.

### Determinism caveats the subagent must respect

- The **category split is a single-run snapshot**, not a cross-run-comparable series. The
  collector's buckets are deterministic, but your core-vs-app judgement isn't pinned across
  runs — so don't present "core grew 4%" by diffing two reports' buckets. The **only**
  cross-run evolution signal is `windows` (git `--numstat`, fully deterministic). Frame
  evolution from `windows`, not from re-bucketing.
- The `windows` numbers include whatever is in the git history, which can include repo-construction
  or bulk-import history (e.g. a repo assembled via `git filter-repo`, a large initial import, or a
  vendored-tree drop). The longest windows can then show large renames/moves rather than net new
  code. If `sixweek` ≈ `quarter`, the history just doesn't reach back a full quarter — say so rather
  than implying a quarter of churn.
- The import graph is rg/regex-level, not AST: relative specifiers are resolved against the
  importer's directory (so fan-in is real), but extensionless/`index` imports are
  approximated. Treat it as "where coupling concentrates," not exact.

## Step 3: the report shape

The subagent returns roughly this (adapt length to scope; lead with the scope arg if given):

```markdown
# Codebase report — <date>  (<scope>)

**TL;DR:** <2–3 sentences: real size, the one thing that shipped, the one complexity to tackle.>

## Size & shape
- Total <N> lines, **<real>** real (excl. <gen> generated: lockfiles, vendored bundles).
- Core/business logic: **<N>** (<where>). App/glue: <N>. Tests: <N>. Docs/harness: <N>.
- Any single bucket/language >5% of real code called out.
- By area: <area-a N · area-b N · …>

## What shipped (business)
<merged-PR changelog grouped by product outcome, per window. What's better for users.>
- This week: <…>
- Last 6 weeks: <…>

## Evolution
<from `windows`: net lines + files changed per window, which area moved. Honest about
bulk-import/construction noise in the git history.>

## Complexity & what to tackle (engineering)
<from import graph + bucket sizes: the fan-in magnets, the high fan-out orchestrators,
the low-hanging cleanup. Concrete: "X has fan-in N and no tests" beats "improve structure".>

## Test health
<tests-per-non-test, test-vs-source LOC, and the behavior-vs-coverage read with one example.>
```

## Don't

- **Don't** run the collector from inside an isolated workspace/worktree if you can avoid it —
  generated files are undercounted there. Use the default checkout.
- **Don't** diff two runs' core-vs-app buckets and call it evolution — that split isn't
  pinned run-to-run. Use `windows` for change-over-time.
- **Don't** present the import graph as exact — it's rg-level, coupling-shaped, approximate.
- **Don't** mutate anything or post to GitHub. This is a read-only report.
- **Don't** reimplement the collector's counting in the agent — run the script, narrate its
  output.
