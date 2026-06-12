# Philosophy

The durable "why" behind the conventions enforced by `CLAUDE.md`, `AGENTS.md`, and
the `.claude/` skills/agents in any repo bootstrapped from
[`claude-harness-template`](https://github.com/mauricedesaxe/claude-harness-template).

`CLAUDE.md` is the **rules**, dense and enforceable, applied to *this* project.
`AGENTS.md` is the **Codex bridge**, intentionally thin, so Codex follows the same
rules instead of growing a parallel source of truth.
This doc is the **reasoning** — the kind of thing you re-read when an edge case
shows up that the rules don't obviously cover. When `CLAUDE.md` is silent or
ambiguous, defer to the section number here.

The shape: every section has a **rule**, the **why**, and the **earn-its-keep**
clause (when deviation is allowed, and what bar a deviation has to clear).

---

## §1. Earn its keep

**Rule.** The simpler architecture wins by default. Anything more complex — a
second instance, a replica, a queue, a cache layer, a different language, a
different database, an infrastructure-as-code tool, a hosting platform with more
moving parts — has to *earn its keep* before it lands. The bar is the same one
the `capture` skill applies to product features: a **felt, current, specific
problem** that the simpler option doesn't solve. Hypothetical, future, or
aesthetic ("cleaner") reasons don't qualify.

**Why.** Most software is killed by complexity it didn't need. The single-machine
Postgres-backed monolith ships faster, is easier to debug, has fewer moving
parts on-call, and scales further than people expect. The premature reach for
microservices / Kafka / k8s / Redis is the modal failure mode in our reference
class. We treat that reach as a special case requiring justification, not the
default.

**Earn-its-keep.** A deviation qualifies when:

1. The simpler default has a **named, currently-felt problem** (e.g. "reads are
   throttled by writes at p99 250ms today"), not a hypothetical one ("what if we
   spike").
2. The simpler alternative has been **tried or thought through and ruled out**
   for a specific, written reason.
3. The **operational cost** of the addition (deploy complexity, on-call burden,
   debug complexity, new failure modes) is named and accepted.

All three. If you can't write down #1, the deviation hasn't earned anything.

This is the meta-rule. Every other section here is an instance of it.

---

## §2. Languages

**Rule.** Default to **TypeScript** for everything. Python and Rust are
secondary tools used only when they earn their keep. Don't introduce a fourth
language at all without a major justification.

**Why.** TypeScript covers the full stack — frontend, backend, scripts, tooling,
infrastructure adapters — with one toolchain, one type system, and one
package-management discipline. End-to-end type safety (§9) is free when both
ends speak the same language. Splitting languages doubles the surface area of
"how do we lint, test, deploy, lockfile-pin, supply-chain-cooldown this part?"
without buying anything most of the time.

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

## §4. Modular monolith

**Rule.** Inside a single deployable, organize code **by business domain** —
not by technical layer. The folder structure exposes the domains; the
inter-module boundary is the API the rest of the codebase consumes.

**Why.** Layered structures (`controllers/`, `services/`, `repositories/`) hide
the domain and spread one business concept across many folders, so every change
hops files. Domain-shaped structures (`billing/`, `orders/`, `inventory/`) put
each concept in one place. Shopify's monolith is the reference: it scaled to
enormous size as one codebase because the modular cut held up. The modular cut
also makes a future extraction (if a module genuinely earns the right to become
its own service per §1) a tractable diff instead of a rewrite.

**Earn-its-keep.** The bar for a separate service is high — see §1. The default
is: a new domain is a new module folder, not a new repo.

**Examples** (not prescriptions — pick the granularity your project warrants):

```
# Mid-size — explicit subdirectories per module
modules/
  billing/
    routes.ts        # HTTP / RPC handlers for this domain
    domain.ts        # pure functions; the business logic
    db.ts            # repositories (the only place SQL lives for this module)
    integrations.ts  # external upstreams owned by this domain
  orders/
    ...
  inventory/
    ...
```

```
# Smaller — module = single file
modules/
  billing.ts
  orders.ts
  inventory.ts
```

```
# Domain-shaped at the top level even without `modules/`
server/
  integrations/    # external boundaries, one file per upstream
  scoring/         # pure domain core
  routes/          # entry points
database/          # repositories
```

The last is what WalkUp uses (and what `CLAUDE.md` skeleton's architecture TODO
suggests as a starting point). All three are fine; what's *not* fine is a
top-level `services/` + `controllers/` + `repositories/` cut that flattens the
domain.

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

## §10. End-to-end type safety

**Rule.** Every boundary between machines, processes, and modules is **typed
end to end**. Network responses are parsed through a schema (Zod / Valibot /
Pydantic / serde) at the boundary; the parsed type flows through the rest of
the code with no further validation. Frontend-to-backend boundaries are typed
via tRPC, OpenAPI codegen, or a framework's native loader/action typing.

**Why.** Untyped boundaries are the load-bearing source of production bugs.
"It worked locally" usually means "the local data shape happened to match the
type we assumed in code." A schema at the boundary turns those bugs into
compile-time errors and loud parse failures rather than silent
mis-rendering or `undefined is not a function` at 3am.

**Earn-its-keep.** Some boundaries are genuinely freeform (raw text from a
user, content from a third-party HTML scrape) and don't have a schema to parse
against. These are the exception, not the rule, and even then you usually want
a downstream parsing step that extracts the structured part before it
propagates.

This rule does not say "no `unknown`." It says: when you have an `unknown`,
narrow it through a parser before you act on it.

---

## §11. API integration primitives

**Rule.** Every integration with an external API (third-party service, upstream
microservice, anything that can rate-limit, fail, or stampede) uses the same
four primitives, composed:

1. **In-flight request map** (single-flight / request coalescing): if the same
   logical request is already running, attach to the existing promise instead
   of issuing a duplicate. Keyed by the caller.
2. **Rate limiter**: cap the per-window request rate to the upstream so you
   stay inside its free-tier or contractual limits. Caller picks the cap.
3. **Bounded parallelism (semaphore)**: cap the concurrent in-flight requests
   so a burst doesn't dogpile a sick upstream or your own connection pool.
4. **Circuit breaker**: when the upstream has failed N times within a window,
   open the circuit and fail fast for a cooldown before probing again.
5. **Retry with jittered backoff**: handle transient errors. Caller picks the
   `shouldRetry` predicate so the integration decides which error codes are
   transient.

(Yes, that's five. The "four" was the brain dump; in practice the bounded
parallelism / semaphore is the fifth load-bearing piece.)

**Composition order** (outermost → innermost):

```
inFlight.run(key, () =>
  rateLimiter.run(() =>
    semaphore.run(() =>
      breaker.run(() =>
        withRetry(() => fetch(...), { shouldRetry, baseDelayMs, maxAttempts })))))
```

- In-flight is **outermost** so duplicate requests don't even acquire the rate
  limiter token.
- Rate limiter outside semaphore so the rate limit applies to unique
  *requests*, not internal retries.
- Semaphore outside breaker so the breaker's "open" state itself doesn't hold
  semaphore slots.
- Breaker outside retry so a single attempt's failures contribute to the
  breaker, but the breaker's "open" state short-circuits before retry spins.
- Retry innermost, around the actual fetch.

**Implementation rules:**

- **Functional.** No classes / `this`. Each primitive is a `createX(opts)`
  factory returning an object of closures over private state. Matches the
  `Result` / pure-function grain of the rest of the codebase.
- **Consumer decides policy.** Defaults are conservative; every knob is a
  caller-supplied option (`maxAttempts`, `baseDelayMs`, `shouldRetry`,
  `onRetry`, breaker `failureThreshold`, breaker `cooldownMs`, limiter
  `tokensPerWindow`, limiter `windowMs`, semaphore `maxConcurrent`,
  inFlight `keyFn`).
- **In-memory by default.** State lives in the process. This is a deliberate
  choice tied to §3: a single instance is the default, so in-process state
  works. If you ever scale to multiple instances (after §1 earns it), you
  swap the in-memory backing for a shared one — but you don't pay that
  complexity until you have to.
- **Each primitive returns a `Result<T, E>`** with a typed error union (e.g.
  `BreakerOpen`, `RateLimitExceeded`, `RetryExhausted`) — never throws.

**Earn-its-keep.** Skipping a primitive earns its keep only when:

- The upstream genuinely has no rate limit (no rate limiter needed) or you're
  already the rate-limiting party.
- The call is genuinely one-off and a stampede is structurally impossible (no
  in-flight map needed).
- The call is genuinely idempotent and transient errors are visible to the
  user anyway (no retry needed).

These are individual choices. The default is: use all of them, composed in the
order above, and pass conservative options.

**Where the code lives.** This document describes the **contract**, not the
implementation. Each project ships its own implementation in its language of
choice — see the project's `CLAUDE.md` for the actual module(s). The standing
reference TypeScript implementation lives in the WalkUp / job-finder repos as
`server/concurrency/`.

---

## §12. Observability

**Rule.** Every project ships with **structured logs and distributed traces from day
one**. Errors are **never sampled out**. At small scale, the default sampling rate
for successful traces is **100%** (or as close as the ingest budget allows). Metrics
and alerts are secondary tools — useful when there's an SLO to defend or an on-call
rotation receiving alerts, not load-bearing primitives.

**Why.** When something breaks, you can only diagnose with the signal you already
captured. Sampling decisions made before an incident are bets that the failure
you're about to hit will be among the kept samples — and at small scale, that bet
is unnecessary. Keep everything until you have a real ingest-cost problem.

Traces (with spans) are the single most valuable observability tool: they show the
actual execution path through your code, including DB calls, external upstreams,
and timing. That's exactly the surface area where the load-bearing bugs and
latency problems live. A single trace with proper spans usually answers a debugging
question that would take an hour of `git log` and `console.log` to reach.

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

**Distributed tracing.** When the system is more than one process, use the W3C
**Trace Context** standard (`traceparent` / `tracestate` headers) so a single trace
spans every service. Both Sentry and BetterStack consume OpenTelemetry, which uses
the standard. Don't invent your own correlation header.

**What to log** (in addition to the structured-logging Hard rule):

- Every external upstream call: latency, status code, retry count, circuit-breaker
  state, rate-limiter wait time.
- Cache decisions: hit / miss / write, with the cache key.
- Domain-meaningful events: a score computed, a job enqueued, a webhook received.
- Never log API keys; never log full PII without an explicit, documented reason.

**Earn-its-keep.**

- **Aggressive sampling** (5%, 1%, 0.1%) earns its keep when ingest cost is a
  current, felt budget problem. When it does, prefer **tail-based** sampling: keep
  100% of errors and slow traces; sample the successful, fast ones. Never sample
  errors.
- **Metrics dashboards** earn their keep when there's an SLO or capacity-planning
  decision riding on them.
- **Alerts** earn their keep when there's a human (or a rotation) actually receiving
  them. An unactioned alert is noise.

---

## §13. Outsource the non-core

**Rule.** When you have a problem to solve and the problem is **not your core
competency**, default to **paying for an existing solution**. Building it yourself or
self-hosting earns its keep only when (a) the problem IS your core competency, or
(b) the paid solution becomes a current, felt cost problem, or (c) the paid solution
is demonstrably unreliable in a way that's hurting users.

**Why.** The time cost of building, running, and operating a homebrew solution is
almost always greater than the dollar cost of the paid one — *especially* once you
include ongoing maintenance, security patches, upgrade churn, and the on-call
burden of being the operator of last resort. Vendors whose core competency is the
problem you're trying to solve have already paid the cost of fixing the hard edges
you haven't hit yet. Outsourcing buys you their solved problem; building means you
re-solve it on your own time.

This is the **sister rule to §1**. §1 says "the simpler architecture wins by
default." §13 says "the paid tool wins over the built tool by default." Together
they bias the system toward shipping product on top of someone else's solved
problem, not toward becoming a platform team for your own infrastructure.

**Applications across this doc** (these are §13 in action):

- **Hosting (§6)** — managed Docker platforms over IaC and k8s.
- **CDN (§9)** — Cloudflare's CDN over a homebrew edge cache.
- **Observability (§12)** — Sentry + BetterStack over self-hosted Grafana stack.
- **Data (§5)** — **Railway Postgres** or **DigitalOcean Managed Postgres**
  (plain managed Postgres, no abstraction layer above it) over operating your own
  instance. Avoid "Postgres-plus-platform" products (Supabase, etc.) that abstract
  the database away and lock you to their surface — by the "own the data" rule
  below, you want managed *Postgres*, not "a service backed by Postgres".
- **Auth** — **BetterAuth** (open-source library that runs on your own backend; the
  user records live in your own Postgres). Hosted-identity SaaS (Clerk, Auth0,
  Descope, etc.) is a more aggressive form of outsourcing that gives up data
  ownership — see the "own the data" rule below.
- **Email / SMS** — Resend, Postmark, Twilio over running your own MTA. The data
  here is transactional output, not durable identity, so the data-ownership rule
  is less constraining.

**Sub-rule: own the data.**

When the outsourced solution offers both a **managed SaaS** (vendor holds your
data on their infrastructure) and a **library or service you run on your own
infrastructure** (data stays in your own Postgres / your own object store /
your own process), prefer the library version. The running code is a short-term
productivity gain; the data is a long-term asset. Vendor lock-in is much harder
to escape after the data has lived in their system for years — and a vendor
whose incentives, pricing, or product direction shift later can hold the data
hostage in a way they can't hold an open-source library.

This applies most strongly to **durable, identifying, or strategic data**:

- **User identities and accounts** — BetterAuth (data in your DB) wins over
  hosted-identity SaaS by this rule. If you ever migrate auth providers, having
  the user table already on your side of the wall is the difference between
  "swap the library" and "data migration project".
- **Customer records, content, domain state** — these belong in your own DB
  (per §5 Postgres only), not in a CMS-as-a-service or a Firestore-shaped
  vendor lock-in.
- **Anything that's a moat** — proprietary data, scores, recommendations,
  curated content — stays on your side, period.

It applies less to **transactional output and ephemeral context**:

- Sent emails (Resend / Postmark), sent SMS (Twilio), pushed notifications.
- CDN cache contents, edge logs.
- Observability ingest (§12) — though even there, prefer vendors with clean
  export paths so you can leave with the historical data.

When you can't have both ("there is no library version of this problem"), §13's
outer rule still applies: pay for the SaaS. But check first. The library version
often exists and is the better choice on the data-ownership axis.

**Where you do NOT outsource:**

- **The domain core.** If you're building a scoring engine, the scoring engine is
  yours; you don't pay a vendor for "scoring as a service." The product *is* the way
  you do that one thing.
- **Durable user / customer / domain data.** The "own the data" sub-rule above is
  the operational form of this: even when you outsource the *solution*, keep the
  *data* on your side of the wall whenever the library form lets you.
- **Anything that exposes proprietary data or a strategic moat** to a vendor whose
  incentives could turn against you.

**Earn-its-keep for building or self-hosting** a non-core component — the bar is
the same as §1:

1. A current, felt, named problem with the paid solution (cost is biting *now*,
   not "what if it scales"; reliability has caused specific user-visible incidents
   with documented numbers).
2. An articulated reason the simpler (paid) thing genuinely doesn't work for the
   problem — not a hypothetical or aesthetic objection.
3. An accepted operational cost — on-call, upgrades, security, the new failure
   modes you're now responsible for.

"It would be cleaner if we owned this" doesn't qualify. "It would be cheaper at
some future scale" doesn't qualify. "The vendor's API isn't quite ergonomic" doesn't
qualify. Reach for the build path only when the paid path is *currently broken in a
named way* — and document the named problem in the commit that adopts the build.

---

## §14. Code-level discipline

**Rule.** A small set of universal coding habits shape every file in every project.
They are not all hard rules — but together they catch entire classes of bug at
compile time or commit time, when fixing them is cheap.

- **Functional over OOP.** Prefer factory functions returning closures over
  `class` / `this`, and composition over inheritance. Stateful primitives (the
  semaphores, breakers, in-flight maps of §11) are `createX(opts)` returning
  closures over private state, not classes. Reserve classes for genuine
  framework-interface compliance (a React `Component`, a Drizzle `pgTable`,
  etc.), not as a stylistic preference.
- **`Result<T, E>` over `throw`.** Application code does not throw. Every fallible
  function returns a `Result` (neverthrow in TypeScript, `Either`/equivalent
  elsewhere) carrying a typed error union. The caller handles failure as a
  value. `_unsafeUnwrap` / `_unsafeUnwrapErr` are test-only. Total functions that
  genuinely cannot fail are the exception.
- **Parse at boundaries.** Every external input (env, network response, file
  content) goes through a schema (Zod / Valibot / Pydantic / serde) at the
  boundary. Never `JSON.parse` and cast.
- **Discriminated unions over boolean flags.** Express multi-state outcomes as
  tagged unions, not `{ found: boolean; failed: boolean }` bags. This is the
  type-level form of the "two zeros" distinction (§11).
- **Branded types whenever possible.** A `string` that means a user ID, a `number`
  that means Unix seconds, a `bigint` that means cents — brand them at the type
  level. TypeScript: intersection with an opaque tag (`type UserId = string & {
  __brand: "UserId" }`). Rust: newtype pattern. Python: `NewType`. The compiler
  then refuses "you passed a `BookingId` where `UserId` was expected" or "you
  compared seconds to milliseconds." They are nearly free and *infinitely*
  useful — reach for them by default.
- **Atomic conventional commits.** One logical change per commit. The atomic
  discipline is on you; the type prefix is enforced in CI (and by a
  `commit-msg` hook on git-native repos — see §28 for why jj doesn't fire it).
- **Isolated-working-copy concurrent work.** Multiple agents (human or AI)
  routinely work the same repo at the same time. Each work stream runs in its
  own **isolated working copy** — a **jj workspace** (the default; see §28) or
  a git worktree in a non-jj repo — created off **freshly fetched trunk**,
  never by switching the shared checkout and never based on a possibly-stale
  local `main`/trunk ref. The isolated copy covers the *code*; repo metadata,
  PR numbers, and board state stay shared — those remain the genuinely-shared
  steps to slow down on. Spinning one up costs a command or two; mutating
  another agent's working copy under their feet costs their whole run. **The
  isolation unit matters:** in a jj repo it's the workspace, not the git
  worktree — a git worktree isolates files but not jj's single working-copy
  commit `@`, so jj run from a worktree still snapshots the *default*
  workspace and concurrent agents collide.
- **Plan first, attack the plan, gate on the user, then write code.** The `work`
  skill encodes the workflow; this is the underlying habit. Designing in prose
  where the cost of being wrong is a paragraph is cheaper than designing in code.

**Why.** These habits compound. Each one alone is a small tax; collectively they
shift large classes of bug from "discovered in production" to "caught at the
moment you typed them."

**Earn-its-keep.** A `class` is acceptable when the framework expects one. A
`throw` is acceptable when the runtime expects one (a thrown `Response` in
React Router 7, an `error()` in a loader). These are interface compliance, not
deviations.

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

## §16. Value-type discipline

**Rule.** Certain primitive types **lie to you when used naively**. Encode them at
the boundary so they can't.

**Dates and times.**

- **Wire format**: ISO-8601 with explicit UTC offset
  (`2026-05-29T14:00:00Z` / `2026-05-29T14:00:00+00:00`). Never bare local time.
- **Storage**: Postgres `timestamptz` (a UTC instant) or the language's equivalent
  "moment in time with zone" type.
- **Avoid numeric Unix timestamps.** "Is this seconds or milliseconds?" is a
  question nobody should have to ask. Sources that hand you Unix time get
  parsed into a temporal type at the boundary.
- **If numeric seconds are unavoidable** (a third-party API expects them, an
  embedded system emits them), use a **branded type** (§14):
  `type UnixSeconds = number & { __brand: "UnixSeconds" }`. The compiler then
  refuses to compare seconds with milliseconds. This is the canonical
  branded-types example.

**Durations** are typed too. `delayMs: number` and `delaySec: number` should
not both be unbranded `number`s; they should be branded distinct types or a
`Duration` value with explicit units.

**Money.**

- **Where math matters: never floating-point.** JavaScript's `0.1 + 0.2 !== 0.3`
  is the famous case; most languages have the same problem at some
  precision. In TypeScript, use `bigint` for whole units of the smallest
  denomination (cents, satoshis) or `decimal.js` / equivalent when you need
  arbitrary fractional precision.
- **In Postgres**: `numeric(p, s)` is the safe default. Storing money as `text`
  is a defensive option that preserves original precision through round-trips
  at the cost of in-DB filtering/sorting/arithmetic — pick `text` when you
  compute exclusively in the app, `numeric` when the DB also computes.
- **Brand the money type**: `Cents`, `MoneyMinorUnits`. A `number` parameter
  accidentally treated as cents when it was dollars is the kind of bug that
  shows up on a wire transfer.

**Why.** These tiny rules are nearly impossible to retrofit. By the time the
bug shows up — a half-day duplicate in a timezone-naive timestamp, a rounding
error in a billing run — you have a backfill problem on production data.
Encoding at the boundary turns the entire class of bug into a compile error.

**Earn-its-keep.** A throwaway script that prints a chart and exits is allowed
to use floats. A throwaway script that prints "now" is allowed to use a naive
`Date`. State the choice explicitly when you deviate so future-you reading the
commit knows it was deliberate.

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

## §18. Testing philosophy

**Rule.** **Test behaviour. Climb the fidelity ladder.** Most production bugs
live at the seams — at integration layers, at I/O boundaries, in how modules
hand off to each other. A test that crosses a seam *and stays deterministic*
is worth ten unit tests of the components in isolation.

**The fidelity ladder** (prefer the higher rung wherever determinism survives):

| Rung | Tests | When to choose this |
|---|---|---|
| E2E | The full pipeline against a real or recorded external surface | Whenever determinism is achievable (recorded fixtures, fixed time, fixed RNG) |
| Integration | Two or more real modules talking, mocking only true external boundaries | When E2E is too slow or genuinely flaky |
| Unit | One pure function, no collaborators | When the behaviour is genuinely localized — domain math, parser shape, decay curve |

Unit tests have a place; they are **not the load-bearing layer**. A unit-test-heavy
suite passes while the system is broken — a function returning `Result.ok({})`
satisfies a unit test even when its caller expects `{ status: "scored" }`. The
mock-heavy unit world hides exactly the seam bugs that production exercises.

**Concrete rules:**

- **Test names are third-person verbs of observable behaviour.** `test("scores
  a 5-minute grocery at full credit")`, not `test("computeScore works")` or
  `test("calls decay")`.
- **Recorded fixtures over invented stubs** for external boundaries. A response
  shape you invented to match what you *think* the upstream returns tests
  your assumption, not reality. Capture one real response, commit it, parse
  it through the schema in tests.
- **No `.skip`, no `.only`, no env-guarded skips.** A test that needs a key
  fails loudly without the key.
- **Tests in the same commit as the behaviour.** A new mapping, a new error
  path, a new integration parser — all land with coverage in one commit.
- **Drive `Result` to its `err` branch in tests.** A `Result`-returning function
  whose tests only ever assert `isOk()` isn't tested.

**UI components: stories are the test layer for the view.** A UI component's
behaviour is mostly *how it renders in a given state* — and the right tool for
pinning that is **Storybook**. Virtually any non-trivial UI component ships
with at least a few stories, one per meaningful state:

- **Default** — realistic happy-path data.
- **Loading** — what renders while data is on its way.
- **Empty** — a legitimate "genuinely nothing there" result.
- **Error / unavailable** — the upstream failed. Empty and unavailable get
  *separate* stories; this is the "two zeros" distinction (§11) made visible.
- **Edge fullness**, where relevant — overflow content, long names, many items.

Light interactions in a story are fine (a play function that opens the
dropdown). Asserting a multi-step user *flow* is not what stories are for —
that's an E2E test, the top rung of the ladder. Stories answer "does this UI
look right in state X?"; E2E answers "can the user get from A to B?".

Stories also double as a living catalog: a designer or product owner can
browse every state of every component without running the app or reproducing
an error by hand.

**Earn-its-keep.** Heavy mocking earns its keep only when the alternative is
genuinely non-deterministic and no recording strategy works (a third-party
system that doesn't replay sensibly, time-sensitive logic with no clock
abstraction). It does *not* earn its keep merely because the higher-fidelity
test "would be slower" — slower-but-real beats fast-but-fake.

---

## §19. Commercial readiness and authorization

**Rule.** Every project declares whether it is **commercial-ready** or not. This
single setting changes defaults in security-sensitive areas — primarily
**authorization**.

The declaration lives in `CLAUDE.md` near the top (a TODO marker is in the
skeleton). Setting it deliberately at bootstrap prevents both modal failures:
over-engineering a personal tool with full RBAC scaffolding, *and*
under-engineering a SaaS with no authorization plan when the first customer
arrives.

**Defaults by readiness.**

| Concern | Personal / non-commercial | Commercial-ready |
|---|---|---|
| App-layer authorization | Required (even one user has a principal) | Required; **RBAC** is the default model |
| Postgres Row-Level Security | Optional, often overkill | **Strongly recommended** as the second policy layer |
| Audit logging | Not required | Required for auth decisions and data mutations |
| Authorization tests | Smoke tests | Each role × resource matrix tested explicitly |
| PII handling | Project's discretion | Documented in `CLAUDE.md` with explicit rules |
| Tenant isolation | N/A | Enforced and tested at both app and DB layer |

**App-layer authorization is the default.** Even a one-user project has a
"principal" and "permissions" — anything that isn't a query against fully
public data needs a check. RBAC adds structure when distinct roles exist.

**Postgres RLS is the second layer.** It runs *underneath* the application and
catches authorization bugs the app misses — a forgotten `WHERE tenant_id = ?`
becomes a silent zero-rows result instead of a cross-tenant leak. RLS is
non-trivial to operate (connection pooling needs care, debugging is harder),
so it earns its keep when the failure mode (data leak) is unacceptable — i.e.
commercial systems.

**Why this matters at bootstrap.** A commercial-ready project that ships
without RBAC, RLS, and an authorization test matrix is the failure mode this
section exists to prevent. Naming the readiness up front turns it into a
single, visible choice rather than a hundred unmade decisions.

**Earn-its-keep.** A non-commercial project that adopts the commercial defaults
is fine — they're not harmful, just optional for that flavor. A commercial
project that skips them is the violation.

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

## §21. Documentation discipline

**Rule.** Write **why**, not **what**. The code says *what*; documentation,
comments, and commit messages say *why*. They are also simple, clear, and
not needlessly verbose.

**Comments.** Default to no comments. Add one only when:

- A **non-obvious constraint or invariant** lives here ("this loop must run
  before X because Y").
- A **workaround for a specific external bug** ("upstream returns 200 with
  HTML on rate-limit; treat as 429").
- A **surprising algorithmic choice** ("greedy match is intentional — the
  recursive version was 3× slower on N>10k").

Don't write comments that:

- Explain *what* the code does — the code already does that.
- Reference the current task / fix / caller ("added for issue #123") — that
  belongs in the commit message and rots as the codebase evolves.
- Restate the function signature in prose above the function.

**Commit messages.** Same rule, harder discipline. The subject line *is* the
*what* in compressed form (Conventional Commits). The body — when present —
explains the **why** and the **how-if-non-obvious**. Skip the body when the
subject is enough; never pad. Bad: "Updated `score.ts` to handle the new
mapping." (What the diff already shows.) Good: "Treat fast_food as additive
coverage, not parity." (Why the rule changed.)

**ADRs (Architecture Decision Records).** ADRs earn their keep as **temporary
discussion artefacts** for an in-flight decision:

1. A short doc captures the question, the options, the trade-offs.
2. The team / individual debates in PR comments or chat.
3. The chosen direction lands in the codebase (and in `CLAUDE.md` or
   `docs/PHILOSOPHY.md` if it's a durable convention).
4. The ADR is then **archived or removed**.

Permanent ADRs as a documentation strategy compete with `CLAUDE.md` + commit
history and tend to rot — a decision recorded in 2023 referenced by an ADR
from 2021 is harder to track than the commits that implemented the change.
Prefer letting the code, the commits, and the durable docs speak.

**Earn-its-keep.** A permanent ADR earns its keep when the decision involves
something the code genuinely can't express — a vendor choice, a process
change, an SLA commitment, a contractual constraint. Even then, consider
whether it belongs in `CLAUDE.md` (a durable rule) or `docs/PHILOSOPHY.md`
(a durable principle) before it earns its own file.

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

## §24. CI/CD discipline

**Rule.** **Green CI is non-negotiable** (with one partial exception — evals,
see §27); **preview deploys per PR, full-stack**; **commit-msg hook re-enforced
server-side**; **deploy on every merge to `main`**.

**Why.** Tight feedback loops are how you ship multiple times a day with
confidence. A PR that can be clicked-through on a real preview deploy removes
the "well, it works locally" failure mode. A green-only `main` means `main` is
always deployable, which means deploys are routine and small (low-risk by
construction). Conversely, a CI that's allowed to be red sometimes erodes the
signal until nobody trusts it.

**Concrete defaults:**

- **CI runs on every PR**, before merge. Lint, type-check, deterministic tests
  (unit + integration + recorded-fixture E2E), and the commit-msg hook
  re-enforced server-side. Per §1, hooks aren't the obstacle — the client-side
  hook can be bypassed; CI can't.
- **Preview deploys per PR, full-stack.** Frontend, API, **and an ephemeral
  database** where the platform supports it. Railway and Render both do (§6).
  The goal: open a PR, the reviewer clicks a link, the actual feature runs on
  the actual stack — no checkout, no `pnpm install`, no "works on my machine."
  Frontend-only previews are the fallback when full-stack is genuinely hard
  to set up; aim for full-stack — once you have it, you don't go back.
- **Migrations run in CI** against a real ephemeral Postgres before the merge,
  and against production in the deploy step. Migration failure in CI is a
  blocker.
- **Deploy on merge to `main`.** Trunk-based per §17. Every merge triggers
  production. Half-shipped features hide behind flags. Multiple deploys per day
  is the normal cadence, not a milestone.

**The one negotiable: evals (§27).** Deterministic tests must be green; **evals
(non-deterministic by nature) must run on every PR but need not be green** in
the early life of an AI-integrated system. As the system matures and the eval
suite stabilizes, lock the threshold in. Details in §27.

**Earn-its-keep.**

- Full-stack preview deploys are a real setup cost. If the platform doesn't make
  it trivial (Railway and Render do; raw Docker hosts don't), the project's
  earliest milestones can run with frontend-only previews. Plan to upgrade.
- Manual approval gates on deploy-to-prod earn their keep in regulated industries
  and never elsewhere. Trust the test suite or fix the test suite.

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

---

## §26. Avoid double state — single source of truth, prefer consistency

**Rule.** The system has **one source of truth** for any given piece of state.
Wherever a second store, a derived index, a cache, or a replicated copy would
create state that must be kept in sync, the burden is on the *deviation* to earn
its keep. **Strong consistency over availability** in the CAP trade for most
products.

**Why.** Double state is the second-most expensive complexity tax in software
(after the §1 reach-for-bigger-architecture one). Every duplicate is a sync
problem in waiting: the indexer falls behind, the cache goes stale, the replica
diverges. Bugs that come from these are notoriously hard to reproduce because
they depend on *which* copy you read and *when*. Avoiding the duplicate in the
first place — the single Postgres source-of-truth that everything reads — is
cheaper than any of the strategies for managing it.

**The CAP-theorem stance.** Most products aren't Google-scale; the actual cost
of dropping availability briefly during a partition or write spike is small, and
the cost of operating an eventually-consistent system is large. We pick **C**
(strong consistency) over **A** (availability) for most things. Outages are
explainable and recoverable; data corruption from eventually-consistent merges
is not.

**Applications:**

- **Search.** Postgres FTS (`tsvector` + `tsquery`, `pg_trgm`, GIN indexes) is
  the default. A dedicated search index (Meilisearch, Typesense, OpenSearch,
  Algolia) duplicates the indexed data, requires sync (CDC, dual-writes,
  background reindexers) with its own failure modes, and earns its keep only at
  scale or feature shapes Postgres FTS genuinely can't serve (advanced relevance
  ranking, faceted search at enormous scale, fuzzy multi-language). Most
  products outgrow their original search problem before they outgrow Postgres
  FTS.
- **Caching.** A cache is duplicate state. Eat the database read first; reach for
  the cache only when a real, current, measured performance problem demands it.
  When you do, prefer caches that are *invalidatable* (a Postgres `*_cache`
  table you control) over caches that are only *time-bounded* (Redis with a
  TTL). The §11 in-flight map covers stampede protection on egress without
  introducing a second store.
- **Read replicas.** Same pattern as §3 — earn-their-keep on a measured
  read/write contention problem, never preemptively.
- **Materialized views.** Acceptable as cached aggregates the app already knows
  how to compute (§5 / §15). Not acceptable as the place where the app's actual
  data lives.

**When availability beats consistency.** Some products legitimately need it — a
content-delivery layer that has to stay up under partition (eat the small chance
of serving stale content), a write path that absolutely must not block (queue
and reconcile later via §22). When you make this trade, **name the boundary**
of the eventually-consistent zone so the rest of the system stays strongly
consistent.

**Earn-its-keep.** Any deviation that creates double state names the current,
felt problem the single-source-of-truth approach doesn't solve, the sync
strategy *with its failure modes*, and the operational cost. Same bar as §1.

---

## §27. AI / LLM integration

**Rule.** Integrating an LLM into a product brings its own slice of the
philosophy: **non-deterministic outputs**, **per-request cost**, **provider
risk**, and **eval discipline as the load-bearing tool**. Treat an LLM call as a
§11 API integration with these concerns layered on top.

### Evals are the load-bearing tool

Deterministic tests can't tell you whether the system *actually does the thing*
when the model itself is non-deterministic. Evals can.

**Fixtures + accuracy thresholds**, not pass/fail. An eval suite is a set of
`(input, expected_or_acceptable_output)` fixtures, run through the actual model,
scored against a target threshold (e.g. *≥ 80% match*, *false-positive rate
≤ 5%*, *ranking agreement ≥ 0.7 with the human gold*). The pass/fail is on the
**threshold**, not on any individual fixture — the model is allowed to miss any
particular case as long as the aggregate behaves.

**Prefer fixtures over LLM-as-judge** wherever the output is binary,
multi-choice, or otherwise scoreable by a deterministic comparison. LLM-as-judge
has its place (open-ended generation where no fixed answer exists), but every
judge call is its own non-determinism and its own bill. Use it sparingly.

**Evals run on every PR but are not always required to pass.** Especially in the
inception phase of an AI feature — when you're still figuring out the model,
the prompt, and the eval suite itself — a red eval is a signal, not a blocker.
Locking the threshold in on day one teaches the team to game the threshold
instead of building the feature.

As the system stabilizes, **promote evals to blocking** with a regression
threshold (new PR's score must be ≥ baseline − N%). Until then, the score is
visible on every PR but not enforced. This is the carve-out in §24's "green CI
is non-negotiable" rule.

**Eval improvement is itself a system.** You start with a small fixture set and
you improve it as you ship — adversarial cases, user-flagged outputs, sampled
production traffic. Two viable strategies:

1. **Manual labelling** — recurring review of recent outputs, tagged for
   correctness, added to the eval set.
2. **Self-healing** — production traffic sampled and auto-labelled (by another
   model, by heuristics, by explicit thumbs-up/down in the UI), fed back into
   the eval set.

Manual is the safe default; self-healing earns its keep when volume makes manual
infeasible and the auto-labelling is reliable. Either way, there *is* a system —
not a static suite that ages out of relevance.

**Eval improvement informs model improvement.** When the eval bar moves, the
prompt / RAG retrieval / fine-tune improves to clear it — either manually
(a human reads the failing cases and edits the prompt) or self-healing (a
tuning loop optimises against the eval set). The cycle — eval → model
improvement → eval again — is the actual product loop for AI features.

### Provider choice

**Default: Anthropic and OpenAI**, accessed via **OpenRouter** as the unified
surface. Same logic as §13: managed APIs absorb the operational cost of running
large models; self-hosted earns its keep only on a named cost or compliance
reason.

**OpenRouter specifically** because: a single SDK fronts dozens of providers,
easy switching without code rewrites, single billing across providers, and
pay-with-crypto. Reduces vendor lock-in along the §13 own-the-data axis — you
can leave any single provider without changing your code.

**Self-hosted models earn their keep** on:

- **Regulatory or data-protection** constraints that genuinely forbid sending
  data to a third party. The most common real reason.
- **Cost** at very high volume — bar is high; operating a model at production
  quality is expensive in its own ways (GPUs, ops, security patches, model
  upkeep).
- **Latency** in a specific geo where managed providers don't serve well — rare.

### Cost discipline — track every metered call

**Hard line: every metered API call is logged in Postgres** with enough fields
to attribute cost per user, per request, per model, per time window. This is
non-negotiable for any project that ships AI features.

Shape (adapt to the project):

```
api_calls (
  id, user_id, request_id, provider, model, endpoint,
  input_tokens, output_tokens, cost_estimate_cents,
  latency_ms, status, started_at, finished_at
)
```

**Why this is non-negotiable.** AI costs scale per-request, not per-user-month.
A bug, an abusive user, or a hot loop can rack up four-digit bills in hours.
Without per-request tracking, you find out from the provider's billing page
weeks after the fact. With it, you alert at the first $10/hour anomaly and you
know exactly which user / request / model / time window did it.

**The rule extends to any per-request metered API**, not only LLMs (Twilio SMS,
certain Maps APIs, transaction-fee processors). The §11 in-flight map / rate
limiter is about *not making* expensive calls; the cost-tracking table is about
*knowing what you did make* once you let them through.

**Earn-its-keep — when cost tracking can be relaxed:**

- **Non-commercial / personal projects** with a known small footprint and a
  single user. The provider's billing page is fine.
- **Multi-tenant where each user gets their own deployment / self-hosts.** Cost
  is naturally segregated by deployment; internal tracking is redundant.
- **Non-metered APIs** (a flat-rate SaaS, an internal service). No per-call cost
  to attribute.

### Provider fallback

**Default: if the provider is down, that feature is down.** Accept the §26 trade
— consistency over availability — and let the request fail loud (with the §11
breaker open, the §12 error tracker firing). Most products survive an AI
provider being down for an hour; few products survive an auto-failover that
silently produces wrong answers from a fallback model.

**When the product must stay available** (commercial-ready, customer-facing,
contractually guaranteed), declare an **ordered fallback chain** in code — try
the primary, on §11 breaker-open or provider error fall through to the
secondary, etc. The chain is observable per §12 so you know when you're
degraded. The cost-tracking table (above) records which provider actually
served each request so the bill stays attributable.

### Prompt as code vs prompt as data

**Case by case.** The eval strategy is the strongest constraint: if your evals
are stable and prompts change rarely, **code** is fine (versioned with the
codebase, simple to ship, branches under git). If your prompts iterate
per-customer or per-experiment, **data** is fine (a `prompts` table with
versions, A/B-tested, possibly self-healed by the eval loop).

Pick based on how the prompt actually evolves in your product. Both can be
right; neither has a default.

---

## §28. Version control — jj (colocated)

**Rule.** The working copy is **Jujutsu (jj)**, colocated with git (there's a
`.jj` directory alongside `.git` at the repo root). git stays underneath as the
*interop and remote* layer — GitHub, `origin`, the shared history teammates see
— and jj drives all local version-control work on top of it. This holds even
when the wider team is on plain git: the shared history is git, the local
working copy is jj, and `jj git push` / `jj git fetch` bridge the two. Most
single-author projects can be jj end to end.

**The isolation unit is the workspace, not the worktree** (this is the load-
bearing reason jj changes §14). jj has a *single* working-copy commit `@` per
workspace. A git worktree gives you a second checkout of the files but it does
**not** give you a second `@` — run jj from inside a git worktree and it
snapshots and mutates the *default* workspace's `@`. So concurrent agents
sharing one jj repo must each get their own **`jj workspace`**, not a git
worktree:

- `jj workspace add --name <slug> --revision 'trunk()' <path>` — new workspace
  with its own `@` based on freshly-fetched trunk (run `jj git fetch` first;
  `mkdir -p` the parent, since `jj workspace add` won't create it).
- Work there, then `jj workspace forget <slug>` and remove the directory when
  done. All workspaces share one repository, so a jj GUI (e.g. GG) still shows
  every workspace's `@` in a single graph.

**Snapshot model, not staging.** jj auto-snapshots the working directory into
`@` on every command — there is no index, no `git add`. The consequences ripple
through the skills:

- A commit is `jj commit [paths] -m "..."` (finalizes `@`, or just the named
  paths, into a commit and leaves a fresh `@` on top). No staging step to get
  wrong, and atomic splitting is `jj commit <paths>` per logical unit.
- Folding a fix into an earlier commit is `jj squash --from <rev> --into <rev>`,
  never a git `--fixup` dance.
- The reviewable diff of a branch — committed *and* uncommitted at once — is
  `jj diff --from 'trunk()' --to @`, because uncommitted edits already live in
  `@`. One command replaces git's staged/unstaged/committed three-way gather.

**Bookmarks are branches.** jj's named pointers are *bookmarks*. The branch you
open a PR from is a bookmark pointing at your tip commit: `jj bookmark set
<branch> -r @-` then `jj git push --bookmark <branch>` (auto-tracks the remote,
does the safe force-with-lease). Rebasing onto advanced trunk is
`jj git fetch && jj rebase -d 'trunk()'` then a plain `jj git push` — jj's push
is force-with-lease by default, so there is no `--force` to fumble. The PR
itself is still `gh` (jj has no PR concept), and the merge is still
`gh pr merge --rebase` on the pushed git commits.

**jj does not fire git hooks.** A colocated repo's `pre-commit` / `commit-msg`
hooks do **not** run under `jj commit`. So the two guarantees those hooks
normally give — conventional-commit format and a green lint/typecheck/test gate
— move into the workflow itself: the `commit` skill validates the message shape
and runs the project's checks before finalizing, and CI re-enforces both
server-side (§24). Don't assume a hook caught what jj silently skipped.

**Why.** jj makes the §14 habits (small atomic commits, isolated concurrent
work, fearless rebasing) cheap enough that they actually happen. The cost is one
sharp edge — the single-`@`-per-workspace model — and getting it wrong (a git
worktree where a workspace was needed) corrupts concurrent runs silently. Naming
the workspace-not-worktree rule here, once, is what keeps every skill downstream
correct.

**Earn-its-keep.** A repo with no jj (`.jj` absent) falls back to git worktrees
and plain git — the skills are jj-native by default, so a non-jj repo is the
deviation, not the rule. Reach for raw `git` mutations inside a jj repo only for
something jj genuinely can't express; nearly everything has a jj verb, and
mixing the two is how divergent duplicate commits appear.

---

## What this document is not

- A roadmap. Sections aren't features; they're principles.
- A checklist. The principles need judgment; that's what the "earn its keep"
  language is for.
- A guarantee. If a future project genuinely needs Kafka, you reach for Kafka
  and you write down why. The system here makes the deviation deliberate, not
  forbidden.

Drift policy: this document is the canonical source. When a project's
`CLAUDE.md` or `.claude/` configuration disagrees, the disagreement is either
a project-specific earn-its-keep deviation (with a written reason) or a
template drift that should be backported to
[`mauricedesaxe/claude-harness-template`](https://github.com/mauricedesaxe/claude-harness-template).
