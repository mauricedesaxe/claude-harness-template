# Philosophy

The durable "why" behind the conventions enforced by `CLAUDE.md`, `AGENTS.md`, and
the `.claude/` skills/agents in any repo bootstrapped from
[`claude-harness-template`](https://github.com/mauricedesaxe/claude-harness-template).

This file is the paradigm-agnostic **spine** — the engineering principles that hold
for any codebase, whether or not it is a web product. The web/backend prescriptions
(single-instance Postgres, hosting, frontend, background jobs, blob storage, realtime)
live in [`packs/web.md`](packs/web.md); the AI/LLM prescriptions live in
[`packs/ai.md`](packs/ai.md). A repo **always** applies the spine, then layers on
whatever packs match its paradigm — a smart-contract or mobile repo takes the spine
and simply omits the web pack.

Section numbers (§1–§28) are **stable IDs**: a section keeps its number wherever it
lands, and inline `§N` cross-references resolve through the index below, which records
the file each section lives in. Six sections **split** — a universal kernel stays here
and the web-specific prescription lives under the same `§N` heading in the web pack.

`CLAUDE.md` is the **rules**, dense and enforceable, applied to *this* project.
`AGENTS.md` is the **Codex bridge**, intentionally thin, so Codex follows the same
rules instead of growing a parallel source of truth.
This doc is the **reasoning** — the kind of thing you re-read when an edge case
shows up that the rules don't obviously cover. When `CLAUDE.md` is silent or
ambiguous, defer to the section number here.

The shape: every section has a **rule**, the **why**, and the **earn-its-keep**
clause (when deviation is allowed, and what bar a deviation has to clear).

## Section index

| § | Title | Location |
|---|---|---|
| §1 | Earn its keep | Spine |
| §2 | Languages | Spine + packs/web.md (web specifics) |
| §3 | Single-instance default | packs/web.md |
| §4 | Modular monolith | Spine + packs/web.md (web specifics) |
| §5 | Data: Postgres only | packs/web.md |
| §6 | Hosting: managed platforms over IaC and k8s | packs/web.md |
| §7 | Web layer: no serverless, no edge | packs/web.md |
| §8 | Web app architecture | packs/web.md |
| §9 | CDN: Cloudflare | packs/web.md |
| §10 | End-to-end type safety | Spine + packs/web.md (web specifics) |
| §11 | API integration primitives | Spine |
| §12 | Observability | Spine + packs/web.md (web specifics) |
| §13 | Outsource the non-core | Spine |
| §14 | Code-level discipline | Spine |
| §15 | Database discipline | packs/web.md |
| §16 | Value-type discipline | Spine |
| §17 | Feature flags | packs/web.md |
| §18 | Testing philosophy | Spine |
| §19 | Commercial readiness and authorization | Spine + packs/web.md (web specifics) |
| §20 | Frontend defaults and local-first | packs/web.md |
| §21 | Documentation discipline | Spine |
| §22 | Background jobs and scheduled work | packs/web.md |
| §23 | File and blob storage | packs/web.md |
| §24 | CI/CD discipline | Spine + packs/web.md (web specifics) |
| §25 | Realtime — polling first | packs/web.md |
| §26 | Avoid double state | Spine |
| §27 | AI / LLM integration | packs/ai.md |
| §28 | Version control — jj (colocated) | Spine |
| §29 | Shaping, appetite, and betting | Spine |

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

**Rule.** Pick one primary language for the stack and make everything else earn
its keep. A second or third language is a deliberate, justified choice; a fourth
needs a major justification. Don't let languages sprawl.

**Why.** Every additional language doubles the surface area of "how do we lint,
test, deploy, lockfile-pin, supply-chain-cooldown this part?" One primary language
keeps the toolchain, type system, and dependency discipline singular. Where both
ends of a boundary share a language, end-to-end type safety (§10) comes nearly
free.

**Earn-its-keep.** A secondary language earns its keep when its ecosystem is
genuinely the right tool, not a preference. The project's paradigm pack names the
concrete defaults — for web/backend that's the TypeScript-first stack in
[`packs/web.md`](packs/web.md) §2.

---

## §4. Modular monolith

**Rule.** Inside a single deployable, organize code **by business domain** —
not by technical layer. The folder structure exposes the domains; the
inter-module boundary is the API the rest of the codebase consumes.

**Why.** Layered structures (`controllers/`, `services/`, `repositories/`) hide
the domain and spread one business concept across many folders, so every change
hops files. Domain-shaped structures (`billing/`, `orders/`, `inventory/`) put
each concept in one place.

**Earn-its-keep.** The default is: a new domain is a new module folder, not a new
repo.

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

The last is a good starting point for a domain-core service (and what `CLAUDE.md`
skeleton's architecture TODO suggests as one). All three are fine; what's *not* fine is a
top-level `services/` + `controllers/` + `repositories/` cut that flattens the
domain.

---

## §10. End-to-end type safety

**Rule.** Every boundary between machines, processes, and modules is **typed
end to end**. Network responses are parsed through a schema (Zod / Valibot /
Pydantic / serde) at the boundary; the parsed type flows through the rest of
the code with no further validation.

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
reference TypeScript implementation is a `server/concurrency/` module.

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

**Applications across the philosophy** (these are §13 in action):

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
  type-level form of the "two zeros" distinction (§14, discriminated unions).
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
  *separate* stories; this is the "two zeros" distinction (§14) made visible.
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
| Audit logging | Not required | Required for auth decisions and data mutations |
| Authorization tests | Smoke tests | Each role × resource matrix tested explicitly |
| PII handling | Project's discretion | Documented in `CLAUDE.md` with explicit rules |

**App-layer authorization is the default.** Even a one-user project has a
"principal" and "permissions" — anything that isn't a query against fully
public data needs a check. RBAC adds structure when distinct roles exist.

**Why this matters at bootstrap.** A commercial-ready project that ships
without RBAC, RLS, and an authorization test matrix is the failure mode this
section exists to prevent. Naming the readiness up front turns it into a
single, visible choice rather than a hundred unmade decisions.

**Earn-its-keep.** A non-commercial project that adopts the commercial defaults
is fine — they're not harmful, just optional for that flavor. A commercial
project that skips them is the violation.

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

## §24. CI/CD discipline

**Rule.** **Green CI is non-negotiable** (with one partial exception — evals,
see §27); **commit-msg hook re-enforced server-side**; **deploy on every merge to
`main`**. (Per-PR full-stack preview deploys are a web/backend prescription —
[`packs/web.md`](packs/web.md) §24.)

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
- **Deploy on merge to `main`.** Trunk-based per §17. Every merge triggers
  production. Half-shipped features hide behind flags. Multiple deploys per day
  is the normal cadence, not a milestone.

**The one negotiable: evals (§27).** Deterministic tests must be green; **evals
(non-deterministic by nature) must run on every PR but need not be green** in
the early life of an AI-integrated system. As the system matures and the eval
suite stabilizes, lock the threshold in. Details in §27.

**Earn-its-keep.**

- Manual approval gates on deploy-to-prod earn their keep in regulated industries
  and never elsewhere. Trust the test suite or fix the test suite.

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


## §29. Shaping, appetite, and betting

**Rule.** Work runs at **two altitudes**, and the planning machinery lives at the
upper one. An **initiative** (a GitHub *milestone*) is the unit you shape, bet on,
and circuit-break; an **issue** is the granular unit you capture, research, and
build. Shape Up's planning verbs operate on milestones (`shape`, `bet`, `prune`);
the per-issue skills (`capture`, `research`, `work`, `commit`, `ship`) operate on
issues. Don't push betting, appetite, or scope-hammering down into `work` — that
skill is deliberately granular and runs to completion on one issue.

Adapted from 37signals' Shape Up to a solo, agent-driven shop. The parts that
assume a full-time team in a room — the betting *meeting*, hill-chart status
broadcasts, the fixed six-week calendar cycle, cool-down weeks, the 40-hour-week
culture — are dropped or reshaped. The load-bearing ideas are kept: fixed appetite
with variable scope, shaping before committing, a hard circuit breaker, no runaway
projects.

**Appetite, measured in sittings.** Every initiative (and optionally every issue)
carries an **appetite**: a deliberate cap on how much of the scarce resource you'll
spend, *not* an estimate of how long it'll take. In an agent-driven solo shop the
scarce resource is **your supervision attention** — not labor-hours and not agent
compute. You fire the agent and go do other work; agent wall-time is abundant and
nearly free, while your return visits to check and redirect it are what's scarce.
So appetite is counted in **sittings**: one sitting is one time you sit down, check
the agent, redirect it, and leave. The name is literal — one sitting is one
sit-down at the work. Three fuzzy bands, never auto-counted:

- **S — one sitting.** Fire it once, one check, done.
- **M — a few sittings.** A handful of agent-runs and checks over a couple of days.
- **L — many sittings.** Many check-ins over a week or more of real calendar time.

It's a cap you *declare*, not a number you measure, so you never have to estimate
hours. Any time-tracking or session markers you keep are **soft context you
eyeball**, never a meter the harness reads automatically — fuzzy is the point.
The appetite system stands alone.

**Shaping.** Before an initiative can be bet on it must be *shaped*: name the felt
outcome, set its appetite, sketch which issues are in vs out, and hunt the **rabbit
hole** — the one unknown that could blow the appetite — resolving or de-scoping it
up front. Shaping can conclude "don't build this," and that's a success, not a
waste. The `research` skill is the rabbit-hole hunt at the milestone altitude; it
runs at both altitudes (milestone-scale shaping research and single-issue
research). The `shape` skill produces a shaped milestone whose description *is*
the pitch.

**Betting, with a WIP cap.** Shaping and betting are separate acts: you might shape
several initiatives in one sitting, then later sit down to bet across all the shaped
ones. A **bet** commits a milestone to the active set and sets its cutoff. **One to
three bets may be active at once** (some initiatives parallelize); **never more than
three** — a fourth is refused until one resolves. `bet` always shows the active bets
(with cutoffs) and the recently-finished ones *before* the table, because how full
the pipe is and what you just shipped both inform what to take on next.

**Circuit breaker.** Fixed appetite, variable scope: when an initiative reaches its
cutoff (or has plainly burned past its appetite in sittings), it does **not**
auto-extend. The breaker is the first step inside `bet` — before placing a new bet
you resolve any expired or over-budget one: **ship what's done, re-shape it** (back
to the drawing board, Shape Up's step 6), **or drop it.** The default is *the
project loses, the appetite holds*, never *the deadline silently moves* — that's
what forces scope to get hammered down during the work rather than after. You ship
fast, so you'll rarely trip it; it's the guardrail against the silent runaway, not
an everyday event.

**The backlog stays — deliberately.** Shape Up kills the backlog; we don't. This is
a solo side project you don't touch daily, so the backlog is your **re-entry
state** — where you left off and what was next — and deleting it would delete your
memory of the work. Instead it gets a periodic **prune** (`prune`): kill the
genuinely dead, keep the live. A future agent must not "tidy" the backlog out of
existence; the backlog-as-memory is precisely why it's allowed to exist against
Shape Up's grain.

**Why.** Two altitudes keep the planning machinery from contaminating the build
loop: `work` stays a clean, granular, runs-to-completion skill, while the decisions
about *what's even worth building* live one level up where they belong.
Appetite-in-sittings makes "how much is this worth" answerable without a time
estimate you can't give. The breaker is the single rule that makes fixed-appetite
real — without it, "appetite" is just a wish. The WIP cap of three stops a solo from
fragmenting attention across more initiatives than one person can hold.

**Earn-its-keep.** This whole layer is optional scaffolding tuned to *this* working
style; a different project can ignore it and run plain `capture` → `work`. Reach for
the initiative layer when work clusters into multi-issue efforts worth shaping and
betting on (a platform migration, a framework migration, a new service kind of
effort); skip it for one-off issues that don't need a milestone.
The bands and the cap are fuzzy on purpose — making them precise would be false
precision that earns nothing.

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
