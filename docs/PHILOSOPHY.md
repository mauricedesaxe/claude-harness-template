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
