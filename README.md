# claude-harness-template

A portable workflow harness for [Claude Code](https://claude.com/claude-code) and
Codex projects. Install it in any repo with one command (`/bootstrap-harness`) and
get the same opinionated end-to-end flow: capture → work (plan → adversarial plan
review → implement → review → ship) with atomic conventional commits, no
`Co-Authored-By` trailers, and a shared "Lemon Pie" UI vocabulary.

## What's in here

```
.claude/
  skills/
    work/                   pick up a GitHub issue end-to-end
    research/               go deep on an issue's open questions, no implementation
    commit/                 atomic conventional commits, no --no-verify
    review/                 run reviewer agents on the diff, chat report
    capture/                file a GH issue — only if it clears the felt-value bar
    ship/                   land on main (branch/commit/push/PR/CI/rebase-merge)
    setup/                  fresh-clone onboarding skeleton
    neobrutalist-pop/       neo-brutalist UI tokens + components
  agents/
    code-reviewer.md        engineering-quality reviewer
    test-reviewer.md        adversarial test reviewer
    plan-reviewer.md        adversarial plan reviewer (run before code exists)
    data-reviewer.md        schema, migrations, value types, feature flags
    security-reviewer.md    authz/RBAC/RLS/audit/PII (commercial-ready only)
docs/
  PHILOSOPHY.md             durable "why" doc — single-instance, Postgres-only,
                            no serverless, API-integration primitives, etc.
CLAUDE.md                   skeleton: short rules + per-project TODOs, references
                            PHILOSOPHY.md for the long-form reasoning
AGENTS.md                   Codex bridge: delegates to CLAUDE.md + .claude skills
bootstrap-harness/
  SKILL.md                  the global skill that installs everything above
  scripts/install.sh        the installer the skill runs — single source of truth
```

## Install (one-time, per machine)

The `bootstrap-harness` skill lives globally so it's available in any repo. Install the
same `SKILL.md` into both Claude Code's and Codex's user-scope skill directories:

```sh
CHT="$(mktemp -d)"
git clone --depth 1 https://github.com/mauricedesaxe/claude-harness-template.git "$CHT"
mkdir -p ~/.claude/skills/bootstrap-harness ~/.agents/skills/bootstrap-harness
cp "$CHT/bootstrap-harness/SKILL.md" ~/.claude/skills/bootstrap-harness/SKILL.md
cp "$CHT/bootstrap-harness/SKILL.md" ~/.agents/skills/bootstrap-harness/SKILL.md
rm -rf "$CHT"
```

Only `SKILL.md` is installed globally — the installer is always run from a fresh clone of
the template (the skill clones it on each run), so there's no stale local copy to drift.
From then on, `/bootstrap-harness` works in any Claude Code session and
`$bootstrap-harness` works in any Codex session (`~/.agents/skills` is Codex's user-level
skills directory; restart Codex once after installing a new skill so it's discovered).

## Use (per-project)

Inside any git repo:

```
/bootstrap-harness      # Claude Code
$bootstrap-harness      # Codex
```

The agent clones the template and runs `bootstrap-harness/scripts/install.sh` from that
fresh clone. The installer overwrites the universal skills/agents into `.claude/`,
overwrites `docs/PHILOSOPHY.md` (the canonical "why" doc, always synced), preserves any
non-universal skills/agents already there, writes a `CLAUDE.md` skeleton (only if one
doesn't exist), and sets up Codex through `AGENTS.md`. If `AGENTS.md` already has the
bridge, the installer syncs it in place; if it exists without one, the bounded bridge is
appended. Codex picks up the project workflows through that `AGENTS.md` bridge (which
points it at `.claude/skills/`), so the skills aren't duplicated into a second directory.
Then fill the `<!-- TODO -->` markers in `CLAUDE.md` with the
project's specifics: what the project does, its architecture, the load-bearing bar
("the score stays trustworthy and explainable", "the latency budget stays under N",
etc.), area labels, and (if applicable) GitHub Project IDs.

`docs/PHILOSOPHY.md` is the load-bearing reference doc — read it once, then let
`CLAUDE.md` point at its section numbers (§1 Earn its keep, §3 Single-instance
default, §5 Postgres only, §7 No serverless / no edge, §11 API integration
primitives, etc.).

## Customizing

The universal skills are deliberately opinionated. If you need to diverge for a
specific project — different test runner, no GitHub Project board, etc. — edit the
files in that project's `.claude/` after install.

**Improvements you'd want everywhere should be backported here.** Open a PR against
`mauricedesaxe/claude-harness-template`. The next `/bootstrap-harness` run picks it
up. There is no auto-sync — manual backport discipline is the price of having one
template feeding many projects with different needs.

## Philosophy in one breath

- **Earn its keep.** Any complexity beyond the single-machine default needs a
  named, current problem and an articulated reason the simpler thing won't work.
- **Outsource the non-core; own the data.** Pay for the managed solution unless
  the problem *is* your core competency. When both exist, prefer a library that
  runs on your own backend (e.g. **BetterAuth**) over a SaaS that holds your data
  — vendor lock-in is much harder to escape once the data has lived elsewhere.
  Building from scratch or self-hosting earns its keep only on a current cost or
  reliability problem.
- **TypeScript by default.** Python and Rust earn their keep.
- **Single instance, one Postgres, modular monolith.** Replicas, queues like
  Kafka, Redis, k8s all earn their keep. Background queues on Postgres (Graphile,
  pg-boss) are the default async story.
- **Postgres only.** Reject SQLite, Kafka, Redis, Mongo, Timescale, etc.
- **Managed Docker platforms** (Railway / Render / DO App Platform) > IaC, k8s, raw
  cloud. Dockerfile + push.
- **No serverless, no edge** for the app layer. App close to DB; CDN handles user
  latency. Cloudflare for CDN.
- **Observability from day one.** Structured logs + distributed traces. Errors
  never sampled out. Sentry + BetterStack as defaults; self-hosted Grafana stack
  must earn its keep.
- **End-to-end type safety.** Schema at every boundary; tRPC / OpenAPI / native
  framework typing between front and back. **Branded types** wherever they fit.
- **API integrations** stack five primitives: in-flight map, rate limiter,
  semaphore, circuit breaker, retry — in that order. Functional,
  consumer-policied, in-memory.
- **Database stores data; app owns the rules.** No business logic in stored
  procedures, triggers, or non-trivial constraints. Migrations reversible by
  default; expand → backfill → contract for invasive changes.
- **Value types at the boundary.** UTC `timestamptz` for time. `bigint` /
  `decimal.js` for money. Avoid Unix-numeric timestamps and floating-point money.
- **Feature flags live in our Postgres.** No third-party flag SaaS.
- **Background jobs are idempotent — always.** Graphile Worker on Postgres,
  workers next to the web tier, cron in code. The ideal job test is end-to-end
  through the API → queue → worker → final-state seam.
- **File storage: Cloudflare R2 + pre-signed URLs.** Paths in DB, bytes in R2.
  Uploads go browser → R2 direct; the server only signs and records.
- **Polling first; push (WS / SSE / webhooks) earns its keep** on latency,
  resource intensity, or inbound from an external system.
- **Avoid double state.** One source of truth per piece of state. Caches,
  dedicated search indexes, read replicas — each duplicate earns its keep.
  Strong consistency over availability in the CAP trade.
- **Green CI + full-stack preview deploys + deploy on every merge.** Multiple
  deploys per day is the cadence. Evals (non-deterministic) are the one
  exception — run on every PR, not always required to pass.
- **AI: evals are load-bearing, costs are tracked per request.** Anthropic +
  OpenAI via OpenRouter is the default. Every metered API call is logged in
  Postgres (per user / request / model / cost). Fallback: provider down ⇒
  feature down, unless the product must stay available.
- **Test behaviour, climb the fidelity ladder.** Bugs live at the seams.
  Recorded fixtures over invented stubs. Unit tests are a tool, not the load-
  bearing layer.
- **Commercial readiness** is declared per project. Commercial-ready ⇒ RBAC + RLS
  + audit logging + authorization-matrix tests required.
- **Frontend (when app-shaped):** TanStack Query + Zustand + Tailwind +
  `neobrutalist-pop` + TanStack Form. Local-first feel under the Doherty
  threshold; keyboard-first. Skip the stack on small surfaces — simplicity wins.
- **Version control is jj (Jujutsu), colocated with git.** Isolated work happens in a
  jj **workspace** (not a git worktree — the workspace is jj's isolation unit); commits
  are `jj commit`, branches are bookmarks, `jj git push` / `gh` handle the remote. The
  skills are jj-native.
- **Atomic conventional commits**, no `--no-verify`, no `Co-Authored-By`. Rebase-merge.
- **Plan first, attack the plan, gate on the user, then write code.**
- **Comments and commits say *why*, not *what*.** Default to no comments.
- **Fail loud, distinguish "no data" from "fetched zero"** — the "two zeros" rule.
- **No `throw` in app code** — return a `Result<T, E>`.
- **Felt product value** is the bar for issues — not "feature vs refactor".

Full reasoning in [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md). Project-specific bindings
(runtimes, labels, modules) in `CLAUDE.md`. Codex reads `AGENTS.md`, which stays thin
and delegates back to `CLAUDE.md` plus the `.claude/skills/` workflows.

## Not in here

- Domain-specific reviewer agents (e.g. a `payments-reviewer` or `geo-scoring-reviewer`)
  — ship them in the project's own `.claude/agents/` and list them in the project's
  `CLAUDE.md`. The `review` skill picks them up automatically.
- Hook configs (`lefthook.yml`, `.husky/`, etc.) — these are project-flavoured and live
  in the project repo.
- Anything WalkUp-specific. The skills started life there; the domain references are
  stripped out here.

## License

MIT. Take it, fork it, edit it, ship a variant tuned to your shop.
