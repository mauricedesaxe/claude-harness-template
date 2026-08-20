# Philosophy

The durable "why" behind the conventions enforced by `CLAUDE.md`, `AGENTS.md`, and the
skills and agents that
[`lazar-harness`](https://github.com/mauricedesaxe/claude-harness-template) installs.

This file is the paradigm-agnostic **spine**, the engineering principles that hold
for any codebase, whether or not it is a web product. The web/backend prescriptions
(single-instance Postgres, hosting, frontend, background jobs, blob storage, realtime)
live in [`packs/web.md`](packs/web.md). The AI/LLM prescriptions live in
[`packs/ai.md`](packs/ai.md). A repo **always** applies the spine, then layers on
whatever packs match its paradigm. A smart-contract or mobile repo takes the spine
and omits the web pack.

Section numbers are **stable IDs**. A section keeps its number wherever it lands,
and inline `§N` cross-references resolve through the index below, which records the
file each section lives in. Six sections **split**: a universal kernel stays here,
and the web-specific prescription lives under the same `§N` heading in the web pack.

`CLAUDE.md` is the **rules**, dense and enforceable, applied to *this* project.
`AGENTS.md` is the **Codex bridge**, deliberately thin, so Codex follows the same
rules instead of growing a parallel source of truth.
This doc is the **reasoning**. Re-read it when an edge case shows up that the rules
don't obviously cover. When `CLAUDE.md` is silent or ambiguous, defer to the section
number here.

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
| §25 | Realtime: polling first | packs/web.md |
| §26 | Avoid double state | Spine |
| §27 | AI / LLM integration | packs/ai.md |
| §28 | Version control: jj (colocated) | Spine |
| §29 | Narrative order | Spine |
| §30 | Felt outcome and writing | Spine |
| §31 | Code style | Spine |
| §32 | Complexity and deep modules | Spine |
| §33 | Controlled language | Spine |
| §34 | UI and UX design principles | packs/web.md |

---

## §1. Earn its keep

**Rule.** The simpler architecture wins by default. Anything more complex has to
*earn its keep* before it lands. That covers a second instance, a replica, a queue,
and a cache layer. It also covers a different language, a different database, an
infrastructure-as-code tool, and a hosting platform with more moving parts. The
bar is the same one §30 applies to product work: a **felt, current, specific
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
2. You **tried or thought through the simpler alternative and ruled it out**
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

**Why.** Every additional language doubles one surface area: how do we lint, test,
deploy, lockfile-pin, and supply-chain-cooldown this part? One primary language
keeps the toolchain, type system, and dependency discipline singular. Where both
ends of a boundary share a language, end-to-end type safety (§10) comes nearly
free.

**Earn-its-keep.** A secondary language earns its keep when its ecosystem is
genuinely the right tool, not a preference. The project's paradigm pack names the
concrete defaults. For web/backend that's the TypeScript-first stack in
[`packs/web.md`](packs/web.md) §2.

---

## §4. Modular monolith

**Rule.** Inside a single deployable, organize code **by business domain**, not
by technical layer. The folder structure exposes the domains. The inter-module
boundary is the API the rest of the codebase consumes.

**Why.** Layered structures (`controllers/`, `services/`, `repositories/`) hide
the domain and spread one business concept across many folders, so every change
hops files. Domain-shaped structures (`billing/`, `orders/`, `inventory/`) put
each concept in one place.

**Earn-its-keep.** The default is: a new domain is a new module folder, not a new
repo.

**Examples**, not prescriptions. Pick the granularity your project warrants:

```
# Mid-size: explicit subdirectories per module
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
# Smaller: module = single file
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
end to end**. A schema (Zod / Valibot / Pydantic / serde) parses network responses
at the boundary. The parsed type flows through the rest of the code with no
further validation.

**Why.** Untyped boundaries are the load-bearing source of production bugs.
"It worked locally" usually means one thing: the local data shape matched the
type we assumed in code. A schema at the boundary turns those bugs into
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
4. **Circuit breaker**: when the upstream fails N times within a window,
   open the circuit and fail fast for a cooldown before the next probe.
5. **Retry with jittered backoff**: handle transient errors. Caller picks the
   `shouldRetry` predicate so the integration decides which error codes are
   transient.

(Yes, that's five. The "four" was the brain dump. In practice the bounded
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
- **Consumer decides policy.** Defaults are conservative. Every knob is a
  caller-supplied option: `maxAttempts`, `baseDelayMs`, `shouldRetry`,
  `onRetry`, breaker `failureThreshold`, breaker `cooldownMs`, limiter
  `tokensPerWindow`, limiter `windowMs`, semaphore `maxConcurrent`, and
  inFlight `keyFn`.
- **In-memory by default.** State lives in the process. This is a deliberate
  choice tied to §3: a single instance is the default, so in-process state
  works. If you ever scale to multiple instances (after §1 earns it), you
  swap the in-memory backing for a shared one. You don't pay that complexity
  until you have to.
- **Each primitive returns a `Result<T, E>`** with a typed error union (e.g.
  `BreakerOpen`, `RateLimitExceeded`, `RetryExhausted`). It never throws.

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
choice. See the project's `CLAUDE.md` for the actual module(s). The standing
reference TypeScript implementation is a `server/concurrency/` module.

---

## §12. Observability

**Rule.** Every project ships with **structured logs and distributed traces from day
one**. Errors are **never sampled out**. At small scale, the default sampling rate
for successful traces is **100%** (or as close as the ingest budget allows). Metrics
and alerts are secondary tools, not load-bearing primitives. They matter when
there's an SLO to defend or an on-call rotation that receives alerts.

**Why.** When something breaks, you can only diagnose with the signal you already
captured. A sampling decision made before an incident is a bet that the next
failure sits among the kept samples. At small scale that bet is unnecessary.
Keep everything until you have a real ingest-cost problem.

Traces with spans are the single most valuable observability tool. They show the
actual execution path through your code, including DB calls, external upstreams,
and timing. That's exactly the surface area where the load-bearing bugs and
latency problems live. One trace with proper spans usually answers a debugging
question that costs an hour of `git log` and `console.log` to reach.

**Distributed tracing.** When the system is more than one process, use the W3C
**Trace Context** standard (`traceparent` / `tracestate` headers). A single trace
then spans every service. Both Sentry and BetterStack consume OpenTelemetry, which
uses the standard. Don't invent your own correlation header.

**What to log** (in addition to the structured-logging Hard rule):

- Every external upstream call: latency, status code, retry count, circuit-breaker
  state, rate-limiter wait time.
- Cache decisions: hit / miss / write, with the cache key.
- Domain-meaningful events: a score computed, a job enqueued, a webhook received.
- Never log API keys. Never log full PII without an explicit, documented reason.

**Earn-its-keep.**

- **Aggressive sampling** (5%, 1%, 0.1%) earns its keep when ingest cost is a
  current, felt budget problem. When it does, prefer **tail-based** sampling. Keep
  100% of errors and slow traces, and sample the successful, fast ones. Never
  sample errors.
- **Metrics dashboards** earn their keep when an SLO or a capacity-planning
  decision rides on them.
- **Alerts** earn their keep when a human or a rotation reads them. An unactioned
  alert is noise.

---

## §13. Outsource the non-core

**Rule.** When you have a problem to solve and the problem is **not your core
competency**, default to **paying for an existing solution**. To build it yourself
or self-host it earns its keep in three cases only. (a) The problem IS your core
competency. (b) The paid solution becomes a current, felt cost problem. (c) The
paid solution is unreliable in a way that hurts users.

**Why.** To build, run, and operate a homebrew solution costs more time than the
paid one costs in dollars. That holds *especially* once you count maintenance,
security patches, upgrade churn, and the on-call burden of last resort.
A vendor whose core competency is your problem already paid the cost of the hard
edges you haven't hit yet. To outsource buys you their solved problem. To build
means you re-solve it on your own time.

This is the **sister rule to §1**. §1 says "the simpler architecture wins by
default." §13 says "the paid tool wins over the built tool by default." Together
they bias the system toward shipping product on top of someone else's solved
problem, not toward becoming a platform team for your own infrastructure.

**Applications across the philosophy** (these are §13 in action):

- **Hosting (§6)**: managed Docker platforms over IaC and k8s.
- **CDN (§9)**: Cloudflare's CDN over a homebrew edge cache.
- **Observability (§12)**: Sentry + BetterStack over a self-hosted Grafana stack.
- **Data (§5)**: **Railway Postgres** or **DigitalOcean Managed Postgres**
  (plain managed Postgres, no abstraction layer above it) over your own instance.
  Avoid "Postgres-plus-platform" products (Supabase, etc.) that abstract the
  database away and lock you to their surface. By the "own the data" rule below,
  you want managed *Postgres*, not "a service backed by Postgres".
- **Auth**: **BetterAuth**, an open-source library that runs on your own backend,
  so the user records live in your own Postgres. Hosted-identity SaaS (Clerk,
  Auth0, Descope, etc.) outsources more aggressively and gives up data ownership.
  See the "own the data" rule below.
- **Email / SMS**: Resend, Postmark, Twilio over your own MTA. The data here is
  transactional output, not durable identity, so the data-ownership rule
  constrains it less.

**Sub-rule: own the data.**

Some outsourced solutions offer two forms. One is a **managed SaaS**, where the
vendor holds your data on their infrastructure. The other is a **library or
service you run yourself**. There the data stays in your own Postgres, object
store, or process. Prefer the library version.

The running code is a short-term productivity gain, and the data is a long-term
asset. Vendor lock-in gets harder to escape with every year the data sits in
their system.

A vendor whose incentives, pricing, or product direction shift later can hold
that data hostage. They cannot do the same to an open-source library.

This applies most strongly to **durable, identifying, or strategic data**:

- **User identities and accounts**: BetterAuth, with the data in your DB, wins
  over hosted-identity SaaS by this rule. When you migrate auth providers, a user
  table already on your side of the wall decides everything. It is the difference
  between "swap the library" and "data migration project".
- **Customer records, content, domain state**: these belong in your own DB
  (per §5 Postgres only), not in a CMS-as-a-service or a Firestore-shaped
  vendor lock-in.
- **Anything that's a moat**: proprietary data, scores, recommendations,
  curated content, stays on your side, period.

It applies less to **transactional output and ephemeral context**:

- Sent emails (Resend / Postmark), sent SMS (Twilio), pushed notifications.
- CDN cache contents, edge logs.
- Observability ingest (§12). Even there, prefer vendors with clean export paths,
  so you can leave with the historical data.

Sometimes you can't have both, because there is no library version of the problem.
§13's outer rule still applies: pay for the SaaS. But check first. The library
version often exists, and it is the better choice on the data-ownership axis.

**Where you do NOT outsource:**

- **The domain core.** When you build a scoring engine, the scoring engine is
  yours. You don't pay a vendor for "scoring as a service". The product *is* the
  way you do that one thing.
- **Durable user / customer / domain data.** The "own the data" sub-rule above is
  the operational form of this. Even when you outsource the *solution*, keep the
  *data* on your side of the wall wherever the library form lets you.
- **Anything that exposes proprietary data or a strategic moat** to a vendor whose
  incentives could turn against you.

**Earn-its-keep for a non-core component you build or self-host.** The bar is the
same as §1:

1. A current, felt, named problem with the paid solution. Cost bites *now*, not
   "what if it scales". Reliability caused specific user-visible incidents with
   documented numbers.
2. An articulated reason the simpler paid thing doesn't work for the problem.
   A hypothetical or aesthetic objection is not one.
3. An accepted operational cost: on-call, upgrades, security, and the new failure
   modes you now own.

"It would be cleaner if we owned this" doesn't qualify. "It would be cheaper at
some future scale" doesn't qualify. "The vendor's API isn't quite ergonomic" doesn't
qualify. Reach for the build path only when the paid path is *currently broken in
a named way*. Document that named problem in the commit that adopts the build.

---

## §14. Code-level discipline

**Rule.** A small set of universal coding habits shape every file in every project.
Not all of them are hard rules. Together they catch entire classes of bug at
compile time or commit time, where the fix is cheap.

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
  genuinely cannot fail are the exception. §29 reaches the same rule from
  reading order: a `throw`'s handler sits in another file, a `Result`'s sits at
  the call site.
- **Parse at boundaries.** Every external input (env, network response, file
  content) goes through a schema (Zod / Valibot / Pydantic / serde) at the
  boundary. Never `JSON.parse` and cast.
- **Discriminated unions over boolean flags.** Express multi-state outcomes as
  tagged unions, not `{ found: boolean; failed: boolean }` bags. This is the
  type-level form of the "two zeros" distinction (§14, discriminated unions).
- **Branded types whenever possible.** Brand three things at the type level. A
  `string` that means a user ID. A `number` that means Unix seconds. A `bigint`
  that means cents. TypeScript: intersection with an opaque tag
  (`type UserId = string & {
  __brand: "UserId" }`). Rust: newtype pattern. Python: `NewType`. The compiler
  then refuses "you passed a `BookingId` where `UserId` was expected" and "you
  compared seconds to milliseconds". They cost nearly nothing and pay back
  *infinitely*, so reach for them by default.
- **Narrative order.** A file introduces each concept where it's first needed.
  Entry point at the top, callees below in call order, and guards discharged
  early, so the happy path reads straight down. §29 carries the rule and its
  tiebreaks.
- **Atomic conventional commits.** One logical change per commit. The atomic
  discipline is on you. CI enforces the type prefix, and so does a `commit-msg`
  hook on git-native repos (see §28 for why jj doesn't fire it).
- **Isolated-working-copy concurrent work.** Multiple agents, human or AI, work
  the same repo at the same time. Each work stream runs in its own **isolated
  working copy**: a **jj workspace** by default (see §28), or a git worktree in a
  non-jj repo. Cut it off **freshly fetched trunk**. Never cut it by a switch of
  the shared checkout, and never off a possibly-stale local `main` or trunk ref.
  The isolated copy covers the *code* alone. Repo metadata, PR numbers, and board
  state stay shared, and those remain the genuinely-shared steps to slow down on.
  One costs a command or two to spin up. To mutate another agent's working copy
  under their feet costs their whole run. **The isolation unit matters.** In a jj
  repo it's the workspace, not the git worktree. A git worktree isolates files,
  but not jj's single working-copy commit `@`. So jj run from a worktree still
  snapshots the *default* workspace, and concurrent agents collide.
- **Plan in prose, then act; gate on irreversibility, not on the human.** Design
  first. To design in prose costs a paragraph when you get it wrong, and to
  design in code costs more. Then proceed on reversible work and present the
  result. Pause only for the irreversible: a deploy, a force-push to a shared
  branch, data deletion, a message to a customer. This makes
  `pstack-principle-never-block-on-the-human` the default, and it retires the
  older habit of gating every change on the user before code.

**Why.** These habits compound. Each one alone is a small tax. Together they
shift large classes of bug from "discovered in production" to "caught at the
moment you typed them".

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
  is the famous case, and most languages have the same problem at some
  precision. In TypeScript, use `bigint` for whole units of the smallest
  denomination (cents, satoshis), or `decimal.js` and equivalents when you need
  arbitrary fractional precision.
- **In Postgres**: `numeric(p, s)` is the safe default. Money as `text` is a
  defensive option. It preserves original precision through round-trips, and it
  costs you in-DB filtering, sorting, and arithmetic. Pick `text` when you
  compute in the app alone, and `numeric` when the DB computes too.
- **Brand the money type**: `Cents`, `MoneyMinorUnits`. A `number` parameter
  read as cents when it meant dollars is the kind of bug that shows up on a
  wire transfer.

**Why.** These tiny rules are nearly impossible to retrofit. By the time the bug
shows up, you have a backfill problem on production data. It arrives as a
half-day duplicate in a timezone-naive timestamp, or a rounding error in a
billing run. To encode at the boundary turns the entire class of bug into a
compile error.

**Earn-its-keep.** A throwaway script that prints a chart and exits is allowed
to use floats. A throwaway script that prints "now" is allowed to use a naive
`Date`. State the choice explicitly when you deviate so future-you reading the
commit knows it was deliberate.

---

## §18. Testing philosophy

**Rule.** **Test behaviour. Climb the fidelity ladder.** Most production bugs
live at the seams: at integration layers, at I/O boundaries, and in the hand-off
between modules. A test that crosses a seam *and stays deterministic*
is worth ten unit tests of the components in isolation.

**The fidelity ladder** (prefer the higher rung wherever determinism survives):

| Rung | Tests | When to choose this |
|---|---|---|
| E2E | The full pipeline against a real or recorded external surface | Whenever determinism is achievable (recorded fixtures, fixed time, fixed RNG) |
| Integration | Two or more real modules talking, mocking only true external boundaries | When E2E is too slow or genuinely flaky |
| Unit | One pure function, no collaborators | When the behaviour is genuinely localized: domain math, parser shape, decay curve |

Unit tests have a place; they are **not the load-bearing layer**. A unit-test-heavy
suite passes while the system is broken. A function that returns `Result.ok({})`
satisfies a unit test even when its caller expects `{ status: "scored" }`. The
mock-heavy unit world hides exactly the seam bugs that production exercises.

**Concrete rules:**

- **Prefer fewer, longer workflow tests.** Following Kent C. Dodds's
  [testing principle](https://github.com/kentcdodds/kody/blob/main/docs/contributing/testing-principles.md#principles),
  treat each test like a manual tester's script: one explicit setup, then as
  many actions and assertions as the coherent journey needs. Multiple related
  assertions are a feature, not a smell. Don't split one flow merely to satisfy
  "one assertion per test". Split when the cases no longer share a workflow, or
  when one name can't describe the behaviour.
- **Test names are third-person verbs of observable behaviour.** `test("scores
  a 5-minute grocery at full credit")`, not `test("computeScore works")` or
  `test("calls decay")`.
- **Recorded fixtures over invented stubs** for external boundaries. A response
  shape you invented to match what you *think* the upstream returns tests
  your assumption, not reality. Capture one real response, commit it, parse
  it through the schema in tests.
- **No `.skip`, no `.only`, no env-guarded skips.** A test that needs a key
  fails loudly without the key.
- **Tests in the same commit as the behaviour.** A new mapping, a new error path,
  a new integration parser: each lands with its coverage.
- **Drive `Result` to its `err` branch in tests.** A `Result`-returning function
  whose tests only ever assert `isOk()` isn't tested.

**UI components: stories are the test layer for the view.** A UI component's
behaviour is mostly *how it renders in a given state*. **Storybook** is the right
tool to pin that. Virtually any non-trivial UI component ships with at least a
few stories, one per meaningful state:

- **Default**: realistic happy-path data.
- **Loading**: what renders while data is on its way.
- **Empty**: a legitimate "genuinely nothing there" result.
- **Error / unavailable**: the upstream failed. Empty and unavailable get
  *separate* stories. This is the "two zeros" distinction (§14) made visible.
- **Edge fullness**, where relevant: overflow content, long names, many items.

Light interactions in a story are fine, such as a play function that opens the
dropdown. A multi-step user *flow* is not what stories assert. That's an E2E
test, the top rung of the ladder. Stories answer "does this UI look right in
state X?". E2E answers "can the user get from A to B?".

Stories also double as a living catalog. A designer or product owner can
browse every state of every component without a run of the app, and without
an error reproduced by hand.

**Earn-its-keep.** Heavy mocking earns its keep only when the alternative is
genuinely non-deterministic and no recording strategy works. A third-party
system that doesn't replay sensibly counts, and so does time-sensitive logic
with no clock abstraction. It does *not* earn its keep merely because the
higher-fidelity test "would be slower". Slower-but-real beats fast-but-fake.

---

## §19. Commercial readiness and authorization

**Rule.** Every project declares whether it is **commercial-ready** or not. This
single setting changes defaults in security-sensitive areas, and **authorization**
is the main one.

The declaration lives in `CLAUDE.md` near the top, where the skeleton carries a
TODO marker. Set it deliberately at bootstrap and it prevents both modal
failures. One is a personal tool over-engineered with full RBAC scaffolding. The
other is a SaaS under-engineered with no authorization plan when the first
customer arrives.

**Defaults by readiness.**

| Concern | Personal / non-commercial | Commercial-ready |
|---|---|---|
| App-layer authorization | Required (even one user has a principal) | Required; **RBAC** is the default model |
| Audit logging | Not required | Required for auth decisions and data mutations |
| Authorization tests | Smoke tests | Each role × resource matrix tested explicitly |
| PII handling | Project's discretion | Documented in `CLAUDE.md` with explicit rules |

**App-layer authorization is the default.** Even a one-user project has a
"principal" and "permissions". Anything that isn't a query against fully
public data needs a check. RBAC adds structure when distinct roles exist.

**Why this matters at bootstrap.** A commercial-ready project that ships
without RBAC, RLS, and an authorization test matrix is the failure mode this
section prevents. Name the readiness up front and it becomes a single, visible
choice rather than a hundred unmade decisions.

**Earn-its-keep.** A non-commercial project that adopts the commercial defaults
is fine. They are not harmful, only optional for that flavor. A commercial
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
- A **surprising algorithmic choice** ("greedy match is intentional, because the
  recursive version was 3× slower on N>10k").

Don't write comments that:

- Explain *what* the code does. The code already does that.
- Reference the current task, fix, or caller ("added for issue #123"). That
  belongs in the commit message, and it rots as the codebase evolves.
- Restate the function signature in prose above the function.

**A comment that earns its keep is native.** To clear the bar above isn't enough.
The comment also has to sit where the reader will meet it. You read code at the
call site. An explanation the editor can't surface on hover lives somewhere you
aren't looking. A comment about a **symbol**, meaning a function, class, constant,
type, or field, therefore attaches to that symbol in the form the language's
tooling reads. That means a docstring in Python, and `/** */` or `///` in
TypeScript, Rust, Go, Java, and C#.

Four shapes fail this test. A banner ribbon above the symbol. A why-comment
orphaned from it by blank lines, decorators, or an import block. A file-top note
that explains one function buried below. A plain `//` where the language has a
doc form. Each fails even when its content is correct, because correct content
nobody hovers is a doc that rots unread. The fix is always to move it, never to
delete it.

The test is one question: hover the symbol in an editor, does this text come up?
Three things that look like violations aren't, and the rule doesn't reach them:

- **A *why* about one line or one branch, sitting on that line** inside the body.
  It's already where it's read, so there's no hover to miss. It is local, not
  floating.
- **Comments where no doc form reaches**: inside a function body, beside a
  config entry, on a shell / YAML / SQL / Dockerfile line, above a regex. Judge
  these on content alone.
- **A file- or module-level comment about the file or module.** Its subject is
  the file, so the file's top *is* its symbol.

**Commit messages.** Same rule, harder discipline. The subject line *is* the
*what* in compressed form (Conventional Commits). The body, when present,
explains the **why** and the **how-if-non-obvious**. Skip the body when the
subject is enough, and never pad it. Bad: "Updated `score.ts` to handle the new
mapping", which is what the diff already shows. Good: "Treat fast_food as
additive coverage, not parity", which says why the rule changed. The
subject-then-body shape is §29 applied to a commit: the conclusion first, the
detail underneath it.

**ADRs (Architecture Decision Records).** ADRs earn their keep as **temporary
discussion artefacts** for an in-flight decision:

1. A short doc captures the question, the options, the trade-offs.
2. The team / individual debates in PR comments or chat.
3. The chosen direction lands in the codebase (and in `CLAUDE.md` or
   `docs/PHILOSOPHY.md` if it's a durable convention).
4. The ADR is then **archived or removed**.

Permanent ADRs as a documentation strategy compete with `CLAUDE.md` and commit
history, and they rot. A decision recorded in 2023 and referenced by an ADR from
2021 is harder to track than the commits that implemented the change. Let the
code, the commits, and the durable docs speak instead.

**Earn-its-keep.** A permanent ADR earns its keep when the decision covers
something the code genuinely can't express. That means a vendor choice, a process
change, an SLA commitment, or a contractual constraint. Even then, ask first
whether it belongs in `CLAUDE.md` as a durable rule, or in `docs/PHILOSOPHY.md`
as a durable principle.

---

## §24. CI/CD discipline

**Rule.** **Green CI is non-negotiable**, with one partial exception for evals
(see §27). **The commit-msg hook is re-enforced server-side.** **Deploy on every
merge to `main`.** Per-PR full-stack preview deploys are a web/backend
prescription, in [`packs/web.md`](packs/web.md) §24.

**Why.** Tight feedback loops are how you ship multiple times a day with
confidence. A PR that can be clicked-through on a real preview deploy removes
the "well, it works locally" failure mode. A green-only `main` means `main` is
always deployable, which means deploys are routine and small (low-risk by
construction). Conversely, a CI that's allowed to be red sometimes erodes the
signal until nobody trusts it.

**Concrete defaults:**

- **CI runs on every PR**, before merge. Lint, type-check, deterministic tests
  (unit + integration + recorded-fixture E2E), and the commit-msg hook
  re-enforced server-side. Per §1, hooks aren't the obstacle. The client-side
  hook can be bypassed; CI can't.
- **Deploy on merge to `main`.** Trunk-based per §17. Every merge triggers
  production. Half-shipped features hide behind flags. Multiple deploys per day
  is the normal cadence, not a milestone.

**The one negotiable: evals (§27).** Deterministic tests must be green. **Evals
are non-deterministic by nature, so they must run on every PR but need not be
green** in the early life of an AI-integrated system. Lock the threshold in as
the system matures and the eval suite stabilizes. Details in §27.

**Earn-its-keep.**

- Manual approval gates on deploy-to-prod earn their keep in regulated industries
  and never elsewhere. Trust the test suite or fix the test suite.

---

## §26. Avoid double state: single source of truth, prefer consistency

**Rule.** The system has **one source of truth** for any given piece of state.
A second store, a derived index, a cache, or a replicated copy creates state that
someone must keep in sync. The burden is on that *deviation* to earn its keep.
Pick **strong consistency over availability** in the CAP trade for most products.

**Why.** Double state is the second-most expensive complexity tax in software,
after the §1 reach for a bigger architecture. Every duplicate is a sync problem
in waiting. The indexer falls behind, the cache goes stale, the replica diverges.
Bugs from these are notoriously hard to reproduce, because they depend on *which*
copy you read and *when*. The cheapest strategy is to avoid the duplicate: one
Postgres source-of-truth that everything reads.

**The CAP-theorem stance.** Most products aren't Google-scale. A brief drop in
availability during a partition or write spike costs little, and an
eventually-consistent system costs a lot to operate. We pick **C** (strong
consistency) over **A** (availability) for most things. An outage is explainable
and recoverable. Data corruption from eventually-consistent merges is not.

**Applications:**

- **Search.** Postgres FTS (`tsvector` + `tsquery`, `pg_trgm`, GIN indexes) is
  the default. A dedicated search index (Meilisearch, Typesense, OpenSearch,
  Algolia) duplicates the indexed data. It needs sync through CDC, dual-writes,
  or background reindexers, each with its own failure modes. It earns its keep
  only at a scale or a feature shape Postgres FTS genuinely can't serve. That
  means advanced relevance ranking, faceted search at enormous scale, or fuzzy
  multi-language. Most products outgrow their original search problem before
  they outgrow Postgres FTS.
- **Caching.** A cache is duplicate state. Eat the database read first. Reach for
  the cache only when a real, current, measured performance problem demands it.
  When you do, prefer an *invalidatable* cache over a merely *time-bounded* one.
  A Postgres `*_cache` table you control beats Redis with a TTL. The §11
  in-flight map protects against a stampede on egress without a second store.
- **Read replicas.** Same pattern as §3. They earn their keep on a measured
  read/write contention problem, never preemptively.
- **Materialized views.** Acceptable as cached aggregates the app already knows
  how to compute (§5 / §15). Not acceptable as the place where the app's actual
  data lives.

**When availability beats consistency.** Some products legitimately need it. A
content-delivery layer has to stay up under partition, so it eats the small
chance of stale content. A write path that absolutely must not block queues the
work and reconciles later via §22. When you make this trade, **name the boundary**
of the eventually-consistent zone, so the rest of the system stays strongly
consistent.

**Earn-its-keep.** Any deviation that creates double state names three things.
The current, felt problem that one source of truth doesn't solve. The sync
strategy *with its failure modes*. The operational cost. Same bar as §1.

---

## §28. Version control: jj (colocated)

**Rule.** The working copy is **Jujutsu (jj)**, colocated with git. A `.jj`
directory sits alongside `.git` at the repo root. git stays underneath as the
*interop and remote* layer: GitHub, `origin`, and the shared history teammates
see. jj drives all local version-control work on top of it.

This holds even when the wider team is on plain git. The shared history is git,
the local working copy is jj, and `jj git push` / `jj git fetch` bridge the two.
Most single-author projects can be jj end to end.

The operational rules live in `CLAUDE.md`: the verbs, where a workspace is cut,
how bookmarks are named, how a PR is pushed and merged. This section is why
they're shaped that way. Read it when one of them looks arbitrary, or when an
edge case falls outside it.

**The isolation unit is the workspace, not the worktree.** This is the
load-bearing reason jj changes §14 at all. jj has a *single* working-copy commit `@`
per workspace. A git worktree gives you a second checkout of the files but no
second `@`. So jj run from inside one snapshots and mutates the *default*
workspace's `@`.

Two agents that share an `@` therefore collide even though their files are
separate. Each one's edits land in the other's snapshot, and a commit picks up
the wrong directory's work. A branch isn't isolation either, because one
workspace has one working copy no matter how many branches point into it.
Isolation means a **`jj workspace`**, which carries its own `@`. All workspaces
share one repository, so a jj GUI still shows every `@` in a single graph.

**Snapshot model, not staging.** jj auto-snapshots the working directory into
`@` on every command. There is no index and no `git add`, and the consequences
ripple through the workflow:

- To split a change into atomic commits is a property of the commit verb, not a
  staging ritual you can get wrong.
- To fold a fix into an earlier commit is a first-class operation, not a
  `--fixup` dance.
- The reviewable diff of a branch is one command, because uncommitted edits
  already live in the graph.

git's staged / unstaged / committed three-way gather has no analogue here to
lose track of.

**Bookmarks are branches, and pushing is safe by default.** jj's named pointers
are *bookmarks*. The branch a PR opens from is a bookmark that points at your
tip commit. jj's push is force-with-lease by default. A rebase onto advanced
trunk and a re-push therefore carry no `--force` to fumble. jj has no PR concept.
The PR and the merge stay `gh`'s job, over the git commits jj pushed.

**jj does not fire git hooks.** A colocated repo's `pre-commit` and `commit-msg`
hooks do **not** run under `jj commit`. No staging step exists for them to hang
on. Those hooks normally give two guarantees: conventional-commit format,
and a green lint/typecheck/test gate. Both must move into the workflow itself and
into CI (§24). Don't assume a hook caught what jj silently skipped.

**Why.** jj makes the §14 habits cheap enough that they actually happen: small
atomic commits, isolated concurrent work, and fearless rebasing. The cost is one
sharp edge, the single-`@`-per-workspace model. Get it wrong, with a git worktree
where a workspace was needed, and it corrupts concurrent runs silently. The
workspace-not-worktree rule is named here, once, and that keeps every skill
downstream correct.

**Earn-its-keep.** A repo with no jj, where `.jj` is absent, falls back to git
worktrees and plain git. The skills are jj-native by default, so a non-jj repo is
the deviation, not the rule. Reach for raw `git` mutations inside a jj repo only
for something jj genuinely can't express. Nearly everything has a jj verb, and a
mix of the two is how divergent duplicate commits appear.

---

## §29. Narrative order

**Rule.** Code and prose introduce a concept at the moment it's needed, never
before. A file opens with its entry point and descends from there. The master
function comes first, then the functions it calls, in the order it calls them.
Depth in the file is the level of detail, and the reader picks where to stop.

Ordering makes that choice available. A **substantive top layer** is what makes
it real. A `main()` that reads `run(parseArgs(argv))` introduces nothing early
and teaches nothing either, so the reader has no choice but to descend. Both
halves are load-bearing: nothing arrives before its use site, and the first
screen says what the file does.

This is Clean Code's stepdown rule and Ousterhout's "reading order tracks
abstraction level" ([*A Philosophy of Software
Design*](https://web.stanford.edu/~ouster/cgi-bin/book.php), ch. 4). Both are
the same claim.

**Inside a function.** The happy path reads as one unbroken sequence down the
middle, and guards hang off it as short asides. This is why early returns win. A
guard introduces a case and discharges it immediately, so the reader drops it
from working memory and never meets it again. An `else` forty lines below forces
the reader to carry the condition through the whole body. The cost of nesting is
memory load, not indentation.

**Between functions.** Caller before callee, callees in call order. Three
tiebreaks settle the cases that ordering alone doesn't:

- A function called from two places goes at its **first** use.
- A helper with **three or more callers** sinks to the bottom as shared
  machinery. It stopped being part of one story.
- **Two peer entry points are two stories.** That's the file asking to be split,
  not an ordering problem to solve.

One consequence is concrete enough to change how you write TypeScript.
`function` declarations hoist and `const fn = () => {}` doesn't, so
caller-before-callee at module scope picks the declaration form for you. A
codebase that reaches for arrow consts at the top level gave up this rule
already, and usually didn't notice.

**Types** come before the types they reference. Same file, same rule.

**Prose.** Verdict first, then the evidence, then the caveats. Journalism calls
it the inverted pyramid. Three rules elsewhere in this document are instances of
it, and only now have a name. §21's commit subject carries the *what* over a
body that carries the *why*. `lazar-research` writes verdict-first. A standup
leads with what landed.

**The one inversion: a commit stack.** A stack can't be conclusion-first,
because you can't deliver before you scaffold. So the stack runs chronologically
and the **PR body is the conclusion-first layer over it**. The PR body is the
master function and the commits are the callees. A PR whose body lists its own
commit subjects skipped the top layer entirely.

**Why.** Bottom-up ordering, with helpers first and the entry point last, is
also perfectly consistent, and plenty of code reads that way. Need-to-know is
what rejects it. Bottom-up introduces every concept before anything needs it,
so the reader accumulates unattached machinery and learns its purpose only at
the end. Consistency isn't the property that matters. Direction is.

The other reason is that this is the reading-time form of a deep module (§32).
When the first screen is enough, the interface carries the weight and the
implementation hides below it. When it isn't, the file is shallow no matter how
it's ordered, and the fix is a design change rather than a reshuffle.

It also gives §14's **`Result` over `throw`** a second, independent argument. A
`throw` introduces a failure whose handler lives in another file, so the reader
meets a concept whose resolution is nowhere near it. A `Result` puts the failure
at the call site, where the reader already is. The type-safety argument and the
reading-order argument point the same way.

**Earn-its-keep.** Some files are flat collections with no story: a constants
file, a config file, a barrel of re-exports. Nobody stops reading them early
because there's no early to stop at, and forcing an order on them is theatre.
This section doesn't reach them.

Sort-order tooling wins where it's already in place, whether that's alphabetized
exports, a formatter, or a lint rule. Name the override rather than fighting it
file by file. Languages that require declaration before use invert the rule by
force, and that's the language's constraint, not a deviation to justify.

---

## §30. Felt outcome and writing

**Rule.** Work earns its place only when you can name the product outcome it
delivers, *and the user feels that outcome in the product*. It makes the product
more useful, more trustworthy, or more pleasant to use. The mechanics below apply
to whatever you write to describe that work, and to everything else you write.

**The gate is the outcome, not the category of work.** A refactor, a bug fix, a
performance change, and a feature can each qualify. Each can also fail. A
refactor that unblocks something you'd feel passes. A "feature" nobody notices
doesn't. Don't bank work that isn't felt. If a step takes 100 ms and 100 ms is
fine, 50 ms is not an issue.

Optimize something when its current state is a noticeable problem in use, not
before. Internal tidiness is not a product outcome, and that covers "cleaner",
"more testable", "best practice", and "more modern". Do that work inline while
you deliver something real. The project's own bar lives in its `CLAUDE.md`, in
lines like "the score stays trustworthy and explainable" and "the latency budget
stays under N". Read it and apply it as the test.

**This is a gate, not a writing rule.** The difference is the whole point.
Skills that write tickets and specs *frame* work around the user. They use lines
like "the problem the user faces, from the user's perspective" and "so that
`<benefit>`". That's a good habit, and it is not this rule.

Framing changes how you describe the work. Gating decides whether you write it down at all. A ticket
framed impeccably around a user who won't notice still fails. Do both. Frame the
work in the user's terms, and refuse to bank it when no felt outcome survives
the framing.

**Why.** Most candidate work exists because it occurred to someone, not because
it's worth doing. A tracker records that difference badly, because everything in
it looks equally legitimate once it has a title. So apply the gate at the moment
of writing, the last point where a no is still free.

To aim the gate at categories instead of outcomes is what breaks it in practice.
"Refactors don't count" is a rule you can follow while you ship nothing anyone
feels, and it forbids the refactor that would have. This is §1 at the altitude of
product work rather than architecture. `yagni-reviewer` enforces it on diffs and
plans.

**The mechanics apply to everything you write**: specs, ADRs, PRDs, issues, PR
bodies, docs, commit messages, chat.

- **No em dashes.** A comma, a period, or parentheses instead.
- **No LLM filler**: delve, moreover, furthermore, "it's worth noting",
  landscape, tapestry, robust, seamless, leverage, ultimately.
- **Active voice and contractions.**
- **One idea per sentence.** More than one comma is the tell; split it.
- **Be specific.** Say what happened, not what it "represents".
- **Conclusion first**, then the evidence, then the caveats (§29).
- **Sentence and paragraph caps**, and the tense and term rules under them, live
  in §33.
- **Cite primary sources and link them**: the official doc, the actual file, the
  PR, the issue, the ADR. A claim with no source is an opinion.
- **The project's own style guide wins** over every rule above.

**Voice is separate, and narrower.** The mechanics are floor-level clarity, so
they hold for a formal spec exactly as they hold for a PR comment. A personal
voice is a different thing: terse fragments, hedging, particular verbs, and a
set of calibration examples. It applies only to prose posted **as** a person,
meaning PR reviews, issue and PR comments, standups, and messages to teammates.
Not specs, not formal docs, not code. That voice lives in `CLAUDE.md`, where a
repo's writer defines it, and this section doesn't restate it.

**Why the mechanics don't exempt formal docs.** To exempt "formal documentation"
from writing rules cuts on the wrong axis. It costs the most exactly where the
writing matters most. A spec written in passive, sourceless, em-dashed
filler is harder to act on than a chat message written the same way. More
decisions hang off it. The voice is what's personal, not the mechanics, so
the voice is what the exemption should name.

**Earn-its-keep.** A house style that contradicts a mechanic wins on its own
turf. Three examples: a repo whose docs use em dashes deliberately, a changelog
format fixed by a tool, a public API doc with a tooling-mandated shape.
Name the source of the override.

This file used to claim that exemption for itself, on the grounds that its prose
predates the mechanic. §33 retired the claim and the file was rewritten to both
rules. The subagent argument in §33 is the felt outcome that the em-dash
exemption never had.

The gate has no such exemption. If you can't name what's better in the product,
the work isn't an issue. "We'll want it later" is the answer §1 already rejects.

---

## §31. Code style

**Rule.** The house style is Jane Street's, adapted idiomatically to the language
and framework in use. Most of it is already doctrine, so this section owns the
two ideas nothing else carries and points at the rest.

- **Code is organized around its domain types.** A type's construction,
  validation, transformation, and formatting live together. §4 makes this cut at
  module scale, by business domain rather than by technical layer, and this is
  the same cut one level down. A `Money` does not scatter its parser into
  `parsers/`, its arithmetic into `utils/`, and its renderer into `formatters/`.
- **Module shape follows §32.** Expose the operations a caller needs and keep
  representation and design decisions private wherever the language allows it.
- **Named or labelled arguments once positional order stops being obvious.** Two
  parameters of the same type in a row is the trigger. Branded types (§14) fix
  the other half of that problem, at the type level rather than the call site.

The rest of the style is doctrine already, and this section doesn't restate it.
Model the domain with explicit types, and prefer variants and tagged unions that
make invalid states hard to represent (§14). Handle cases exhaustively rather
than through boolean state bags (§14). Prefer immutable values, pure functions,
and explicit data flow (§14). Represent expected failure as typed data rather
than exceptions wherever the language supports it (§14, `Result` over `throw`).
Parse and validate external input at the boundary (§10).

Prefer readable output-oriented tests for structured transformations. Still
assert directly on values where rendering would lose information (§18).

**Why.** To organize around types puts "what can this thing be, and what can I
do to it" in one file. A reader then learns the type once instead of assembling
it from four folders. That's the same argument §4 makes about domains and §29
makes about reading order, applied to the unit a codebase gets navigated by. The
style is named after a house that ran it at scale for decades, which gives the
rules a shared reference. That is worth more than a list of preferences with no
source.

**Earn-its-keep, and the limit.** The style is a set of ideas, not a syntax.
Don't mechanically reproduce OCaml shapes in another language. Don't introduce a
wrapper around a single operation. Don't add an abstraction that has no current
caller, which §1 and §30 both reject already. Native language and framework
conventions win wherever they express the same idea more clearly. A framework
that demands a class or a throw is interface compliance, not a deviation (§14).

---

## §32. Complexity and deep modules

**Rule.** Complexity that cannot be removed belongs behind the smallest honest
interface that can contain it. Optimize the complexity of the whole system, not
the apparent simplicity of one implementation. A module earns depth when its
callers get substantial behaviour without learning the decisions, sequencing,
representation, or failure handling inside it.

Complexity shows itself through three symptoms:

- **Change amplification.** One logical change requires edits in several places.
- **Cognitive load.** A caller must hold unrelated details in mind to use the
  module correctly.
- **Unknown unknowns.** The caller cannot tell which details matter or where a
  change will have effects.

These symptoms are interface costs. Implementation complexity is local to one
module; interface complexity is paid again by every caller and every test. Shape
modules so the cost stays local:

- **Pull complexity downward.** The module with the knowledge needed to handle a
  decision owns that decision. Callers should state what they need, not coordinate
  the module's internal steps.
- **Hide design decisions, not only data.** Representation, algorithms, ordering,
  policy, and translation rules stay behind the interface. When the same decision
  appears in two modules, information leaked.
- **Prefer depth over pass-through layers.** A wrapper that exposes nearly every
  operation or parameter of what it wraps adds another interface without hiding
  complexity. Delete it or give it enough responsibility to simplify its callers.
- **Generalize across current cases.** When several present use cases share one
  mechanism, prefer that mechanism over a separate special-purpose path for each.
  This is not permission to add extension points for future callers. §1 and §30
  still require a current need.
- **Define errors out where semantics allow it.** An operation that can make a
  case valid, idempotent, or a no-op should do so, where no information is lost.
  That beats an interface where every caller handles the error itself. Real
  operational failures and invalid input remain explicit typed results (§14).
- **Design consequential interfaces twice.** Compare at least two meaningfully
  different shapes first. This applies to an interface that many callers will
  learn, or that will cost a lot to change. The first plausible design is
  evidence, not a default winner.

`matt-codebase-design` owns the operational vocabulary and process for applying
this section: **module**, **interface**, **depth**, **seam**, **adapter**,
**leverage**, **locality**, the deletion test, and design-it-twice. This section
owns why that process exists. The distinction follows John Ousterhout's
[*A Philosophy of Software Design*](https://web.stanford.edu/~ouster/cgi-bin/book.php):
the primary job of design is managing complexity.

**Why.** A module can be simple in itself and still make the system harder. It
forces the caller to sequence operations, translate representations, repeat
policy, or recover from cases it could absorb. Move that work behind one
interface and the implementation grows larger. But the next change then needs
less knowledge and fewer places. That is a net simplification. §1 rejects
complexity that hasn't earned its keep. This section concentrates and hides the
essential complexity that remains.

**Earn-its-keep, and the limit.** Depth is not an excuse to build a framework.

- A broader interface serves named current callers, never hypothetical ones.
- Unrelated domains do not merge merely to reduce method count. The interface must
  hide one coherent body of knowledge.
- Framework adapters and true external boundaries may be shallow when translation
  is their whole honest responsibility.
- Hidden behaviour must not become surprising behaviour. Security decisions,
  destructive effects, cost, and material performance characteristics stay
  visible when callers need them to use the module correctly.
- A design-only refactor still clears §30's felt-outcome gate. Improve depth inline
  with current product work, or against a named architecture problem that is
  already slowing changes or allowing bugs.

---

## §33. Controlled language

**Rule.** Everything written follows the sentence mechanics of
[**ASD-STE100 Simplified Technical English**](https://www.asd-ste100.org/). Six
rules, and they hold on every surface: chat, code comments, docs, specs, issues,
PR bodies, commit messages, and prose posted as a person.

- **Short sentences.** 20 words for an instruction, 25 for description.
- **Short paragraphs.** One topic, and six sentences at most.
- **Simple tenses only.** Infinitive, imperative, simple past, simple present,
  simple future, and the past participle as an adjective. Not the perfect, and
  not the progressive.
- **No `-ing` word as a verb.** It is a noun, or it is part of one.
- **Noun clusters stop at three words.**
- **One term per concept.** The same thing keeps the same name every time. Do
  not vary a word for elegance. §30 bans a list of filler words; this bans the
  second word for a thing you already named.

**What the rule does not take.** STE also ships a dictionary of about 900
approved words, and the register of a maintenance manual. Neither lands here.
§30 requires contractions, and `CLAUDE.md`'s voice requires prose that sounds
spoken. The STE register fails both tests, and the six mechanics above fail
neither.

The dictionary was never the obstacle. Domain vocabulary is already safe under
STE's own Technical Name and Technical Verb rules, so `idempotent` and `rebase`
survive it. The register is what conflicts, so the register is what this rule
drops.

**Why.** Two reasons, and the second carries the weight.

The first is a limit. §30 already asks for one idea per sentence and plain
words, but it sets no number. "One idea" is a judgment call, and a judgment call
drifts under pressure. A word count does not drift.

The second is the subagent. A subagent inherits neither `CLAUDE.md` nor these
rules. It opens a `§N` cold and acts on what it reads, once, with no chance to
ask. A rule that parses on the first read is a rule it applies correctly. A
30-word sentence with three subordinate clauses is where it guesses instead.
That is a felt outcome under §30, not a matter of taste: the rules get followed
more often.

**Earn-its-keep.** Five things sit outside this rule. None of them is a
deviation to justify.

- **A quotation keeps its original wording.** Calibration examples, cited
  sources, and error text get quoted, never rewritten.
- **Code is not prose.** Identifiers, command lines, and code blocks are exempt.
- **A heading, a table cell, and a list label are not sentences.** The caps
  reach running prose only. The paragraph cap reaches a paragraph, so a long
  list item is judged on its sentences, not on its count of them.
- **The two caps pull against each other.** Split a 40-word sentence into three
  and the paragraph gets three sentences longer. When they conflict, the
  sentence cap wins and the paragraph splits.
- **A source that fixes its own format wins.** §30 already grants this.
- **Correctness beats the cap.** A sentence that needs 30 words to stay true
  keeps them. Split it when a split preserves the meaning. Never shave meaning
  to reach a number.

This document was rewritten to the rule when the rule landed, rather than left
to converge. §30's earn-its-keep declined that work for its em dashes, because
the rewrite had no felt outcome. The subagent argument above is that outcome,
and it did not exist when §30 was written.

---

## What this document is not

- A roadmap. Sections aren't features; they're principles.
- A checklist. The principles need judgment; that's what the "earn its keep"
  language is for.
- A guarantee. If a future project genuinely needs Kafka, you reach for Kafka
  and you write down why. The system here makes the deviation deliberate, not
  forbidden.

Drift policy: this document is the canonical source. A project's `CLAUDE.md` or
`.claude/` configuration can disagree with it. That disagreement is either a
project-specific earn-its-keep deviation, with a written reason, or a template
drift to backport to
[`lazar-harness`](https://github.com/mauricedesaxe/claude-harness-template).
