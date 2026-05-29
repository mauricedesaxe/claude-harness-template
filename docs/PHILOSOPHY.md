# Philosophy

The durable "why" behind the conventions enforced by `CLAUDE.md` and the
`.claude/` skills/agents in any repo bootstrapped from
[`claude-harness-template`](https://github.com/mauricedesaxe/claude-harness-template).

`CLAUDE.md` is the **rules**, dense and enforceable, applied to *this* project.
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
- **Atomic conventional commits.** One logical change per commit. The
  `commit-msg` hook enforces the type prefix; the atomic discipline is on you.
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
