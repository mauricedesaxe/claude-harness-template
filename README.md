# lazar-harness

A single, global-only agent harness. It is **installed** into every runtime it supports and
is never copied into a repository, because every copy is a fork that starts drifting the day
it lands. One source, one install command, and the per-runtime differences are generated
rather than hand-maintained.

Supported runtimes: [Claude Code](https://claude.com/claude-code) and
[OpenCode](https://opencode.ai).

## Install

```sh
./install.sh            # says what it would do to this machine, writes nothing
./install.sh --install  # does it
```

Writing is opt-in, and the run without the flag is the one to read first: it prints the two config
homes it resolved, the files it would replace, and **every entry it would delete**, then exits
having touched nothing. An install replaces `skills/`, `agents/` and `rules/packs/` whole, so
anything in them this repo has no name for goes, down to a file hand-edited inside a skill that
otherwise stays. That list is worth reading before it happens rather than after, and the run that
applies it prints the same one.

A script that installs when you merely run it is a script that installs when nobody meant to.
`install.sh` carries the story of the install nobody meant.

Needs `bash` and `jq`. It writes to Claude Code's config home (skills, agents, rules,
`CLAUDE.md`) and OpenCode's (skills, agents, rules, `AGENTS.md`, `opencode.json`), reading
everything from this repo. Each is resolved the way the runtime itself resolves it, so the
harness lands where it is actually read:

| Runtime     | Config home                                 |
| ----------- | ------------------------------------------- |
| Claude Code | `${CLAUDE_CONFIG_DIR:-~/.claude}`           |
| OpenCode    | `${XDG_CONFIG_HOME:-~/.config}/opencode`    |

With neither variable set that is `~/.claude/` and `~/.config/opencode/`, which is what the
paths below assume.

```
install.sh                  the whole install path
vendor-skills.sh            re-vendors mattpocock/skills as matt-*, tldraw-skill as lazar-tldraw
skills-lock.json            the source and content hash every vendored skill is pinned to
patches/
  lazar-tldraw.patch        the local divergence from tldraw-skill, re-applied at vendor time
CLAUDE.md                   the instructions both runtimes load
agents/
  clarity-reviewer.md       docs/comment + self-explanatory-code discipline (§21)
  git-hygiene-reviewer.md   atomic conventional commits, linear history, PR meta
  yagni-reviewer.md         speculative generality, in a diff or in a plan
skills/
  lazar-commit/             atomic conventional commits, jj-native, no AI attribution
  lazar-pr-status/          a PR number → its issue, what's addressed, what's only replied to, drift
  lazar-research/           an issue's open questions → /deep-research + matt-prototype → a verdict
  lazar-review/             the one review: global agents + the repo's own + matt-code-review
  lazar-ship/               bookmark → push → PR → gate → rebase-merge → close out on the tracker
  lazar-standup/            the daily 3 Ps, from merged PRs + tracker + unpushed local work
  lazar-tldraw/             talk → tldraw canvas: diagrams + low-fi wireframes (vendored)
  matt-*/                   Matt Pocock's 22 skills, vendored (see below)
                            both are generated — edit the upstream or the patch, not the file
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

It is authored for a laptop, and `HARNESS_SURFACE=sandbox ./install.sh --install` generates the one
block that differs in an Open-Inspect sandbox: which jj workspace to work in. `§28` states the
isolation principle for both, so only the default is generated, the same way an OpenCode agent's
frontmatter is. `install.sh` carries the reasoning at the transform.

## Machine-local repo notes

Skills need to know which tracker owns a repo. Where the repo can't carry that itself, they keep
a note per repo at `~/.lazar-harness/repos/<host>/<owner>/<repo>.md`. Nothing installs these —
a skill writes one the first and only time it has to ask, and reads it forever after.
`CLAUDE.md` carries the resolution order and the note's format.

## Vendored skills

Two upstreams are vendored through the [`skills` CLI](https://skills.sh):
[Matt Pocock's skills](https://github.com/mattpocock/skills) as `matt-*`, and
[Agents365-ai/tldraw-skill](https://github.com/Agents365-ai/tldraw-skill) as `lazar-tldraw`.
Nothing here is hand-edited, so there is nothing to hand-merge and no local edits an update could
lose:

```sh
./vendor-skills.sh --update    # pull upstream's current content and repin the lockfile
./vendor-skills.sh             # re-vendor exactly what the lockfile pins, or fail
./vendor-skills.sh --regen-patch   # rebuild patches/lazar-tldraw.patch from an edited lazar-tldraw
```

`skills-lock.json` pins each skill's source repository, its path within that repository, and the
content hash of its `SKILL.md`. Without `--update`, the script fetches upstream and refuses to
write anything if a pinned `SKILL.md` no longer hashes to what it pinned, so a re-vendor either
reproduces those prompts or tells you upstream moved. A skill's supporting files are not covered
by that hash — they are pinned only by being committed here, where a re-vendor shows any upstream
change to them as a diff.

Every skill of Matt's is renamed `matt-<name>` on the way in — its directory, its `name:`
frontmatter, and the `/name` cross-references its prose dispatches through. The prefix is
load-bearing: upstream
ships `code-review`, `implement` and `research`, so a skill installed under its own name would
silently replace Claude Code's built-in `/code-review`, and a body left saying `/code-review`
would call that built-in instead of `matt-code-review`.

That makes the vendored prose diverge from upstream, which is a bug everywhere except here: the
rename is a step of the vendor script, re-derived from scratch on every run and never
hand-maintained, so it survives each future update without anyone remembering it. Only the 22
vendored names are rewritten, so Claude Code's own `/compact` still means `/compact`, and only
where a reference and not a path is being written, so `docs/agents/triage-labels.md` and the
route `/prototype/<name>` are left alone.

### lazar-tldraw, which carries local patches

`lazar-tldraw` is the exception the `lazar-` prefix is announcing: it is not upstream's skill
under a new name. It adds the UI/UX wireframe and Shape-up presets, widens the triggers, and fixes
the sizing and spacing rules that had diagrams coming out packed with text overflowing its shapes.
That is prose, not a rewrite rule, so it cannot be re-derived the way the `matt-` prefix is.

It is still not hand-maintained. The divergence lives in `patches/lazar-tldraw.patch` and is
re-applied to freshly-fetched upstream on every run, which keeps the same property by a different
means: **`skills/lazar-tldraw/SKILL.md` is generated**, and the next re-vendor overwrites whatever
is sitting in it. The workflow is to edit that file like any other, then run `--regen-patch`,
which rebuilds the patch from the difference against pristine upstream so the change survives.

`git apply` matches context exactly and will not fuzz, so if upstream ever edits a region the
patch touches, the vendor **stops** with a conflict and writes nothing. That is the whole design:
the failure mode of an update is a loud stop, never a quietly-dropped local fix. Upstream's MIT
`LICENSE` is fetched alongside the skill, because the `skills` CLI installs `SKILL.md` alone and
the licence belongs next to the text it covers.

## Test

```sh
bash test/install-smoke.sh
bash test/prefix-rewrite.sh
bash test/tldraw-patch.sh
```

`install-smoke.sh` is one end-to-end pass: it runs the installer with `HOME` pointed at a temp
directory and asserts what landed on disk — that both runtimes got the skills, the agent, and the
instructions, that every skill the lockfile pins is installed under its `matt-` or `lazar-` name
with no body still dispatching to an unprefixed one, and that the OpenCode agent carries the
generated frontmatter while its prompt still matches the source byte for byte.

`prefix-rewrite.sh` drives the vendor script's rename over a fixture, offline. It is the seam
where the prefix is decided, so it is the seam that pins which `/name` is a reference to rewrite
and which is a path or a built-in to leave alone.

`tldraw-patch.sh` drives the vendor script's patch step over a fixture, offline. Its reason to
exist is the drift case: it pins that upstream moving under a patched region **stops** the
vendor, since the alternative is shipping a `lazar-tldraw` with its local fixes silently gone.

Neither of the two offline seams reaches the network; `vendor-skills.sh` itself does, so it is
run by hand rather than by a test.

`docs/PHILOSOPHY.md` is the load-bearing reference doc — read it once, then let
`CLAUDE.md` point at its section numbers (§1 Earn its keep, §3 Single-instance
default, §5 Postgres only, §7 No serverless / no edge, §11 API integration
primitives, §30 Felt outcome and writing, etc.).

The skills lean on a few MCP servers, which are user-scope and so are yours to wire. The
load-bearing one is the **browser MCP (Playwright)**: the review flow verifies UI changes by
driving a real browser (navigate, snapshot, screenshot) instead of trusting that the code
compiled. The `lazar-tldraw` skill additionally needs `@kitschpatrol/tldraw-cli` on your PATH.

## The per-repo bootstrap is gone

There used to be a `/bootstrap-harness` skill that cloned this repo into whatever project you
ran it in and copied the harness there. Every run minted another fork that started drifting the
day it landed, which is the problem this repo now exists to end. It is deleted, along with the
`.claude/` skill tree it installed. Both are readable in git history. Use `./install.sh --install`.

Improvements still land here first (open a PR against
`mauricedesaxe/claude-harness-template`), and they reach you by reinstalling rather than by
re-bootstrapping each repo.

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
  TanStack Form. Local-first feel under the Doherty
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
- `code-reviewer`, `test-reviewer`, `plan-reviewer`, `data-reviewer`, `security-reviewer`
  — they judge a repo against *its* standards (its module boundaries, its schema rules, its
  commercial posture), so they belong to the repo that holds those standards. The three in
  `agents/` survive globally because they encode habits that hold in every repo.
- Hook configs (`lefthook.yml`, `.husky/`, etc.) — these are project-flavoured and live
  in the project repo.
- Anything project-specific. The skills started life in a working product repo; the
  domain references are stripped out here.

## License

MIT. Take it, fork it, edit it, ship a variant tuned to your shop.
