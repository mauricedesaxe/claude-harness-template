# CLAUDE.md

Guidance for Claude Code (and any other agent) working in this repository.

The bar for changes is: <!-- TODO: one sentence — the load-bearing quality the project
must preserve. Examples: "the score stays trustworthy and explainable", "the latency
budget stays under N", "the export is reproducible". This is the bar every plan,
diff, and review is judged against. -->

**Commercial readiness:** <!-- TODO: yes / no. See PHILOSOPHY §19. Set to "yes" if
this project handles other people's data, runs in production for paying users, or
otherwise has data-leak as an unacceptable failure mode. "yes" makes RBAC, Postgres
RLS, audit logging, authorization-matrix tests, and explicit PII handling required
defaults rather than optional, and turns on the security-reviewer at review time. -->

## Philosophy

This project follows the durable conventions in `docs/PHILOSOPHY.md` and its domain
packs — the **why** behind the rules below, and the canonical source when this file is
silent or ambiguous. The Hard rules section is the compressed, always-in-context form;
the philosophy is the long form. The split:

- [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md) — the **paradigm-agnostic spine** (any
  codebase): §1 Earn its keep, §2 Languages, §4 Modular monolith, §10 End-to-end type
  safety, §11 API integration primitives, §12 Observability, §13 Outsource the non-core,
  §14 Code-level discipline, §16 Value-type discipline, §18 Testing, §19 Commercial
  readiness & authorization, §21 Documentation, §24 CI/CD, §26 Avoid double state,
  §28 Version control.
- [`docs/packs/web.md`](docs/packs/web.md) — the **web/backend pack**: §3 Single-instance,
  §5 Postgres only, §6 Managed platforms, §7 No serverless/edge, §8 Web architecture,
  §9 Cloudflare, §15 Database discipline, §17 Feature flags, §20 Frontend & local-first,
  §22 Background jobs, §23 File/blob storage, §25 Realtime, plus the web specifics of §2,
  §4, §10, §12, §19, §24.
- [`docs/packs/ai.md`](docs/packs/ai.md) — the **AI/LLM pack**: §27 AI/LLM integration.

`§` numbers are stable IDs; the spine's Section index records which file each lives in.
This is a web-flavored project, so it applies the spine plus both packs. Where this file
overrides the philosophy, the override must name a specific project reason that clears §1.

## Codex

`AGENTS.md` is the Codex bridge for this repo. Keep durable project rules here in
`CLAUDE.md`; `AGENTS.md` stays thin and points Codex back to this file,
`docs/PHILOSOPHY.md`, and the `.claude/skills/` workflows.

## Project status

<!-- TODO: a sentence or two on where the project is — greenfield, in production,
mid-migration. Delete if not useful. -->

## Architecture (this project)

<!-- TODO: the project's actual modules/domains, deployable shape, and any deliberate
deviation from the §3/§5/§6/§7 defaults (each with its earn-its-keep reason per §1).
Until filled, the defaults below apply: single deployable, one Postgres, modular
monolith organized by business domain, managed Docker target, no serverless/edge. -->

## Runtime

- **Language: TypeScript** by default (§2). Python / Rust may be used only where they
  specifically earn their keep — name the reason here if so.

## Skills

Project skills live in `.claude/skills/<name>/SKILL.md` and are invoked as `/<name>`
(Claude Code) or `$<name>` (Codex). The harness lists them each session; this table is
the durable "when to reach for which".

| Skill | Reach for it when |
|---|---|
| `work` | Picking up a GitHub issue — workspace off latest main → plan → adversarial plan review → user approval → implement → `/review` → triage → `/ship`. The default end-to-end workflow. Supports `auto`. |
| `research` | Exploring an issue's open questions **before** committing to an approach — deep open-web + codebase research, live probes, a cited verdict in `docs/research/`. Never closes the issue; writes only research-grade code. Supports `auto`. |
| `commit` | A logical chunk of work is done — record it as atomic conventional commits, as you go. |
| `review` | Before commit/push/merge — runs the reviewer agents against the diff and reports in chat. Never posts to GitHub. |
| `capture` | An idea/feature/bug surfaces mid-flow — file it as a GitHub issue, but only if it clears the felt-product-value bar. |
| `ship` | Land work on `main` end-to-end — branch/commit/push/PR/CI-wait/rebase-merge, running only the missing steps. |
| `setup` | A fresh clone — install deps, bring up the stack, set keys, verify build + tests. |
| `neobrutalist-pop` | Building or styling any UI — the neo-brutalist look (thick borders, hard shadows, candy accents). |
| `lazar-tldraw` | Talking through a diagram or a low-fi UI wireframe — system/API/DB diagrams and product sketches on a tldraw canvas (needs `@kitschpatrol/tldraw-cli`). |
| `lazar-standup` | Writing the daily 3 Ps (Progress / Problems / Priorities) — reconciles merged PRs, tracker issues, and unpushed local work into a post in my voice. |
| `shape` | A raw idea is really a multi-issue effort — shape it into a bettable milestone (felt outcome, appetite in sittings, in/out scope, the rabbit hole). Can conclude "don't build it". |
| `bet` | Committing a shaped milestone to the active set with a cutoff — runs the circuit breaker on expired bets first. Hard WIP cap of 1–3. |
| `prune` | The backlog is bloated — cull only the genuinely dead, surface dups. Read-then-recommend; never closes without approval. |
| `next-task` | "What should I work on next" — a ranked shortlist from the board, open issues, and roadmap docs. |
| `viability` | "Is there a market / would anyone pay for X" — market/impact assessment before betting (TAM/SAM/SOM, competitor table, CAC/LTV, verdict-first). |
| `codebase-report` | "How big/healthy is this / what shipped lately" — a two-perspective (business + engineering) snapshot over a metrics collector. |

The **initiative layer** (`shape` / `bet` / `prune`) runs one altitude up from issues, on
GitHub milestones — the Shape Up model (PHILOSOPHY §29). Nudge toward it when a raw idea is
really a multi-issue effort, or when reaching for a fourth active bet.

**Autonomous mode (`auto`).** `work` and `research` each take an optional `auto` opt-in
(the keyword — `/work 12 auto` — or clear "let it rip" / "review at the end" intent) that
collapses the mid-flow user gates into self-decisions and keeps a **single review gate at
the very end**, right before the outward step (the merge for `work`, the merge + issue
comment for `research`). The reviewer agents still run and genuine blockers still stop. No
opt-in → the normal gated flow; borderline wording → ask once.

The reviewer **agents** are run *by* skills, not invoked directly. Three install globally,
because they judge habits that hold in every repo:

- **At plan time** (run by `work`): `yagni-reviewer` against the plan text, before code exists.
- **At diff time** (run by `review`): `git-hygiene-reviewer`, `yagni-reviewer`, and
  `clarity-reviewer`, always.

Every other reviewer judges a repo against *its* standards, so it lives in that repo's own
`.claude/agents/` — a `code-reviewer` that knows the module boundaries, a `payments-reviewer`,
a `security-reviewer` if the repo is commercial. `review` picks them up automatically and runs
them alongside the global three.

### Engineering skills (`matt-*`)

Alongside the workflow skills above, the `matt-*` family (Matt Pocock's engineering skills)
installs as a distinct **engineering-skills layer** — reach for these mid-task, not as an
end-to-end workflow. They keep the `matt-` prefix, cross-reference each other by that name,
and bring their **own** review sub-agents (they don't use the reviewer agents above).

| Skill | Reach for it when |
|---|---|
| `matt-wayfinder` | Orienting in unfamiliar code before you plan or change it — map the module(s), entry points, data flow. |
| `matt-grilling` / `matt-grill-with-docs` | Stress-testing a plan/design Socratically before building; `-with-docs` when the question is "does this API actually behave the way the plan assumes". |
| `matt-to-spec` / `matt-to-tickets` | Turning a rough idea into a spec, or a spec into tickets. |
| `matt-tdd` | Building a checkable-contract change test-first (red-green-refactor). |
| `matt-implement` | A structured implementation pass against a spec. |
| `matt-diagnosing-bugs` | A bug/regression — find the root cause before planning a fix. |
| `matt-code-review` | A two-axis (standards + spec) review of a diff against a fixed point. |
| `matt-domain-modeling` / `matt-codebase-design` | Pinning domain terms / designing a deep module's interface. |

Plus `matt-prototype`, `matt-diagnosing-bugs`, `matt-triage`, `matt-handoff`,
`matt-improve-codebase-architecture`, `matt-research`, `matt-resolving-merge-conflicts`,
`matt-teach`, `matt-ask-matt`, `matt-grill-me`, `matt-writing-great-skills`.

They're **issue-tracker-agnostic**: run `/matt-setup-matt-pocock-skills` once per repo — it
writes `docs/agents/issue-tracker.md` (GitHub / GitLab / local / other) that the rest read
from.

## Tracker resolution

Any skill that needs to know which tracker owns a repo resolves it in this order. **Asking is
a last resort, and it happens at most once per repo**:

1. **The repo's own config** — `docs/agents/issue-tracker.md`, where the repo permits such a
   file. This one is written by `/matt-setup-matt-pocock-skills`.
2. **The machine-local note** (below), for shared work repos where committing harness config
   isn't an option.
3. **Inference** — the remote host, issue-key patterns in branch names and commit messages,
   and which tracker MCPs are connected.
4. **Ask** — and **write the answer to the note**, so the same question is never asked twice.

### The machine-local note

One markdown file per repo, keyed by the git remote, at:

```
~/.lazar-harness/repos/<host>/<owner>/<repo>.md
```

Derive the key from `git remote get-url origin`, normalised: drop the scheme, any user
(`git@`), and the trailing `.git`, so `git@github.com:iconicshift/platform.git` and
`https://github.com/iconicshift/platform` both key to
`~/.lazar-harness/repos/github.com/iconicshift/platform.md`. A repo with no remote has no key,
so it gets no note — infer, and ask if you must, but there's nowhere to remember the answer.

It's a plain file under `$HOME`, read with `cat` and written with `mkdir -p` + a redirect.
`$HOME` is the one thing Claude Code, OpenCode, and an Open-Inspect sandbox all agree on. The
note lives under neither `~/.claude/` nor `~/.config/opencode/`, so no runtime owns it, and
Claude Code's auto-memory is **not** used — auto-memory would cover Claude Code alone and leave
the other two asking every session forever.

The note records what the harness must not guess at:

```markdown
# iconicshift/platform

- tracker: Linear, team ICON, via `mcp__linear__*`
- issue key: `ICON-<n>`
- vcs: jj, colocated with git
- standup: Slack, #eng-standup

## Conventions

- A system design doc lives in the Linear issue, not as an ADR in the repo. An ADR is a
  different artifact with a different lifecycle (§21: a temporary decision record, archived
  once the decision lands).
```

Add a convention the moment a repo teaches you one. Editing the note by hand is expected — it's
mine, not the agent's.

## Hard rules

These are the always-in-context, enforceable form of the philosophy. The `§` ref points
at the full reasoning; read it when a rule needs its why or feels wrong for this repo.

- **Earn its keep** (§1). Any architectural complexity beyond the single-instance /
  Postgres-only / managed-platform / no-serverless defaults must clear §1's bar first.
- **Outsource the non-core; own the data** (§13). Pay for the managed solution unless the
  problem *is* the core competency; when a library-on-your-backend and a data-holding SaaS
  both exist, prefer the library (e.g. BetterAuth over hosted identity).
- **Single deployable, modular monolith, Postgres only** (§3/§4/§5). One app + one Postgres;
  code organized by business domain, not technical layer; SQLite/Kafka/Redis/Mongo rejected
  by default. Postgres also handles queues and aggregates.
- **Managed Docker platform, no serverless/edge, Cloudflare CDN** (§6/§7/§9). Dockerfile +
  push; the app is a long-running owned server close to the DB; Cloudflare for CDN/DNS/TLS.
- **Conventional commits, atomic, one logical change each.** Types:
  `feat|fix|refactor|chore|docs|test|style|perf|ci|build|revert`. Don't fold unrelated
  cleanup into a feature commit.
- **No `Co-Authored-By` trailer / AI-attribution line** on any commit.
- **Never bypass hooks.** No `--no-verify`. A failing hook is the bug, not the obstacle.
- **Env vars only via the validated config module** (one module, schema-validated, frozen at
  startup; app refuses to start on bad config). API keys are config, never inline.
- **Structured logging via child loggers.** `log.info({ <fields> }, "<event>")`, not
  interpolated strings. Never log API keys.
- **Observability from day one** (§12). Structured logs + distributed traces ship with the
  first deploy. Errors are never sampled out; W3C `traceparent` via OpenTelemetry.
- **Fail loud; distinguish two zeros.** No silent `catch`. A legitimate empty result is not
  the same as a failed fetch — a failed upstream surfaces as `unavailable`, never as empty.
- **No `throw` in app code — return a `Result<T, E>`** (neverthrow/equivalent), with a typed
  discriminated-union error. `_unsafeUnwrap` is tests-only.
- **Branded types wherever possible** (§14/§16). Brand IDs, money (`bigint`/cents), and time
  units at the type level. Nearly free, catches whole bug classes.
- **End-to-end type safety** (§10). Every network response parses through a schema at the
  boundary; front↔back typed via tRPC / OpenAPI codegen / native loader typing — never an
  untyped fetch wrapper.
- **External integrations stack five primitives** (§11), in order: `inFlight → rateLimiter →
  semaphore → breaker → withRetry`. Functional factories, consumer-supplied policies,
  in-memory by default, each returning a `Result`. No ad-hoc `Promise.all` / `setTimeout`
  throttles / inline retry loops over external calls.
- **Database stores data; app owns the rules** (§15). No business logic in stored procedures,
  triggers, or non-trivial `CHECK`s. Migrations reversible by default; invasive changes go
  expand → backfill → contract.
- **Value types at the boundary** (§16). `timestamptz` + ISO-8601 UTC on the wire (avoid Unix
  numeric timestamps; brand if unavoidable); money as `numeric`/`bigint`/`decimal.js`, never
  float; durations branded with units.
- **Feature flags live in our Postgres** (§17). No flag SaaS. Trunk-based; half-shipped
  features hide behind a flag defaulting off, with a named removal target.
- **Background jobs are idempotent** (§22). Postgres-backed queue (Graphile Worker default),
  workers on the web-tier machine, cron in code. Every job re-runs safely.
- **Track every metered API call in Postgres** (§27). Per user / request / model, with token
  counts + cost estimate + latency. Hard line for AI features and any metered API.
- **Avoid double state** (§26). One source of truth per piece of state; caches, search
  indexes, replicas, domain-logic materialized views each earn their keep on a named problem.
- **File/blob storage: Cloudflare R2 + pre-signed URLs** (§23). Bytes in R2, paths in
  Postgres; uploads go browser → R2 direct; processing/scanning run as background jobs.
- **Test behaviour; climb the fidelity ladder** (§18). Prefer the highest-fidelity
  deterministic test; recorded fixtures over invented stubs; unit tests are a tool, not the
  load-bearing layer. Drive `Result` to its `err` branch. New behaviour ships with tests in
  the same commit. No `.skip`/`.only`/env-guarded skipping.
- **Comments and commits say *why*, not *what*** (§21). Default to no comments; add one when a
  non-obvious invariant, workaround, or surprising choice lives there.
- **Modules are domain models.** A file is named for the subject it owns, not a role
  (`utils.ts`, `helpers.ts`). If the best name is "miscellaneous", the design hasn't landed.
- **No `as any`, no non-null `!`.** If you reach for them, the model is wrong — fix it.
  Discriminated unions over boolean flags; `as const` for domain keys/weights/error codes.

For commercial-ready projects, §19 additionally requires app-layer RBAC, Postgres RLS as a
second policy layer, audit logging on every authz decision and mutation, an explicit
role × resource test matrix, and tested tenant isolation. App-layer authorization is required
for every project regardless.

## Issue triage

Open issues live on the project's [GitHub project board](<!-- TODO: board URL -->) — a
Kanban over GitHub Issues. **Labels describe *what* an issue is** (stable, exactly one
`area/*` each); **the project's `Status` field describes *where in the flow* it sits**
(fluid). No priority labels — ordering within a column is the priority.

| Status | Means |
|---|---|
| Backlog | Captured, not yet scoped. Default landing column for `capture`. |
| Ready | Scoped, unblocked, actionable. Top of column = next up. `work` pulls from here. |
| In progress | Actively being worked on (usually one item). |
| Blocked | Waiting on another issue/milestone. Also carries the `blocked` label. |
| Done | Closed and shipped. |

Dependencies stay in body text (`Depends on #N`, `Refs #M`). A genuinely-blocked issue gets
the `blocked` label *and* moves to the Blocked column.

## Version control (jj, colocated)

The working copy is **Jujutsu (jj)**, colocated with git (§28). git stays underneath as the
remote/interop layer; jj drives every local VC step, and the skills (`work`, `commit`, `ship`,
`review`) are jj-native. The operational specifics the skills depend on:

- **Workspace-first.** Each work stream runs in its own jj workspace under `.jj/ws/<slug>`,
  created off freshly-fetched trunk — never by moving the shared `@`, never on a stale trunk:
  `jj git fetch && mkdir -p .jj/ws && jj workspace add --name <slug> --revision 'trunk()' .jj/ws/<slug>`.
  Stay in your workspace for every jj/`gh` op; after merge, `jj workspace forget <slug>` and
  remove the dir. The isolation unit is the workspace, not a git worktree.
- **Snapshot model, no staging.** A commit is `jj commit [paths] -m "..."`; fold a fix with
  `jj squash --from/--into`. jj fires no git hooks, so the `commit` skill validates the
  message shape and runs the project's checks itself; CI re-enforces both.
- **Bookmarks are branches.** `<type>/<#>-<slug>`. Push with
  `jj bookmark set <branch> -r @- && jj git push --bookmark <branch>`.
- **Rebase-merge PRs**: `gh pr merge <#> --rebase --delete-branch` — linear history, each
  commit good enough to live on `main`. Never `--merge`. Self-review with `review` first.

No `Co-Authored-By` trailer on any commit (repeated because it's easy to forget).

## Style

- **Functional over OOP** (§14). Factory functions returning closures over private state, not
  `class`/`this`. Reserve classes for genuine framework-interface compliance and say why.
- **Formatting & linting.** <!-- TODO: name the formatter and linter (Biome, Prettier +
  ESLint, etc.). Don't fight the formatter. -->
- **Imports** follow the project's configured path aliases (`~/…`, `@/…`); prefer a module's
  index over reaching into internals. Don't add a new alias scheme without the matching config.

Pre-commit hooks (if wired): lint, typecheck, test; `commit-msg` enforces Conventional
Commits. If a hook fails, fix the cause — never `--no-verify`.
