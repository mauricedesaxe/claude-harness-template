---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.sql"
  - "package.json"
---

# Web / backend domain pack

Web / backend domain pack. Layers on [`../PHILOSOPHY.md`](../PHILOSOPHY.md) (the
spine). Applies when the project is a web or backend product; omit or replace it for
other paradigms (smart contracts, mobile, embedded). § numbers match the spine's
Section index — the six split sections appear here under the same `§N. Title (web)`
heading, carrying the web-specific half of a section whose universal kernel lives in
the spine.

---

## §2. Languages (web)

**Rule.** Default to **TypeScript** for everything. Python and Rust are
secondary tools used only when they earn their keep.

**Why.** TypeScript covers the full stack — frontend, backend, scripts, tooling,
infrastructure adapters — with one toolchain, one type system, and one
package-management discipline.

**Earn-its-keep.**

- **Python** earns its keep for: notebook-driven analysis / exploratory data
  work, the ML ecosystem (PyTorch, scikit-learn, the HuggingFace stack),
  scientific computing where the library you need is Python-native. *Not* for a
  web service where TypeScript would do.
- **Rust** earns its keep when *measurably* memory- or CPU-bound (a parser
  running per-request on a hot path, a sandbox isolating untrusted code, a CLI
  that ships as a single binary). It is rarely actually needed. Reach for it
  only when profiling tells you so, not because it would feel nice.

Within TypeScript: Node, `pnpm` (pinned via `packageManager`), exact dependency
versions, supply-chain cooldown via `.npmrc` `minimum-release-age`. These are
the standing conventions; the template's `CLAUDE.md` skeleton restates them.

---

## §3. Single-instance default

**Rule.** The default architecture is **one application instance + one Postgres
instance, both on the same host or two adjacent hosts**. Workers run on the
same machine as the web tier (same process, or a sibling process). No
load balancer, no read replicas, no Kafka, no Redis, no service mesh, no
multi-region, no auto-scaling group — unless §1 says they've earned it.

**Why.** Single-instance is dramatically simpler to operate, reason about, and
ship to. Most projects reach end-of-life having never needed more. The cases
where this is wrong (you actually need horizontal scaling, geographic
distribution, a true fan-out streaming workload) are conspicuous when they
arrive; you don't have to guess.

**Earn-its-keep.**

- **Background workers and queues**: a queue (BullMQ, Graphile Worker, plain
  Postgres `LISTEN/NOTIFY`) often earns its keep early — workers offload slow
  jobs from the request path and you keep request latency predictable. Default
  to a Postgres-backed queue (§4) on the same DB. *Don't* reach for Kafka unless
  multi-consumer fan-out at scale is the current bottleneck.
- **Read replicas** earn their keep when reads are demonstrably contending with
  writes on the same instance and the workload is read-heavy — not before.
- **Horizontal scaling + a load balancer** earns its keep when one vertically
  scaled instance is saturating CPU at peak. Vertical scaling is cheap and
  boring; exhaust it first.
- **Multi-region** earns its keep when you have a regulatory requirement or
  measured cross-region latency that affects users. Otherwise it's a tax.

---

## §4. Modular monolith (web)

**Why.** Shopify's monolith is the reference: it scaled to enormous size as one
codebase because the modular cut held up. The modular cut also makes a future
extraction (if a module genuinely earns the right to become its own service per
§1) a tractable diff instead of a rewrite.

**Earn-its-keep.** The bar for a separate service is high — see §1.

---

## §5. Data: Postgres only

**Rule.** **Postgres for everything** that needs persistence. The default
rejection list:

- **SQLite** — single-file is tempting but operationalising backup, migration,
  and concurrency is its own tax; Postgres-on-the-same-machine is barely
  harder.
- **Kafka** — only earns its keep at genuine streaming fan-out scale (§3).
- **Redis** — only earns its keep when a real, measured cache-miss-storm
  problem makes Postgres aggregates too slow.
- **MongoDB** and similar document stores — you almost always want
  Postgres + JSONB.
- **Timescale, InfluxDB, ClickHouse** and other domain-specific DBs — only when
  Postgres extensions (TimescaleDB the extension, pg_partman, partitioning)
  genuinely fall over for your workload, *measured*.
- **DynamoDB / Firestore / "managed NoSQL"** — vendor lock-in for a problem
  Postgres already solves.

**Why.** Postgres is the most extensible, most boring, most universally
operable database in the world. JSONB covers document-ish data. `LISTEN/NOTIFY`
covers a lot of pubsub. Materialized views and triggers cover aggregates and
cache invalidation. PostGIS, pgvector, TimescaleDB-the-extension cover most
"specialty" needs. Most workloads never outgrow it. Picking *anything* else by
default trades durable simplicity for early-stage cleverness.

Postgres also covers patterns people reach to other tools for:

- **Queues** — Graphile Worker / `pg-boss` / plain `SELECT FOR UPDATE SKIP
  LOCKED`. Use these before reaching for BullMQ-on-Redis (and Redis at all per
  the rejection list above), let alone Kafka.
- **Aggregate caches** — pre-computed rollup tables refreshed by triggers or
  background jobs. Postgres-as-cache is fine; "we need Redis" usually isn't yet.

**Earn-its-keep.** A deviation needs §1's three boxes ticked: a named,
currently-felt problem, an articulated reason Postgres can't solve it, and an
acknowledged operational cost. "Industry standard for this use case" is not a
reason.

---

## §6. Hosting: managed platforms over IaC and k8s

**Rule.** Default to **Railway, Render, DigitalOcean App Platform**, or
equivalent managed Docker-target platforms. Ship a Dockerfile, push, let the
platform handle build/run/networking/scaling. No Terraform, no Pulumi, no
Kubernetes, no raw EC2 by default.

**Why.** The single biggest time sink in early-stage software is owning
infrastructure you didn't have to own. Managed platforms collapse "build, run,
DNS, TLS, env vars, autoscale, logs" into a Dockerfile and a couple of dashboard
clicks. The operational burden of self-managed infrastructure is real (on-call,
upgrades, security patches, certificate rotation, log shipping, cost
monitoring) and rarely justified until you're at a scale where having a
dedicated platform team is itself a thing you want.

**Earn-its-keep.** Self-managed infrastructure (IaC, k8s, raw cloud VMs) earns
its keep when:

- The cost model of the managed platform genuinely breaks (you're moving
  multi-TB/day and the egress bill becomes load-bearing).
- A compliance requirement names a control the managed platform can't satisfy.
- You're already large enough to have an SRE function and the cost of *not*
  controlling the infrastructure is higher than the cost of owning it.

For everything else, **Dockerfile + push** is the default.

---

## §7. Web layer: no serverless, no edge

**Rule.** The application layer is a **long-running server you own**, deployed
on a managed platform (§6), running close to the database. **Not** serverless
(Lambda, Vercel Functions, Cloudflare Workers as the app layer). **Not** edge
(Cloudflare Workers / Vercel Edge as the app layer). The CDN is a separate
concern (§8).

**Why.** Latency comes from round-trips. In typical workloads, the app↔DB
round-trips dominate the user↔app round-trip — often by an order of magnitude
once you count N+1s, transactions, and aggregations. Pushing the app to the
edge moves it *closer to the user* and *farther from the database*; that
trades the smaller round-trip down for the bigger one up, plus you now pay
cold-starts. The math almost never works for stateful, DB-backed apps.

Serverless adds: cold starts, the connection-pool problem (every cold function
wants its own pool), no in-process caches or shared in-memory state (so §10's
primitives can't be in-process), much harder local development, harder
observability, vendor lock-in to whatever runtime the platform exposes.

**Earn-its-keep.** Serverless or edge earns its keep when:

- The workload is genuinely **stateless and edge-cacheable** (a redirect
  service, a personalization layer that doesn't hit the DB on every request, a
  webhook receiver that fans out to a queue).
- A specific **geographic latency requirement** matters more than the
  app↔DB round-trip, and you can prove it with measurements.

For a normal DB-backed product, the answer is **a single long-running Node /
Python / Rust process on a managed Docker host**. Even when using a framework
that *can* be deployed serverless (React Router 7, TanStack Start), deploy it
to a server (§8's matrix).

---

## §8. Web app architecture

**Rule.** Three architectures are on equal footing **provided §7 is honored**.
Pick by problem domain.

| Pattern | Sweet spot | E2E type-safety story |
|---|---|---|
| **React SPA + Express backend** | Highly interactive app, no SEO-critical pages, want independent deploy / scale of FE and BE | Zod + tRPC (preferred), or OpenAPI-generated client |
| **React Router 7 / TanStack Start monolith (SSR)** | SEO-critical, fast first paint with data, mixed static + interactive — *and* runnable on an owned single server | Framework-native: route loaders/actions are end-to-end typed |
| **Astro (static or with Node adapter)** | Marketing sites, blogs, e-commerce-light, content-heavy pages with sprinkles of interactivity | Lower E2E rigour, fine for static-heavy content |

**Why.** Each has a clean problem it solves. SPA+Express maximizes
separation-of-concerns and independent scaling; SSR maximizes time-to-first-
useful-paint when the data is needed for the first render; Astro maximizes
shipped-HTML-per-line-of-code for content sites.

**The hard constraint** is §7: whichever you pick, the runtime is a long-running
server you own. React Router 7 and TanStack Start *can* be deployed serverless;
you don't. They run on the same kind of managed-Docker host as an Express
backend would. If the only viable deployment for an SSR framework you're
considering is serverless, **SPA + Express wins** — fall back to the
separation-of-concerns pattern.

**Earn-its-keep.** Pattern selection isn't a deviation needing §1's bar — it's
a design choice. What *does* need §1's bar:

- Adding a separate frontend repo when the project doesn't have a reason to
  split (deploy cadence, team boundary).
- Reaching for a heavier meta-framework (Next.js, Nuxt) when one of the three
  above fits.
- Mixing patterns within one product without a written reason for the cut.

---

## §9. CDN: Cloudflare

**Rule.** **Cloudflare** for CDN, DNS, TLS, DDoS, and frontend hosting
(Pages) when the frontend is static or a static-export SPA. Use the free /
near-free tiers as far as they go; they go remarkably far.

**Why.** Cloudflare's free tier covers the vast majority of small-to-medium
project needs (DNS, CDN, TLS termination, basic WAF, page rules). Their paid
tiers stay reasonable. The product is reliable, the dashboard is sane, the
ecosystem is well-documented.

**Earn-its-keep.** Note that this rule is about **CDN / DNS / static frontend
hosting**. Cloudflare also sells Workers (serverless / edge) and KV / D1
(edge-replicated stores); those are excluded by §7's no-serverless-no-edge
rule unless an exception under §7 applies.

A different CDN earns its keep when: a specific geographic gap in Cloudflare's
PoP coverage matters for your users (rare), an org-policy reason names a
specific alternative, or you've measured a concrete deficiency.

---

## §10. End-to-end type safety (web)

Frontend-to-backend boundaries are typed via tRPC, OpenAPI codegen, or a
framework's native loader/action typing.

---

## §12. Observability (web)

**Default tools** (apply §13 / outsource-the-non-core):

- **Sentry** for error tracking and exception reporting. Even with `Result<T,E>` and
  no `throw`s (per Hard rules / §11), Sentry's structured error events with context
  + breadcrumbs are the fastest way to triage failures.
- **BetterStack** (formerly Logtail) for logs and uptime monitoring; supports
  OpenTelemetry trace ingest for distributed tracing as well.
- Either can take the other's role for tracing depending on project flavor; pick one,
  not both, as the primary trace sink.

**Rejected as defaults** (must earn their keep under §13):

- Self-hosted Grafana / Loki / Tempo / Mimir / Prometheus. Earns its keep only at a
  scale where the managed bill is a current, felt budget problem, or a regulatory
  reason names the data plane.
- DataDog by default — the cost curve grows non-linearly and is hostile at the
  scales where managed observability should be cheapest.
- Building any observability primitive in-house — almost never the right call (§13).

---

## §15. Database discipline

**Rule.** The database stores and indexes data; the **application layer owns the
rules**. Business logic in SQL is invisible to your code search, in a different
language, harder to test, harder to evolve, and silently drifts out of sync
with the app-side version. Keep it out.

**Avoid in the database** (these are nudges, not hard prohibitions):

- **Stored procedures and DB functions** that encode business decisions.
- **Triggers** that mutate data based on business rules.
- **`CHECK` constraints** that encode anything beyond simple, stable, invariant
  range/shape checks. `CHECK (price >= 0)` is fine — that's a hard invariant.
  `CHECK (status IN ('draft', 'submitted', 'approved'))` is right at the
  line — defensible if the enum is genuinely stable; pushes back on it if the
  values are likely to evolve.
- **Materialized views** as a place to encode complex domain calculations. (A
  materialized view as a *cache* of an aggregate the app already computes is
  fine — see §5.)

**Migrations: reversible by default, simple by default.** Each migration ships
with a working `down()` (or equivalent) unless deliberately marked irreversible
with a written reason. Roll-back is a real operation, not a hope.

For any change that touches existing rows (rename, type change, column drop),
default to the **expand → backfill → contract** pattern:

1. **Expand**: add the new column / table / shape.
2. **Backfill**: write to both old and new for a release; backfill historical
   data in a job that can be paused / resumed.
3. **Contract**: switch reads to new, then drop the old in a later release.

Each step is a small, reversible migration. The big-bang migration that
renames a live column under traffic is what burns you.

**Earn-its-keep.** A genuinely irreversible migration (dropping a column that
has been unread for years) is fine — document it. A trigger that protects a
hard referential invariant the app cannot enforce is fine. A stored procedure
for a perf-critical path that ran an explicit `EXPLAIN ANALYZE` to justify
itself is fine. The bar is the same as §1: name the problem, articulate why
the app-side version doesn't work, accept the operational cost.

---

## §17. Feature flags

**Rule.** Feature flags are good. Use them for half-shipped features, gradual
rollouts, A/B experiments, and kill switches. **Store them in your own
Postgres**, not in a third-party flag SaaS.

**Why.** Feature flag systems are conceptually small — a flag has a name, a
value (boolean / percentage / variant set), and optionally a targeting rule.
You don't need LaunchDarkly or Statsig for that; a `feature_flags` table plus
a thin reader does the job. Outsourcing them adds:

- A new vendor dependency with its own outages on your hot path.
- A network round-trip per evaluation (or a caching layer to mask it).
- A SaaS bill for a feature you can implement in 200 lines.
- Lock-in: if pricing or product direction shifts, you migrate every flag
  reference in the codebase.

Owning the flags in your Postgres also makes them participate in §13's "own
the data" sub-rule: flag history, exposure events, who-toggled-what all live
where the rest of your data lives.

**The trunk-based pattern.** Feature branch → atomic commits → PR → rebase-merge
to `main` → production deploy. Half-finished features hide behind a flag that
defaults to off; the unfinished code still ships to production, gated. When
ready, flip the flag (gradually if needed).

**Earn-its-keep.** A flag earns its keep when it solves a real problem: a
feature too big to ship atomically, an A/B cut, a fast kill switch for a
regression. A flag is *anti*-keep when it becomes permanent dead code with
both branches still maintained. Set a removal target when you add one, and
follow through.

---

## §19. Commercial readiness and authorization (web)

| Concern | Personal / non-commercial | Commercial-ready |
|---|---|---|
| Postgres Row-Level Security | Optional, often overkill | **Strongly recommended** as the second policy layer |
| Tenant isolation | N/A | Enforced and tested at both app and DB layer |

**Postgres RLS is the second layer.** It runs *underneath* the application and
catches authorization bugs the app misses — a forgotten `WHERE tenant_id = ?`
becomes a silent zero-rows result instead of a cross-tenant leak. RLS is
non-trivial to operate (connection pooling needs care, debugging is harder),
so it earns its keep when the failure mode (data leak) is unacceptable — i.e.
commercial systems.

---

## §20. Frontend defaults and local-first

**Rule.** The frontend feels **native, instant, and keyboard-first**. The target is
interactions under the **Doherty threshold (~400 ms)**, where the user
perceives the system as responsive enough to stay in flow. The defaults below
deliver this for app-shaped products; small enough surfaces (a static blog,
a single-form landing page) skip them.

**Default stack:**

| Concern | Default | Notes |
|---|---|---|
| Server state | **TanStack Query** | Cache, refetch, optimistic update, suspense — the boring middle layer of every app |
| Local UI state | **Zustand**, or React's built-ins | `useState`/`useReducer` for component-scoped; Zustand for app-wide UI state |
| Styling | **Tailwind + `neobrutalist-pop`** | Tailwind for the system, the skill for the look |
| Forms | **TanStack Form** | Type-safe, server-action-friendly, lower ergonomic tax than the alternatives |
| Routing | Whatever §8's chosen architecture brings | React Router for the SPA / SSR monolith, the framework's router for Astro |

**Earn-its-keep — the simplicity exception.** Each of these is overkill for a
small enough surface. An Astro blog with three pages and no interactivity
needs none of them. A landing page with a contact form doesn't need TanStack
Form. A static dashboard with one fetch doesn't need TanStack Query. *Reach
for these tools when the complexity is real; skip them when it isn't.*
Simplicity is the tier-1 value.

**Local-first feel.** The Doherty target shapes how the UI behaves:

- **Keyboard-first.** Every primary action has a shortcut. Show the shortcut
  in the UI (the `.brut-kbd` element from the `neobrutalist-pop` skill, or
  equivalent). `⌘K` focuses search, `Space` toggles the primary action,
  `Esc` cancels, `Enter` confirms, single letters for nav.
- **Optimistic updates.** Local state mutates the moment the user acts; the
  server reconciles in the background. Failures show as a toast with retry /
  undo, not a blocking dialog.
- **No spinners for local actions.** Spinners are for genuine network waits,
  not for "I just clicked a button and you're about to redraw."
- **View state in the URL.** Filters, search, open modal — encode in the URL
  so reload, back / forward, and shared links all work.

This isn't only aesthetic. It's the difference between "this software feels
good to use" and "this software is fine, I guess." Most products fail the
Doherty test by default; the ones that pass feel noticeably alive.

**Earn-its-keep.** A truly content-driven site (documentation, a blog)
doesn't need the full local-first treatment — readers aren't pressing
keyboard shortcuts at it. For anything where the user *does things*, the
Doherty target is the bar.

---

## §22. Background jobs and scheduled work

**Rule.** When a process is **lengthy or flaky**, run it in the background. The user
clicks, the API enqueues a job, the worker processes it, and the user sees the
result via polling (§25) or the next page load. The user never waits on something
slow or watches it fail in their face. **Every job is idempotent** — re-running it
produces the same outcome. This is a hard line.

**Why.** Background jobs are one of the most powerful tools for shipping a
responsive product. The request path stays fast and predictable, retries and
failures stay invisible to the user, and load smooths instead of spiking. The
cost (a queue, workers, idempotency discipline) is moderate; the benefit is large.

**Queue: Postgres-backed, on the same machine.** **Graphile Worker** is the default
(`pg-boss` is a reasonable alternative). Per §5, the queue lives in the same
Postgres as the rest of the data; per §3, workers run on the same host as the
web tier — separate process, same machine.

**Cron lives in code.** Scheduled jobs are declared in the project's source —
not in a third-party scheduler dashboard or a Kubernetes CronJob YAML the app
doesn't own. Graphile Worker's cron support, a `node-cron` declaration next to
the worker, or an equivalent in-code declaration is the pattern.

**Idempotency is a hard line.** Every job is idempotent — re-running it
produces the same outcome. Non-negotiable because retries are inevitable
(network blips, worker crashes mid-job, queue redelivers). A job that can't be
safely re-run is a bug waiting to be reported. Pattern: jobs operate on a target
identifier (an order ID, a user ID), check current state, and apply changes only
if the work hasn't already been done. "Send the welcome email" is idempotent by
recording the send or checking a flag. "Increment a counter" is not idempotent
and is the wrong shape for a job — model it as "set the counter to N" instead.

**Retry policy is case by case.** Different jobs need different retry semantics
— quick exponential backoff for transient network errors, longer backoff for
upstream rate-limits, no retry for poisoned inputs that will fail again. The
retry config is part of the job definition.

**Testing background jobs.** The ideal test is **end-to-end through the seam**:
a fixture user triggers the action via the API, the test asserts the job got
enqueued, the worker picks it up, and the final state is correct. This is
exactly the §18 fidelity-ladder pressure — bugs live at the seams between API,
queue, and worker.

When end-to-end is hard to set up, fall back to two narrower tests:

1. The user action enqueues the right job with the right payload.
2. The worker, given that job, produces the right outcome.

Worker-only tests with mocked inputs are fine for intricate transitions, but
they sit at the *bottom* rung; cover the seam separately or you'll catch
internal bugs while missing the wiring bugs.

**Earn-its-keep.** The synchronous request path earns its keep when (a) the
work is fast and reliable, AND (b) the user genuinely needs the result before
the next action. Otherwise default to async — even for "fast" work that has
flake risk.

---

## §23. File and blob storage

**Rule.** Object storage is **Cloudflare R2** (consistent with §9). User uploads,
generated assets, and large binaries live in R2; metadata and paths live in
Postgres. Uploads go **directly from the browser to R2 via a pre-signed URL** —
never through the application server.

**Why.** Pre-signed direct uploads remove the application server from the
bytes-moving path. The user's bytes go straight to R2 (no server bandwidth, no
server CPU, no memory pressure, no upload-timeout headaches). The server (1)
issues the pre-signed URL after authorization (§19), and (2) records the
metadata once the upload completes. The request path stays tiny, which keeps the
§3 single instance happy.

R2 specifically because: §9 Cloudflare alignment, **no egress fees** (the killer
feature for media-heavy products), S3-compatible API so libraries port without
rewrites, and the pricing is reasonable.

**Patterns:**

- **Paths in DB, bytes in R2.** Postgres stores a `media` (or equivalent) row
  with the R2 key, content type, size, owner, and any domain metadata. The app
  never stores bytes in Postgres — `bytea` columns for user uploads are a §5
  anti-pattern.
- **Pre-signed URL flow:**
  1. Client requests an upload URL from the server.
  2. Server checks authorization (§19), generates the pre-signed `PUT` URL with
     a short TTL, records a pending metadata row.
  3. Client `PUT`s the bytes directly to R2 against the URL.
  4. Client notifies the server (or R2 fires a webhook); server marks the
     metadata row complete and schedules any post-processing via §22.

**Image processing** where the product needs it — `sharp` (Node) is the standard
tool. Run it in a background job per §22 once the upload completes, not on the
request path. Produce the variants you need (thumbnail, preview, optimized
original), store them as separate R2 keys, record the paths in the metadata row.

**Virus scanning** for user-uploaded files. ClamAV in a §22 background job, or a
vendor (Cloudmersive, etc.) per §13. Mark the metadata row as unscanned until
clean; don't expose the file's public URL until scanning passes.

**Public assets** (CSS, JS bundles, static images that ship with the app) —
Cloudflare Pages handles these per §9, not R2. R2 is for *user* and *runtime*
bytes, not deploy artefacts.

**Earn-its-keep.** S3, DigitalOcean Spaces, or Backblaze B2 are reasonable
alternatives only when a named constraint (existing AWS billing relationship,
geographic gap in R2's PoP coverage) blocks R2. Self-hosted MinIO / Garage /
similar earns its keep only against §13's bar.

---

## §24. CI/CD discipline (web)

- **Preview deploys per PR, full-stack.** Frontend, API, **and an ephemeral
  database** where the platform supports it. Railway and Render both do (§6).
  The goal: open a PR, the reviewer clicks a link, the actual feature runs on
  the actual stack — no checkout, no `pnpm install`, no "works on my machine."
  Frontend-only previews are the fallback when full-stack is genuinely hard
  to set up; aim for full-stack — once you have it, you don't go back.
- **Migrations run in CI** against a real ephemeral Postgres before the merge,
  and against production in the deploy step. Migration failure in CI is a
  blocker.

**Earn-its-keep.**

- Full-stack preview deploys are a real setup cost. If the platform doesn't make
  it trivial (Railway and Render do; raw Docker hosts don't), the project's
  earliest milestones can run with frontend-only previews. Plan to upgrade.

---

## §25. Realtime — polling first

**Rule.** **Default to polling** for any "the UI should reflect the latest server
state" need. Reach for **WebSockets, SSE, or webhooks only when polling
genuinely doesn't work** — and "doesn't work" has to mean a named, current,
specific problem.

**Why.** Polling is dramatically simpler than persistent connections or push
channels. A `GET /thing` every 5–30 seconds is one HTTP request to reason about,
one timeout to tune, one cache header to set, one rate limit to respect.
WebSockets and SSE add: connection lifecycle, reconnection logic, message
ordering, back-pressure, an entirely different observability story (per §12),
and a long-lived stateful object that complicates §3's single-instance default
(when a second instance does eventually earn its keep, sticky sessions become a
thing).

Polling is also cache-friendly. A `GET` with `Cache-Control` and `ETag` behind
Cloudflare (§9) can serve most polls without touching the origin. Persistent
connections bypass the CDN entirely.

**When push earns its keep:**

1. **Latency-critical.** The event must reach the user in well under one polling
   interval — collaborative editing, live order book, real-time chat where the
   perceived delay *is* the product. Polling every 100 ms is bad for both sides;
   push is the right tool.
2. **Resource-intensity.** Data changes rarely (an event per hour) but the
   consumer needs to know promptly. Polling every 5 s wastes both ends' compute
   for no event. A push channel is cheaper at steady state.
3. **Server-to-server webhooks** for an external system calling *into* your app
   — the inverse of polling an upstream API. Webhooks let the upstream tell you
   when something happened (with retries + HMAC signing). The right shape when
   you'd otherwise hammer an external API.

**Defaults when push is justified:**

- **SSE** for one-way server → client streams (notifications, live data feeds,
  log tails). Simpler than WebSockets, works over HTTP/2, behind CDNs
  reasonably, native browser support.
- **WebSockets** only when you need bidirectional traffic or sub-100 ms latency
  — collaborative editing, multiplayer, voice signaling.
- **Webhooks** for inbound. Required: HMAC signing, idempotent receivers (§22),
  and a queue between the receiver and the actual work (§22). A webhook handler
  that does the work synchronously is a §22 violation waiting to happen.

**Earn-its-keep.** WebSockets / SSE / inbound webhooks earn their keep on a
named, measured latency or resource problem, not "it would be cooler." The
complexity tax is real and shows up at the worst time.
