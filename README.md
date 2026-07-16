# lazar-harness

A single, global-only agent harness. It is **installed** into every runtime it supports and
is never copied into a repository, because every copy is a fork that starts drifting the day
it lands. One source, one install command, and the per-runtime differences are generated
rather than hand-maintained.

Supported runtimes: [Claude Code](https://claude.com/claude-code) and
[OpenCode](https://opencode.ai).

## Install

```sh
./install.sh
```

Needs `bash` and `jq`. It writes to `~/.claude/` (skills, agents, rules, `CLAUDE.md`) and
`~/.config/opencode/` (skills, agents, rules, `AGENTS.md`, `opencode.json`), reading
everything from this repo:

```
install.sh                  the whole install path
vendor-matt-skills.sh       re-vendors mattpocock/skills as matt-*
skills-lock.json            the source and content hash every vendored skill is pinned to
CLAUDE.md                   the instructions both runtimes load
agents/
  clarity-reviewer.md       docs/comment + self-explanatory-code discipline (§21)
skills/
  lazar-tldraw/             talk → tldraw canvas: diagrams + low-fi wireframes (vendored)
  matt-*/                   Matt Pocock's 22 skills, vendored (see below)
docs/
  PHILOSOPHY.md             the paradigm-agnostic spine, installed as a rule
  packs/                    per-paradigm packs, each scoped by its own `paths:`
test/
  install-smoke.sh          runs install.sh under a temp HOME, asserts the tree
```

An agent is authored **once**, in Claude Code's format. OpenCode additionally requires a
`mode:` and a `permission:` block, and the installer generates those from that single source
at install time, so there is no second copy of an agent to keep in sync.

The philosophy installs to `~/.claude/rules/`, which Claude Code reads in every repo with no
per-repo setup. The spine carries no `paths:` frontmatter, so it is always loaded; each pack
carries one, so it loads only when the agent touches a file it matches — a smart-contract repo
gets the spine and is never lectured about Postgres. OpenCode has no equivalent, so it gets the
same files via the `instructions` array in `opencode.json` and loads the packs unconditionally.

`CLAUDE.md` is installed to `~/.claude/CLAUDE.md` and, under OpenCode's own name for the same
thing, to `~/.config/opencode/AGENTS.md`.

## Vendored skills

[Matt Pocock's skills](https://github.com/mattpocock/skills) are vendored through the
[`skills` CLI](https://skills.sh). Nothing here is hand-edited, so there is nothing to hand-merge
and no local edits an update could lose:

```sh
./vendor-matt-skills.sh --update    # pull upstream's current content and repin the lockfile
./vendor-matt-skills.sh             # re-vendor exactly what the lockfile pins, or fail
```

`skills-lock.json` pins each skill's source repository, its path within that repository, and the
content hash of its `SKILL.md`. Without `--update`, the script fetches upstream and refuses to
write anything if a pinned `SKILL.md` no longer hashes to what it pinned, so a re-vendor either
reproduces those prompts or tells you upstream moved. A skill's supporting files are not covered
by that hash — they are pinned only by being committed here, where a re-vendor shows any upstream
change to them as a diff.

Every skill is renamed `matt-<name>` on the way in — its directory, its `name:` frontmatter, and
the `/name` cross-references its prose dispatches through. The prefix is load-bearing: upstream
ships `code-review`, `implement` and `research`, so a skill installed under its own name would
silently replace Claude Code's built-in `/code-review`, and a body left saying `/code-review`
would call that built-in instead of `matt-code-review`.

That makes the vendored prose diverge from upstream, which is a bug everywhere except here: the
rename is a step of the vendor script, re-derived from scratch on every run and never
hand-maintained, so it survives each future update without anyone remembering it. Only the 22
vendored names are rewritten, so Claude Code's own `/compact` still means `/compact`, and only
where a reference and not a path is being written, so `docs/agents/triage-labels.md` and the
route `/prototype/<name>` are left alone.

## Test

```sh
bash test/install-smoke.sh
bash test/prefix-rewrite.sh
```

`install-smoke.sh` is one end-to-end pass: it runs the installer with `HOME` pointed at a temp
directory and asserts what landed on disk — that both runtimes got the skills, the agent, and the
instructions, that every skill the lockfile pins is installed under its `matt-` name with no
body still dispatching to an unprefixed one, and that the OpenCode agent carries the generated
frontmatter while its prompt still matches the source byte for byte.

`prefix-rewrite.sh` drives the vendor script's rename over a fixture, offline. It is the seam
where the prefix is decided, so it is the seam that pins which `/name` is a reference to rewrite
and which is a path or a built-in to leave alone.

`docs/PHILOSOPHY.md` is the load-bearing reference doc — read it once, then let
`CLAUDE.md` point at its section numbers (§1 Earn its keep, §3 Single-instance
default, §5 Postgres only, §7 No serverless / no edge, §11 API integration
primitives, §29 Shaping / appetite / betting, etc.).

The skills lean on a few MCP servers, which are user-scope and so are yours to wire. The
load-bearing one is the **browser MCP (Playwright)**: the review flow verifies UI changes by
driving a real browser (navigate, snapshot, screenshot) instead of trusting that the code
compiled. The `lazar-tldraw` skill additionally needs `@kitschpatrol/tldraw-cli` on your PATH.

## Legacy: the per-repo bootstrap

`bootstrap-harness/`, and the `.claude/` skills and agents beside it, are the previous model:
`/bootstrap-harness` cloned this repo into whatever project you ran it in and copied the
harness there. That is what produced the drifting copies this repo now exists to end, so the
skill is frozen, its manifest is no longer authoritative, and it is being removed. Use
`./install.sh`.

Improvements still land here first — open a PR against
`mauricedesaxe/claude-harness-template` — but they now reach you by reinstalling rather than
by re-bootstrapping each repo.

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
- **Two altitudes (Shape Up).** Initiatives (GitHub milestones) get shaped, bet on,
  and circuit-broken; issues get captured, researched, and built. Appetite is counted
  in sittings, 1–3 bets active at once, never four. Skills: `shape` / `bet` / `prune`
  at the initiative layer, `capture` / `research` / `work` / `ship` at the issue layer.

Full reasoning in [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md). Project-specific bindings
(runtimes, labels, modules) in `CLAUDE.md`. Codex reads `AGENTS.md`, which stays thin
and delegates back to `CLAUDE.md` plus the `.claude/skills/` workflows.

## Not in here

- Domain-specific reviewer agents (e.g. a `payments-reviewer` or `geo-scoring-reviewer`)
  — ship them in the project's own `.claude/agents/` and list them in the project's
  `CLAUDE.md`. The `review` skill picks them up automatically.
- Hook configs (`lefthook.yml`, `.husky/`, etc.) — these are project-flavoured and live
  in the project repo.
- Anything project-specific. The skills started life in a working product repo; the
  domain references are stripped out here.

## License

MIT. Take it, fork it, edit it, ship a variant tuned to your shop.
