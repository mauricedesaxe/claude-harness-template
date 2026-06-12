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

**Commercial readiness:** <!-- TODO: yes / no. See PHILOSOPHY §19. Set to "yes" if
this project handles other people's data, runs in production for paying users, or
otherwise has data-leak as an unacceptable failure mode. Setting it to "yes" makes
RBAC, Postgres RLS, audit logging, authorization-matrix tests, and explicit PII
handling required defaults rather than optional. Setting it to "no" leaves those as
optional. Pick deliberately at bootstrap; the choice cascades through the
Authorization and Observability sections below. -->

## Philosophy

This project follows the durable conventions in [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md)
— that file is the **why** behind the rules below, and the canonical source when this
file is silent or ambiguous. Specific sections referenced inline: §1 Earn its keep,
§2 Languages, §3 Single-instance default, §4 Modular monolith, §5 Postgres only,
§6 Managed platforms, §7 No serverless / no edge, §8 Web architecture matrix,
§9 Cloudflare, §10 End-to-end type safety, §11 API integration primitives,
§12 Observability, §13 Outsource the non-core, §14 Code-level discipline,
§15 Database discipline, §16 Value-type discipline, §17 Feature flags,
§18 Testing philosophy, §19 Commercial readiness & authorization,
§20 Frontend defaults & local-first, §21 Documentation discipline,
§22 Background jobs, §23 File and blob storage, §24 CI/CD discipline,
§25 Realtime — polling first, §26 Avoid double state, §27 AI/LLM integration,
§28 Version control (jj, colocated).

Where this file overrides PHILOSOPHY.md, the override must name a specific project
reason that clears §1's earn-its-keep bar.

## Codex

`AGENTS.md` is the Codex bridge for this repo. Keep durable project rules here in
`CLAUDE.md`; `AGENTS.md` should stay thin and point Codex back to this file,
`docs/PHILOSOPHY.md`, and the `.claude/skills/` workflows.

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
| `work` | Picking up a GitHub issue — jj workspace off latest main → rough plan → adversarial plan review → user approval → implement → `/review` → triage → `/ship`. The default end-to-end workflow. Supports `auto` (see *Autonomous mode* below). |
| `research` | Exploring an issue's open questions **before** committing to an approach — deep open-web + codebase research, live probes/spikes, a cited verdict in `docs/research/`. The counterpart to `work`: it **never closes the issue** and writes only research-grade code (`scripts/`, never production). Supports `auto`. |
| `commit` | A logical chunk of work is done — record it as atomic conventional commits (as you go, not all at once). |
| `review` | Before commit/push/merge — runs the reviewer agents against the diff and reports in chat. Never posts to GitHub. |
| `capture` | An idea, feature, or bug surfaces mid-flow — file it as a GitHub issue, but **only if it clears the felt-product-value bar**. |
| `ship` | Land work on `main` end-to-end — branch/commit/push/PR/CI-wait/rebase-merge, running only the missing steps. |
| `setup` | A fresh clone — install deps, bring up the stack, set keys, verify build + tests. |
| `neobrutalist-pop` | Building or styling any UI — the neo-brutalist look (thick borders, hard shadows, candy accents). |

**Autonomous mode (`auto`).** `work` and `research` each take an optional `auto` opt-in (the
keyword — `/work 12 auto` — or clear "let it rip" / "review at the end" intent) that collapses
the mid-flow user gates into self-decisions and keeps a **single review gate at the very end**,
right before the outward step: the merge for `work`, the merge + issue comment for `research`.
The reviewer agents still run and genuine blockers still stop. No opt-in → the normal gated
flow; borderline wording → ask once. See each skill's *Autonomous mode* section.

The reviewer **agents** in `.claude/agents/` are run *by* skills, not invoked directly:

- **At plan time** (run by `work`): `plan-reviewer` against the plan text, before
  any code exists.
- **At diff time** (run by `review`): `code-reviewer`, `test-reviewer`,
  `data-reviewer` always; `security-reviewer` conditionally, only when this file
  declares `Commercial readiness: yes` above.
<!-- TODO: , and any project-specific reviewers like `payments-reviewer` or
`geo-scoring-reviewer` — list them here and note which skill runs them. -->

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

### CI/CD (PHILOSOPHY §24)

- **Green CI is non-negotiable** — with one partial carve-out for non-deterministic
  evals on AI-integrated projects (see §27 + the AI integration section below).
- **CI runs on every PR**: lint, type-check, deterministic tests, commit-msg
  hook re-enforced server-side.
- **Preview deploys per PR, full-stack** where the platform supports it (Railway
  and Render do): frontend + API + ephemeral database. Goal: the reviewer
  clicks a link and tries the actual feature without checking out the branch.
- **Migrations run in CI** against an ephemeral Postgres before merge, against
  production on deploy.
- **Deploy on every merge to `main`.** Trunk-based per §17. Multiple deploys
  per day is the normal cadence.

<!-- TODO: this project's specific deploy target (e.g. "Railway, single web service +
Postgres add-on"), CI workflow file path, preview-deploy setup notes, and any
project-specific deployment quirks (env-var setup, build command, healthcheck
path). -->

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

## Frontend defaults

For app-shaped products (skip this whole section when the surface is a static blog
or a single-form landing page — per PHILOSOPHY §20, simplicity is tier-1):

- **Server state:** TanStack Query.
- **Local UI state:** Zustand for app-wide; React `useState` / `useReducer` for
  component-scoped.
- **Styling:** Tailwind + the `neobrutalist-pop` skill.
- **Forms:** TanStack Form.
- **Component states:** Storybook — every non-trivial component has stories
  (see Testing below).

**Local-first feel** is the product target — interactions under the Doherty
threshold (~400 ms) so the UI feels alive:

- Every primary action has a keyboard shortcut, shown in the UI (`.brut-kbd` from
  the `neobrutalist-pop` skill).
- Optimistic updates; the server reconciles in the background. Failures surface
  as a toast with retry/undo, not a blocking dialog.
- No spinners for local actions — only genuine network waits.
- View state (filters, search, open modal) lives in the URL.

<!-- TODO: this project's specific frontend stack pinned with versions, where the
TanStack Query client / Zustand stores / form definitions live, and the keyboard
shortcut map. -->

## Hard rules

- **Earn its keep.** Any architectural complexity beyond the §3 / §5 / §6 / §7
  defaults must clear PHILOSOPHY §1's bar before it lands.
- **Outsource the non-core; own the data** (PHILOSOPHY §13). When the problem
  is not the project's core competency, pay for a managed solution. When the
  outsourced solution offers both a managed SaaS (vendor holds your data) and a
  library you run on your own backend (data stays in your own Postgres), prefer
  the library — see §13's "own the data" sub-rule. Canonical example: **BetterAuth**
  (library, user records in your DB) over hosted-identity SaaS (Clerk, Auth0,
  Descope, etc.). Building from scratch or self-hosting earns its keep only on a
  current, felt cost or reliability problem with the paid path. Applies to
  hosting, CDN, observability, auth, email, managed Postgres (Railway / DO,
  *not* Postgres-plus-platform products), etc.
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
- **Observability from day one** (PHILOSOPHY §12). Structured logs **and**
  distributed traces ship with the first deploy. Errors are **never sampled out**.
  Successful traces default to 100% sampling at low scale; aggressive sampling
  earns its keep against a real ingest-cost problem and stays tail-based (keep all
  errors and slow traces).
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
- **Branded types wherever possible** (PHILOSOPHY §14 + §16). A `string` that means
  a user ID, a `number` that means Unix seconds, a `bigint` that means cents — brand
  them at the type level so the compiler catches "passed a `BookingId` where
  `UserId` was expected" and "compared seconds to milliseconds." Nearly free,
  *infinitely* useful — default to using them.
- **Database stores data; app owns the rules** (PHILOSOPHY §15). No business logic
  in stored procedures, triggers, or non-trivial `CHECK` constraints. Migrations
  reversible by default; invasive changes follow expand → backfill → contract.
- **Feature flags live in our Postgres** (PHILOSOPHY §17). No third-party flag
  SaaS. Trunk-based: half-shipped features hide behind a flag that defaults to
  off; flag has a removal target when added.
- **Background jobs are idempotent** (PHILOSOPHY §22). Hard line. Every job
  re-runs safely; retries are inevitable. Postgres-backed queue (Graphile
  Worker by default), workers on the same machine as the web tier, cron lives
  in code.
- **Avoid double state** (PHILOSOPHY §26). One source of truth per piece of
  state. Caches, dedicated search indexes, read replicas, materialized views
  encoding domain logic — each duplicate has to earn its keep on a named,
  current problem. Strong consistency over availability in the CAP trade.
- **Track every metered API call in Postgres** (PHILOSOPHY §27). Hard line for
  any project shipping AI features; extends to any per-request metered API
  (SMS, certain Maps APIs, transaction processors). Per user, per request, per
  model, with token counts + cost estimate + latency. Without it, you find out
  from the provider's billing page weeks late.
- **End-to-end type safety** (PHILOSOPHY §10). Every network response parses through
  a schema at the boundary. Frontend ↔ backend boundaries are typed via tRPC,
  OpenAPI codegen, or a framework's native loader/action typing — never an untyped
  fetch wrapper.
- **Test behaviour; climb the fidelity ladder** (PHILOSOPHY §18). Bugs live at the
  seams — prefer the highest-fidelity test that stays deterministic. Recorded
  fixtures over invented stubs. Unit tests are a tool, not the load-bearing layer.
- **Tests must always run.** No `skip`, no conditional skipping. A test that needs a
  key fails loudly without it.
- **Comments and commits say *why*, not *what*** (PHILOSOPHY §21). The code says
  what; you say why. Default to no comments; add one when a non-obvious invariant,
  external-bug workaround, or surprising choice lives at that spot. Commit bodies
  same rule — skip the body when the subject is enough.
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

## Database discipline

Per PHILOSOPHY §15: data and indexes live in the DB; business rules live in the
application layer. Avoid stored procedures, triggers, non-trivial `CHECK`
constraints, and materialized views that encode domain logic. A materialized view
*as a cache of an aggregate the app already computes* is fine — see Caching below.

**Migrations** are reversible by default — each migration ships a working `down()`
unless deliberately marked irreversible with a written reason. Invasive changes
(renames, type changes, column drops on populated rows) follow the
**expand → backfill → contract** pattern from PHILOSOPHY §15.

**Value types at the boundary** (PHILOSOPHY §16):

- Dates: `timestamptz` in Postgres, ISO-8601 with UTC offset on the wire. Avoid
  Unix numeric timestamps; if unavoidable, brand them.
- Money: where math matters, `numeric(p, s)` in Postgres + `bigint`/`decimal.js`
  in app code. Brand money types. Never floating-point.
- Durations: branded types with explicit units.

<!-- TODO: this project's migrations tool (drizzle-kit, prisma migrate, sqlx, alembic,
etc.), the schema entry-point file, and any project-specific value-type rules
(e.g. "all money fields are `cents: bigint`", "all timestamps are UTC `timestamptz`"). -->

## Caching

<!-- TODO: cache schema, TTL / freshness field, repository module path. Per
PHILOSOPHY §5, prefer Postgres (a `*_cache` table, materialized view as a pure
aggregate cache, or pre-computed rollup) over Redis. -->

## Feature flags

Per PHILOSOPHY §17: feature flags live in **this project's Postgres**, not in a
third-party flag SaaS. Trunk-based: half-shipped features hide behind a flag that
defaults to off; the unfinished code still ships to production, gated; flag has a
named removal target.

<!-- TODO: this project's flag table location, the reader API, and the convention
for flag naming. Pattern:

- Table: `feature_flags(name TEXT PRIMARY KEY, value JSONB NOT NULL, removed_after DATE)`
- Reader: `flags.evaluate(name, { userId, ... }) -> Result<FlagValue, FlagError>`
- Naming: `<area>.<feature>` (e.g. `scoring.fast_food_additive`)
-->

## Background jobs

Per PHILOSOPHY §22: lengthy or flaky work runs in the background. **Graphile Worker**
on the project's Postgres is the default; workers run on the same machine as the
web tier; cron lives in code. **Every job is idempotent.**

The ideal test is end-to-end through the seam: user triggers the action → job
enqueued → worker picks it up → final state asserted (per §18 fidelity ladder).
Fall back to two narrower tests (action enqueues the right job; worker produces
the right outcome) when E2E is genuinely hard.

<!-- TODO: this project's worker package, the job registry, the cron schedule
declarations, and the per-job idempotency strategy. Pattern:

- Worker entry: `server/workers/index.ts` (runs alongside the web tier)
- Job registry: `server/workers/jobs/<job-name>.ts` — each export defines `{ run,
  identifier, maxAttempts, backoff }`.
- Cron: `server/workers/cron.ts` — declarations in code.
- Idempotency: each job's `run` is keyed by a stable identifier (the target row's
  ID); the work checks current state and applies changes only if not already done.
-->

## File and blob storage

Per PHILOSOPHY §23: object storage is **Cloudflare R2**; metadata and paths live in
Postgres; uploads go **directly from the browser to R2 via a pre-signed URL** —
not through the server. Image processing and virus scanning run in §22 background
jobs once the upload completes.

<!-- TODO: this project's R2 bucket names, the pre-signed URL flow, the `media`
table schema, and any post-processing pipeline. Pattern:

- Bucket: `<project>-uploads` (private, R2 access keys in env config per §10)
- Pre-signed flow: `POST /api/uploads/sign` returns a PUT URL with TTL;
  client PUTs to R2; `POST /api/uploads/complete` marks the metadata row done.
- Metadata: `media(id, r2_key, content_type, size_bytes, owner_id, status,
  scanned_at, created_at)`.
- Post-processing: a `process-upload` job that runs sharp for image variants
  and ClamAV (or vendor) for virus scanning. Status transitions: `pending` →
  `scanned` → `processed` → `public`.
-->

## Authorization

Per PHILOSOPHY §19: defaults are gated by the **Commercial readiness** declaration
at the top of this file.

**App-layer authorization is required for every project.** Even a single user has
a principal; even one resource that isn't fully public needs a permission check.

For **commercial-ready projects**:

- **RBAC** at the app layer is the default model.
- **Postgres Row-Level Security** is the second policy layer — it catches the
  bugs the app misses (a forgotten `WHERE tenant_id = ?` becomes zero rows, not a
  cross-tenant leak).
- **Audit logging** on every authorization decision and data mutation.
- **Authorization tests** cover the role × resource matrix explicitly.
- **Tenant isolation** is enforced and tested at both app and DB layer.

For **non-commercial projects**: app-layer authorization required; the rest are
optional.

<!-- TODO: this project's auth library (BetterAuth recommended per PHILOSOPHY §13),
the role model, where RLS policies live (if commercial-ready), and the audit-log
schema. -->

## Observability

Per PHILOSOPHY §12 + §13: structured logs and distributed traces from day one;
errors never sampled; default tooling is **Sentry** + **BetterStack**; self-hosted
Grafana stack rejected unless §13 has been cleared. Cross-service tracing uses the
W3C `traceparent` standard via OpenTelemetry.

What gets logged on every external upstream call: latency, status, retry count,
circuit-breaker state, rate-limiter wait. Cache decisions log hit/miss/write with
the key. Domain-meaningful events get their own log line.

<!-- TODO: this project's specific observability setup:
- Sentry DSN env var, project, error filters
- BetterStack source tokens for logs / traces
- OpenTelemetry SDK setup (where the tracer is initialized; which exporter)
- The structured-log shape (top-level fields you always include: requestId, userId,
  component, traceId)
- Any project-specific tail-based sampling rules
-->

## AI / LLM integration

<!-- Delete this whole section if the project does not embed any LLM / AI features. -->

Per PHILOSOPHY §27. The five anchors:

- **Evals are load-bearing.** Fixtures + accuracy thresholds, not pass/fail.
  Evals run on every PR; not blocking in the inception phase, promoted to
  blocking with a regression threshold once stable. This is the carve-out in
  §24's "green CI is non-negotiable" rule.
- **Eval improvement is a system** (manual labelling or self-healing) feeding
  back into the suite, which feeds back into prompt / RAG / model improvements.
- **Provider default: Anthropic + OpenAI via OpenRouter.** Self-hosted models
  earn their keep only on regulatory / data-protection / extreme-cost reasons.
- **Cost discipline is mandatory:** every metered call is logged to the
  `api_calls` table (or equivalent), per user / request / model / time window.
  See the Hard rule above.
- **Provider fallback:** default is "if the provider is down, the feature is
  down." Ordered fallback chains earn their keep only when the product is
  commercial-ready and contractually must stay available.

<!-- TODO: this project's AI providers + models, the OpenRouter setup, the eval
suite location and thresholds, the cost-tracking table, the prompt
storage strategy (code vs data), and the fallback chain (if any). Pattern:

- Providers: Anthropic Claude 4.x via OpenRouter, with model alias rules.
- Cost-tracking table: `api_calls(...)` — see §27 schema. Aggregations live
  in materialized views (per §5 + §26 — caches of aggregates, not the data).
- Eval suite: `evals/<feature>/{fixtures.json, run.ts, scorer.ts}` with a
  per-feature accuracy threshold. CI runs all evals on every PR.
- Eval improvement: manual labelling via `evals/labelling/` (a worker reviews
  flagged outputs); promotion via PR that adds the fixture.
- Prompts: code (`server/ai/prompts/<feature>.ts`) for stable prompts; a
  `prompts` table for prompts that iterate per-customer.
- Fallback: declared in `server/ai/router.ts` as an ordered list of providers
  with breaker integration.
-->

## Testing

Per PHILOSOPHY §18: **test behaviour, climb the fidelity ladder.** Most production
bugs live at the seams; a test that crosses a seam and stays deterministic is
worth ten unit tests of the components in isolation. Unit tests have a place;
they are not the load-bearing layer.

The fidelity ladder (prefer the higher rung wherever determinism survives):

1. **E2E / pipeline** against a real or recorded external surface.
2. **Integration** — two or more real modules talking, mocking only true external
   boundaries.
3. **Unit** — one pure function, no collaborators (genuinely localized behaviour
   only: domain math, parser shape, decay curve).

<!-- TODO: name the test runners and lanes. Pattern:
Vitest for unit, Playwright for e2e. The lanes split into `__tests__/` (deterministic,
code correctness), `__integration__/` (live, keyed, pipeline drift), and any others. -->

- **The domain core is tested with deterministic fixtures.** Because it's pure, feed
  it known inputs and assert exact outputs. No network in domain tests. Cover the
  boundaries (curve inflection points, caps at exactly the cap and at cap+1).
- **Integration boundaries are tested with recorded fixtures**, not live calls —
  capture a real upstream response once, parse it through the schema in tests.
- **Test names are third-person verbs of observable behaviour.** `test("scores a
  5-minute grocery at full credit")`, `describe("decay")`. Behaviour, not
  implementation.
- **All tests always run.** No `.skip`, no `.only`, no env-guarded skipping.
- **Drive `Result` to its `err` branch.** A `Result`-returning function whose
  tests only ever assert `isOk()` isn't tested.
- **New behaviour ships with tests in the same commit.** A new mapping, a curve
  change, a new integration parser — all land with coverage, including the failure
  branch (the `unavailable` path).
- **Non-trivial UI components ship with Storybook stories** (PHILOSOPHY §18) —
  at minimum the default, loading, empty, and error/`unavailable` states; empty
  and unavailable are *separate* stories (the "two zeros"). Light interactions
  in a story are fine; asserting a user *flow* is E2E's job. Stories pin how
  the UI looks in a given state and double as a browsable catalog of every
  component state.

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

## Version control (jj, colocated)

The working copy is **Jujutsu (jj)**, colocated with git (PHILOSOPHY §28). git stays
underneath only as the remote/interop layer (GitHub, `origin`, shared history that
teammates see); jj drives every local VC step. The skills (`work`, `commit`, `ship`,
`review`) are jj-native.

- **Workspace-first** (PHILOSOPHY §14 + §28). Each work stream runs in its own **jj
  workspace** under `.jj/ws/<slug>`, created off **freshly fetched trunk** — never by
  moving the shared working copy's `@`, never based on a stale local trunk ref:
  `jj git fetch && mkdir -p .jj/ws && jj workspace add --name <slug> --revision 'trunk()' .jj/ws/<slug>`
  (`jj workspace add` won't create the parent dir).
  The isolation unit is the **workspace, not a git worktree** — a git worktree doesn't
  isolate jj's single `@`, so concurrent agents would collide. Keep `.jj/ws/`
  gitignored. Stay in your workspace for every jj/`gh` operation; after merge,
  `jj workspace forget <slug>` and remove the dir — don't touch the default workspace.
- **Snapshot model, no staging.** jj auto-snapshots the working dir into `@`; there is
  no `git add`. A commit is `jj commit [paths] -m "..."`; fold a fix with
  `jj squash --from/--into`. See `.claude/skills/commit/SKILL.md`.
- **Conventional commits**, atomic, per logical change. **jj does not fire git hooks**,
  so the `commit` skill validates the message shape and runs the project's checks
  itself; CI re-enforces both server-side.
- **Bookmarks are branches.** Name `<type>/<short-slug>`: `feat/<feature>`, `fix/<bug>`,
  `chore/<scope>`. From an issue, include the number: `<type>/<#>-<slug>` (the `ship`
  skill auto-detects this for `Closes #N`). Push with
  `jj bookmark set <branch> -r @- && jj git push --bookmark <branch>` (auto-tracks,
  safe force-with-lease by default).
- **Rebase-merge PRs.** PR via `gh pr create`; merge via
  `gh pr merge <#> --rebase --delete-branch` — linear history, no merge commits. Each
  commit lands on `main` as written, so write commits good enough to live there. Squash
  only for genuinely throwaway "wip" history, with explicit OK. Never `--merge`.
- **No `Co-Authored-By` trailer** (repeated because it's easy to forget): commits
  carry no AI attribution lines.
- Self-review with the `review` skill before merge.

## Style

- **Functional over OOP** (PHILOSOPHY §14). Prefer factory functions returning
  closures over `class`/`this`, and composition over inheritance. Stateful
  primitives are `createX(opts): Result<X, Error>` returning an object of closures
  over private state — no classes. Reserve classes for genuine framework-interface
  compliance and say why.
- **Comments: default to none, write why-not-what** (PHILOSOPHY §21). Add one
  when the non-obvious WHY lives there — a hidden constraint, a workaround for a
  specific external bug, a surprising algorithmic choice. Don't restate the code;
  don't reference the current task or fix.
- **Commit subjects are the *what* in compressed form**; commit bodies, when
  present, explain the *why* and the *how if non-obvious*. Skip the body when the
  subject is enough.
- **Formatting & linting.** <!-- TODO: name the formatter and linter (Biome, Prettier
  + ESLint, etc.). Don't fight the formatter. -->
- **Imports** follow the project's configured path aliases (`~/…`, `@/…`); don't
  introduce a new alias scheme without the matching tsconfig/build-config change.
  Prefer a module's index over reaching into its internals.
- Keep functions short enough to read without scrolling.
