# CLAUDE.md

Guidance for Claude Code (and any other agent) working in this repository.

<!--
  TEMPLATE NOTE
  -------------
  This file is the *skeleton* installed by `claude-harness-template`. The sections
  marked "TODO" are the project-specific body you fill in for *this* repo: what it
  does, its architecture, its load-bearing invariants, its triage labels. The other
  sections (Philosophy, Architecture defaults, Hosting, Hard rules, Type system,
  Testing, Git workflow, Style, Skills) are the universal philosophy — keep them,
  edit only if your project has a written earn-its-keep reason to diverge.

  Delete this comment block once you've filled in the TODOs.
-->

<!-- TODO: one-paragraph description of what this project does and why it exists. -->

The bar for changes is: <!-- TODO: one sentence — the load-bearing quality the project
must preserve. Examples: "the score stays trustworthy and explainable", "the latency
budget stays under N", "the export is reproducible". This is the bar every plan,
diff, and review is judged against. -->

## Philosophy

This project follows the durable conventions in [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md)
— that file is the **why** behind the rules below, and the canonical source when this
file is silent or ambiguous. Specific sections referenced inline: §1 Earn its keep,
§2 Languages, §3 Single-instance default, §4 Modular monolith, §5 Postgres only,
§6 Managed platforms, §7 No serverless / no edge, §8 Web architecture matrix,
§9 Cloudflare, §10 End-to-end type safety, §11 API integration primitives.

Where this file overrides PHILOSOPHY.md, the override must name a specific project
reason that clears §1's earn-its-keep bar.

## Project status

<!-- TODO: optional — if the repo is being bootstrapped, name the current milestone
and what the next one unlocks. Delete this section once the project is past the
bootstrap phase. -->

## Tasks

<!-- TODO: the most common commands in this repo. Examples:

```sh
just dev            # bring up the dev stack
just check          # type-check
just test           # tests
just fmt            # format
```
-->

Pre-commit hooks (if wired): lint, typecheck, test. `commit-msg` enforces Conventional
Commits. If a hook fails, fix the cause — never `--no-verify`.

## Skills

Project skills live in `.claude/skills/<name>/SKILL.md` and are invoked as `/<name>`.
The harness lists them each session; this table is the durable "when to reach for which".

| Skill | Reach for it when |
|---|---|
| `work` | Picking up a GitHub issue — branch → rough plan → adversarial plan review → user approval → implement → `/review` → triage → `/ship`. The default end-to-end workflow. |
| `commit` | A logical chunk of work is done — record it as atomic conventional commits (as you go, not all at once). |
| `review` | Before commit/push/merge — runs the reviewer agents against the diff and reports in chat. Never posts to GitHub. |
| `capture` | An idea, feature, or bug surfaces mid-flow — file it as a GitHub issue, but **only if it clears the felt-product-value bar**. |
| `ship` | Land work on `main` end-to-end — branch/commit/push/PR/CI-wait/rebase-merge, running only the missing steps. |
| `setup` | A fresh clone — install deps, bring up the stack, set keys, verify build + tests. |
| `neobrutalist-pop` | Building or styling any UI — the neo-brutalist look (thick borders, hard shadows, candy accents). |

The reviewer **agents** in `.claude/agents/` are run *by* skills, not invoked directly:
`code-reviewer`, `test-reviewer`<!-- TODO: , and any project-specific reviewers like
`payments-reviewer` --> are run by `review` against a diff; `plan-reviewer` is run by
`work` against a plan, before any code exists.

## Runtime

- **Language: TypeScript** by default (PHILOSOPHY §2). Python / Rust may be used only
  where they specifically earn their keep — name the reason in this section if so.
<!-- TODO: node version, package manager, lockfile policy. Pattern:

- **Node 22 + pnpm** (pinned via `.node-version` / `packageManager`). Never `npm`,
  never a global tool. TypeScript throughout; run scripts with `pnpm exec tsx <file>`.
- **Exact-pinned dependencies.** Every entry in `package.json` is an exact version
  — no `^`, no `~`.
- **7-day supply-chain cooldown.** `.npmrc` sets `minimum-release-age=10080`; do not
  add a dependency version younger than 7 days.
-->

## Architecture defaults

These come from PHILOSOPHY.md and apply to every project unless overridden with a
written earn-its-keep reason:

- **Single deployable** (PHILOSOPHY §3). One application instance + one Postgres
  instance is the starting point; background workers run on the same machine.
  Multi-instance, read replicas, Kafka, Redis, and a load balancer must earn their
  keep. Queues like Graphile Worker / `pg-boss` running on the same Postgres are the
  default for async work.
- **Modular monolith** (PHILOSOPHY §4). Code is organized by **business domain**,
  not by technical layer. A new domain is a new module folder, not a new repo.
- **Data: Postgres only** (PHILOSOPHY §5). SQLite, Kafka, Redis, MongoDB, Timescale /
  Influx / domain-specific DBs are rejected by default. Postgres extensions
  (JSONB, PostGIS, pgvector, partitioning) cover most "specialty" needs. Postgres
  also handles queues and pre-computed aggregates.

## Architecture (this project)

<!-- TODO: target layout — directory map + one-line per module describing what it
owns. Name the external-dependency boundaries here so reviewers can flag bypasses.
The shape should reflect PHILOSOPHY §4 (domain-organized) — e.g. `modules/<domain>/`
or a domain-shaped top-level like `server/{integrations,scoring,...}`. -->

## Hosting & deployment

- **Default platform**: a managed Docker target (Railway, Render, DigitalOcean App
  Platform) — see PHILOSOPHY §6. Ship a Dockerfile, push. No Terraform, no
  Kubernetes, no raw EC2 by default.
- **No serverless, no edge** for the app layer (PHILOSOPHY §7). The app runs as a
  long-running owned server, close to the database. This holds even with SSR
  frameworks (React Router 7, TanStack Start) — deploy to a server, not to a
  serverless adapter.
- **CDN: Cloudflare** (PHILOSOPHY §9) for the frontend / static hosting / DNS /
  TLS. Cloudflare Workers / KV / D1 are excluded by §7 unless a specific exception
  applies.

<!-- TODO: this project's specific deploy target (e.g. "Railway, single web service +
Postgres add-on") and any project-specific deployment notes (env-var setup, build
command, healthcheck path). -->

## Web architecture

<!-- TODO: pick from the matrix in PHILOSOPHY §8 and name the choice + the reason:

- **React SPA + Express backend** (separate deploys) — for highly interactive apps
  with no SEO-critical pages. Type safety via tRPC (preferred) or OpenAPI codegen.
- **React Router 7 / TanStack Start monolith (SSR on owned server)** — for
  SEO-critical, fast-first-paint apps where mixed static + interactive content
  benefits from server-side rendering. Framework-native loader/action type safety.
- **Astro (static or with Node adapter)** — for marketing sites, blogs,
  e-commerce-light, content-heavy pages with sprinkles of interactivity.

The hard constraint is PHILOSOPHY §7 — whichever pattern, the runtime is a
long-running owned server. -->

## Hard rules

- **Earn its keep.** Any architectural complexity beyond the §3 / §5 / §6 / §7
  defaults must clear PHILOSOPHY §1's bar before it lands.
- **Conventional commits.** Enforced by the `commit-msg` hook. Types:
  `feat|fix|refactor|chore|docs|test|style|perf|ci|build|revert`. One logical change
  per commit — **atomic**. Don't fold unrelated cleanup into a feature commit.
- **No `Co-Authored-By` trailer.** Commits carry no AI-attribution lines.
- **Never bypass hooks.** No `--no-verify`. A failing hook is the bug, not the obstacle.
- **Env vars only via the validated config module.** All `process.env` access lives in
  one module (e.g. `server/config.ts`), validated by a schema, frozen at startup. The
  app refuses to start with bad config — that's the point. API keys are config, never
  inline.
- **Structured logging via child loggers.** `log.info({ <fields> }, "<event>")`, not
  interpolated strings. Never log API keys.
- **Fail loud, and distinguish two zeros.** Errors propagate or are handled explicitly;
  silent `catch` is forbidden. Critically: **"genuinely nothing there" (a legitimate
  empty result) is not the same as "the fetch failed".** A failed upstream call
  surfaces in the result as `unavailable` for that slice — never as if the source
  simply had nothing.
- **No `throw` in application code — return a `Result` (neverthrow / equivalent).**
  Every fallible operation returns `Result<T, E>` (or `ResultAsync` for async) and the
  caller handles the outcome — a failure is a value, not a control-flow jump. Model
  the error as a typed discriminated union, never a thrown string. Total functions
  that genuinely cannot fail are the exception. `_unsafeUnwrap`/`_unsafeUnwrapErr`
  are for tests only.
- **End-to-end type safety** (PHILOSOPHY §10). Every network response parses through
  a schema at the boundary. Frontend ↔ backend boundaries are typed via tRPC,
  OpenAPI codegen, or a framework's native loader/action typing — never an untyped
  fetch wrapper.
- **Tests must always run.** No `skip`, no conditional skipping. A test that needs a
  key fails loudly without it.
<!-- TODO: domain-specific hard rules go here — e.g. "Scoring is a pure function",
"Pricing math lives in one module", "All money is integer minor units". -->
- **Modules are domain models.** A file's name describes the subject it owns, not a
  role (`utils.ts`, `helpers.ts`). If the best name is "miscellaneous", the design
  hasn't landed — push back.

## Type system

Lean on compile-time checks; save runtime checks for what types can't see — env, and
network responses.

- **Parse at boundaries.** Every external response goes through a schema (Zod /
  Valibot / Pydantic / serde) in its integration module the moment it arrives. Don't
  `JSON.parse` and cast — let the schema fail loudly so malformed upstream data never
  reaches the domain core.
- **Discriminated unions over boolean flags.** Model a result as a tagged union —
  `{ status: "ok"; value } | { status: "empty" } | { status: "unavailable"; error }`
  — not a bag of booleans. This is the "two zeros" distinction, enforced by the type.
- **`Result` over `throw`.** Fallible functions return `Result<T, E>` / `ResultAsync`
  carrying a typed error union, not thrown exceptions. The error union is itself an
  `as const`/discriminated type.
- **`as const` for domain keys, weights, and error codes** so callers get narrow types.
- **No `as any`, no non-null `!`.** If you reach for them, the model is wrong — fix it.

## External integrations & concurrency primitives

Every integration with an external API stacks five primitives in this order
(outermost → innermost), per PHILOSOPHY §11:

```
inFlight.run(key, () =>
  rateLimiter.run(() =>
    semaphore.run(() =>
      breaker.run(() =>
        withRetry(() => fetch(...), { shouldRetry, baseDelayMs, maxAttempts })))))
```

- Functional implementation: `createX(opts)` factories returning closures, no classes.
- Consumer-supplied policies (caps, thresholds, `shouldRetry` predicates).
- In-memory state by default — matches the single-instance default (§3). Swap for a
  shared backing only after §1 has been cleared.
- Each primitive returns a `Result<T, E>` with a typed error union; nothing throws.

The reference implementation lives in `server/concurrency/` (or the project's
equivalent — see Architecture above). All upstream calls go through it; ad-hoc
`Promise.all` over external calls, hand-rolled `setTimeout` throttles, and inline
retry loops are violations.

<!-- TODO: list each upstream this project consumes:

| Upstream | Owner module | Free-tier limits | User-Agent | Attribution |
|---|---|---|---|---|
| <name> | server/integrations/<name>.ts | <rate / day / month> | <UA string> | <if required> |

-->

## Caching

<!-- TODO: cache schema, TTL / freshness field, repository module path. Per
PHILOSOPHY §5, prefer Postgres (a `*_cache` table, materialized view, or
pre-computed rollup) over Redis. -->

## Testing

<!-- TODO: name the test runners and lanes. Examples:
Vitest for unit, Playwright for e2e. The lanes split into `__tests__/` (deterministic,
code correctness), `__integration__/` (live, keyed, pipeline drift), and any others. -->

- **The domain core is tested with deterministic fixtures.** Because it's pure, feed
  it known inputs and assert exact outputs. No network in domain tests. Cover the
  boundaries (curve inflection points, caps at exactly the cap and at cap+1).
- **Integration boundaries are tested with recorded fixtures**, not live calls —
  capture a real upstream response once, parse it through the schema in tests.
- **Test names are third-person verbs.** `test("scores a 5-minute grocery at full
  credit")`, `describe("decay")`. Behaviour, not implementation.
- **All tests always run.** No `.skip`, no conditional skipping.
- **New behaviour ships with tests in the same commit.** A new mapping, a curve
  change, a new integration parser — all land with coverage, including the failure
  branch (the `unavailable` path).

## Issue triage

Open issues live on the project's [GitHub project board](<!-- TODO: board URL -->) — a
Kanban over GitHub Issues. **Labels describe *what* the issue is** (stable); **the
project's `Status` field describes *where in the flow* it sits** (fluid). There are no
priority labels — ordering within a column is the priority.

**Labels — apply exactly one `area/*` per issue:**

<!-- TODO: list this project's area labels. Pattern:
- `area/<thing>` — short description of what kind of issue belongs here
- `area/tooling` — repo tooling, agents, skills, dev workflow
- `area/infra` — runtime infrastructure: cache, DB, deploy
- `blocked` — applied when the issue is waiting on another issue or milestone
- `bug` — visibly broken behaviour (otherwise omit; "enhancement" is implicit)
-->

Add a new `area/*` when an issue genuinely belongs to none of the above — don't
overload an existing one. The legacy `enhancement` and `chore` labels are GitHub
defaults; don't apply them to new issues.

**Project columns:**

| Status | Means |
|---|---|
| Backlog | Captured, not yet scoped or decided. Default landing column for `capture`. |
| Ready | Scoped, unblocked, actionable. Top of column = next up. `work` pulls from here. |
| In progress | Actively being worked on (usually one item). |
| Blocked | Waiting on another issue or milestone. Also carries the `blocked` label. |
| Done | Closed and shipped. |

<!-- TODO: project number + field/option IDs. The `work` and `capture` skills look
these up here. Get them with:

  gh project list --owner <owner>
  gh project field-list <project#> --owner <owner> --format json

Pattern:
- Project number: `3` (owner: `<your-gh-org-or-user>`)
- Project ID: `PVT_kwHO...`
- Status field ID: `PVTSSF_lAHO...`
- Status options: Backlog `<id>`, Ready `<id>`, In progress `<id>`, Blocked `<id>`, Done `<id>`
-->

**Dependencies** stay in body text (`Depends on #N`, `Refs #M`) — GitHub renders them as
backlinks. When an issue is genuinely waiting on something, apply the `blocked` label
*and* move it to the Blocked column so it's both filterable and visible on the board.

## Git workflow

- **Conventional commits**, atomic, per logical change. See `.claude/skills/commit/SKILL.md`.
- **Branch names** are `<type>/<short-slug>`: `feat/<feature>`, `fix/<bug>`,
  `chore/<scope>`. When started from an issue, include the number:
  `<type>/<#>-<slug>` (the `ship` skill auto-detects this for `Closes #N`).
- **Rebase-merge PRs.** `gh pr merge <#> --rebase --delete-branch` — linear history,
  no merge commits. Each branch commit lands on `main` as written, so write commits
  good enough to live there. Squash only for genuinely throwaway "wip" history, with
  explicit OK. Never `--merge`.
- **No `Co-Authored-By` trailer** (repeated because it's easy to forget): commits
  carry no AI attribution lines.
- Self-review with the `review` skill before merge.

## Style

- **Functional over OOP.** Prefer factory functions returning closures over
  `class`/`this`, and composition over inheritance. Stateful primitives are
  `createX(opts): Result<X, Error>` returning an object of closures over private
  state — no classes. This matches the `Result` / pure-function grain of the domain
  core and the API-integration primitives (PHILOSOPHY §11). Reserve classes for
  genuinely rare cases, and say why.
- **Formatting & linting.** <!-- TODO: name the formatter and linter (Biome, Prettier
  + ESLint, etc.). Don't fight the formatter. -->
- **Imports** follow the project's configured path aliases (`~/…`, `@/…`); don't
  introduce a new alias scheme without the matching tsconfig/build-config change.
  Prefer a module's index over reaching into its internals.
- Keep functions short enough to read without scrolling.
