---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.sql"
  - "package.json"
  - "pyproject.toml"
  - "Cargo.toml"
---

# Technical defaults

This pack holds concrete technology choices. The spine holds durable engineering
principles. Skills hold procedures and executable checks enforce what can be enforced.

These choices are defaults, not universal rules. Prefer mature technology with broad
production use, stable maintenance, good documentation, and a large hiring pool. A
newer or narrower tool needs a specific benefit for the current product.

## §2. Languages

**Rule.** Use a language and toolchain that preserve types through the application.
Prefer TypeScript to JavaScript. In Python, parse external data with Pydantic or an
equivalent typed schema. Use each ecosystem's static checks at their strict setting.

Pick the language for the problem and its library ecosystem. Do not treat TypeScript
as the default over Python, Go, Rust, or another suitable typed language. Keep one
primary language where practical, because each extra toolchain adds maintenance.

## §3. Deployment topology

**Rule.** Keep one deployable application until a current boundary requires another.
The application can run as a long-lived process or on a serverless platform. Choose
from cost at the expected traffic level, workload duration, runtime limits, data
location, local development, and operational fit.

Push back on microservices, not on a specific runtime model. A second service needs a
real ownership, scaling, isolation, or deployment boundary. Idle-cost savings alone
can make serverless the simpler choice for low-traffic software.

## §4. Modular monolith

Keep application code organized by business domain. A deployment model does not
change that boundary. Cloudflare Workers, containers, and traditional servers can all
host a modular monolith.

## §5. Data stores

**Rule.** Pick one boring, reliable authoritative store that fits the data and access
patterns. Do not add a second database for novelty or hypothetical scale.

- **Postgres** is a strong default for relational data, transactions, joins, and
  conventional server applications.
- **Cloudflare D1** is a good option for SQLite-shaped workloads that benefit from
  low operations cost and close integration with Workers.
- **MongoDB** is a good option when the domain is naturally document-shaped and most
  operations load or replace aggregate documents.

Judge a store by correctness, operational history, backup and restore support,
migration tooling, local development, query needs, and platform fit. Keep durable
domain data exportable. Avoid a database abstraction that erases useful native
features only to preserve a hypothetical migration.

## §6. Hosting

**Rule.** Use a managed platform before operating infrastructure yourself. Cloudflare
is worth checking for Workers, Pages, D1, R2, Queues, DNS, CDN, security, and related
services. Managed container platforms such as Railway, Render, and DigitalOcean App
Platform remain good choices for long-running processes.

Choose the smallest managed platform that runs the workload well. Kubernetes, a
self-managed VM fleet, and extensive infrastructure-as-code need a current operational
or compliance reason.

## §7. Runtime model

**Rule.** Choose serverless, edge, or long-running compute case by case.

- Prefer serverless or edge compute for low or bursty traffic, short requests, global
  latency, and workloads that fit the platform limits.
- Prefer a long-running process for sustained compute, long jobs, unrestricted
  runtimes, large connection pools, or in-process coordination.
- Put compute near the authoritative data when repeated data round trips dominate
  request latency.

Do not reject Cloudflare Workers because they are serverless. Do not choose them only
because they remove a server. Compare the actual workload and total operating cost.

## §8. Web application architecture

**Rule.** Prefer established frameworks with deep ecosystems. React is the default UI
library when the product needs a component framework. Choose a newer framework such
as Svelte only when it gives the current product a concrete advantage.

Use the smallest application shape that fits.

- A React SPA fits highly interactive products without SEO-critical application pages.
- React Router or another established full-stack React framework fits server-rendered
  products and can target either a server or a compatible serverless runtime.
- Astro fits content-heavy sites with limited client interaction.

Follow the framework's supported deployment path. Do not split frontend and backend
deployments without a real team, security, or release boundary.

## §9. Cloudflare

**Rule.** Consider Cloudflare as a broad application platform, not only as a CDN.
Evaluate DNS, CDN, TLS, DDoS protection, Pages, Workers, D1, R2, Queues, and other
services that match the product.

Cloudflare's integrated platform and low idle cost can remove operational work. Keep
the same selection bar as any vendor. Confirm runtime limits, data semantics, local
development, observability, export paths, and lock-in before adoption.

## §10. End-to-end type safety

Keep frontend-to-backend boundaries typed through generated clients, shared schemas,
or framework-native request types. Parse external data at the boundary. A shared
language can reduce this cost, but it is not required.

## §12. Managed observability

**Rule.** Buy observability before building or self-hosting it. Capture structured
logs, traces, and errors through a managed service. Keep errors unsampled.

Sentry and Better Stack are proven general options. Use an AI-specific service such as
LangSmith when its traces, evals, and cost views fit the AI workflow. Do not send the
same signal to several tools without a named use for each copy.

## §15. Database discipline

Keep business rules in application code unless the database must enforce a hard data
invariant. Use the selected database's native indexes, transactions, constraints, and
query language rather than forcing every store through one lowest-common-denominator
interface.

Test migrations against the real database engine. Use staged migrations when a change
must remain compatible with live readers or writers. The exact migration strategy
depends on the store and deployment model.

## §17. Feature flags

Use flags for staged delivery, experiments, and kill switches. Store simple flags in
the application's existing authoritative store. Use a managed flag product when its
targeting, audit, or experimentation features solve a current need. Set a removal
condition for temporary flags.

## §19. Commercial readiness and authorization

Commercial software requires application authorization, audit records for sensitive
changes, tenant-isolation tests, and documented PII handling. Use database-level
authorization such as Postgres RLS when the selected store supports it and the extra
layer justifies its operational cost. Do not assume every database offers the same
mechanism.

## §20. Frontend defaults and local-first

**Rule.** The frontend feels native, fast, and keyboard accessible. Aim for responses
under the Doherty threshold of about 400 ms when the user expects direct feedback.

Start with React's built-in state and browser primitives. Add TanStack Query for
non-trivial server state. Add a form or local-state library when the application has
enough complexity to benefit from it. Keep view state in the URL when users need
reload, history, or shareable links.

Use optimistic updates when reversal is safe. Show real network waits honestly. Make
primary actions easy to reach by keyboard and pointer.

## §22. Background work

Move lengthy or failure-prone work out of the request path. Use the hosting platform's
managed queue or scheduler when it fits. A database-backed queue remains a good choice
for a long-running application. Cloudflare Queues and Workflows can fit a Workers
application.

Every retried job must be idempotent. Keep retry policy with the job. Test the seam
from the enqueue action through final state where deterministic tests allow it.

## §23. Object storage

**Rule.** Use managed object storage for uploads and generated binary assets.
Cloudflare R2 is a strong default, especially within a Cloudflare deployment. S3 and
other mature S3-compatible services are also valid choices.

Keep metadata in the authoritative application store. Upload large files directly
with short-lived signed URLs when the provider supports them. Do not route large byte
streams through application compute without a product reason.

## §24. CI and deployment

Run deterministic checks on every pull request. Test migrations against the selected
database engine. Provide a preview deployment when the platform can do so without
large setup or data costs. Deploy small changes from a green main branch.

## §25. Realtime delivery

**Rule.** Choose polling, server-sent events, WebSockets, or webhooks from the event
shape. No transport is the universal default.

- Poll when updates can arrive at an interval and a cacheable read is cheap.
- Use server-sent events for one-way streams from server to browser.
- Use WebSockets for bidirectional traffic or latency that polling cannot meet.
- Use signed, idempotent webhooks for inbound server-to-server events.

Account for reconnects, ordering, backpressure, authentication, observability, and
platform limits for any persistent connection.

## §34. UI and UX design principles

**Rule.** Two layers guide the interface. Visual design makes it readable and
hierarchical. Cognitive fit makes it match how the user thinks. Both are defaults,
not matters of taste.

The primary sources are *Refactoring UI* by Adam Wathan and Steve Schoger, and
[*Laws of UX*](https://lawsofux.com) by Jon Yablonski.

### Visual design

- **Hierarchy is a budget.** Spend size, weight, and color on the few things that
  matter. Most of a page stays quiet.
- **Space does the grouping.** Related items sit close. Unrelated items sit apart.
  Proximity carries relationship faster than a heading.
- **One accent, many grays.** Use one main hue and lean on grays for the rest. Use
  borders and backgrounds before saturated color.
- **Depth signals interaction.** Use elevation or another deliberate visual cue to
  mark interactive elements.
- **Type stays readable.** Body text has sufficient size, contrast, and line height.
- **One primary action per view.** Distinguish action levels by more than color.

### Cognitive fit

- **Hick's Law.** Decision time grows with the number of options. Cut choices when
  the user is under load.
- **Fitts's Law.** Target time depends on target size and distance. Make primary
  targets large and near.
- **Jakob's Law.** Users expect the product to work like products they know. Follow
  conventions unless a real product need says otherwise.
- **Miller's Law.** Working memory handles a limited number of items. Group long
  lists into meaningful chunks.
- **Serial position effect.** People remember the first and last items best. Put key
  actions at an end.
- **Von Restorff effect.** A distinct item is easier to recall. Make the important
  item visibly different.
- **Principle of proximity.** Nearby items appear related. Use spacing to show groups.
- **Aesthetic-usability effect.** People perceive attractive products as easier to
  use. Polish can reduce perceived friction.
- **Doherty threshold.** Responses under about 400 ms help users stay in flow.

A deliberate visual style can reinterpret these principles. It does not remove the
need for hierarchy, grouping, readable type, and clear actions.
