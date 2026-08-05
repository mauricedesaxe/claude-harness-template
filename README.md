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
`CLAUDE.md`, `settings.json`) and OpenCode's (skills, agents, rules, `AGENTS.md`,
`opencode.json`), reading everything from this repo. Each is resolved the way the runtime itself
resolves it, so the harness lands where it is actually read:

| Runtime     | Config home                                 |
| ----------- | ------------------------------------------- |
| Claude Code | `${CLAUDE_CONFIG_DIR:-~/.claude}`           |
| OpenCode    | `${XDG_CONFIG_HOME:-~/.config}/opencode`    |

With neither variable set that is `~/.claude/` and `~/.config/opencode/`, which is what the
paths below assume.

### Every global root a runtime reads skills from

A config home is not the whole story for skills. OpenCode auto-loads two roots that sit outside its
own home, and both **outrank** the ones the installer writes, so a skill in either loads in OpenCode
and not in Claude Code — and can shadow a skill the harness ships while every file the installer
wrote is exactly where it put it. Probed by planting colliding canaries and reading
`opencode debug skill` back, highest precedence first:

| Root                              | Claude Code | OpenCode | Install action                |
| --------------------------------- | ----------- | -------- | ----------------------------- |
| `$OPENCODE_HOME/skills`           | no          | yes      | replaced whole                |
| `$OPENCODE_HOME/skill` (singular) | no          | yes      | **emptied**, never written to |
| `~/.agents/skills`                | no          | yes      | **emptied**, never written to |
| `$CLAUDE_HOME/skills`             | yes         | yes      | replaced whole                |
| `<built-in>`                      | no          | yes      | out of reach — see below      |

Claude Code (2.1.209) reads the last directory alone: its binary carries 63 references to
`.claude/skills` and none to `.agents/skills`. Neither runtime reads a singular `skill/` under
`~/.claude` or `~/.agents` — the singular spelling is OpenCode's, and only under its own home.

Two roots are emptied rather than installed into, because OpenCode reads `~/.claude/skills`
directly and unconditionally: the harness's skills already reach it there, and a second copy would
be double state that drifts (`§26`). Emptying is all that is needed and all that is right.

**`~/.agents` is the Railway CLI's, not the harness's.** `railway skills` documents that it
"always installs to `~/.agents/skills`", additionally installing to detected tool directories such
as `~/.claude/skills`; it created the directory on this machine, and it treats it as the
`Universal (.agents)` target shared with Codex, Cursor, Copilot and Factory Droid. So the harness
**empties that directory and leaves it standing** — removing a directory another tool owns and
recreates buys nothing. This is a purge with an owner on the other side of it: the next
`railway skills install` puts its skill straight back, and the next harness install takes it out
again. That is a standoff rather than a fix, and it is written here rather than left to be
discovered. The install's plan names the directory and every entry it is about to delete from it,
so it is readable before it happens instead of after.

OpenCode also resolves one skill from no directory at all: `customize-opencode`, compiled into the
binary, `location: "<built-in>"`, present with an empty `HOME` and no config. No installer can
purge it, so the two runtimes can never resolve literally identical sets. The parity test excludes
it by that sentinel, and by nothing else.

**Do not link either emptied root onto a root the installer fills.** Symlinking
`~/.agents/skills` at `~/.claude/skills` looks like "one source of truth" and is the exact shape
`~/.claude-personal/skills` already has, but it would mean the install fills the skills tree and
then empties it through the link — every skill gone, exit 0. The installer refuses that
arrangement and stops before it prints a plan, because there is no way to tell which of the two
directories was meant. Give each root its own directory, or remove the link: OpenCode reads
`~/.claude/skills` directly, so linking to it from `~/.agents/skills` buys nothing.

`settings.json` and `opencode.json` are **merged**, not replaced: they carry model choice,
plugins and auth-adjacent config that are none of the harness's business. Each install drops the
entries a previous one wrote and adds back what ships now, so nothing accumulates and nothing
else is touched.

```
install.sh                  the whole install path
vendor-skills.sh            re-vendors mattpocock/skills as matt-*, tldraw-skill as lazar-tldraw,
                            railway-skills as use-railway
skills-lock.json            the source and content hash every vendored skill is pinned to
patches/
  lazar-tldraw.patch        the local divergence from tldraw-skill, re-applied at vendor time
CLAUDE.md                   the instructions both runtimes load
opencode/
  commands/bro.md           OpenCode's user-invoked /bro adapter
hooks/
  enforce-jj.sh             PreToolUse: allows read-only git, steers the rest to jj
agents/
  clarity-reviewer.md       docs/comment + self-explanatory-code discipline (§21)
  complexity-reviewer.md    complexity placement + deep-module discipline (§32)
  git-hygiene-reviewer.md   atomic conventional commits, linear history, PR meta
  yagni-reviewer.md         speculative generality, in a diff or in a plan
skills/
  bro/                      user-invoked plain-language reset
  lazar-commit/             atomic conventional commits, jj-native, no AI attribution
  lazar-pr-status/          a PR number → its issue, what's addressed, what's only replied to, drift
  lazar-research/           an issue's open questions → /deep-research + matt-prototype → a verdict
  lazar-review/             the one review: global agents + the repo's own + matt-code-review
  lazar-ship/               bookmark → push → PR → gate → rebase-merge → close out on the tracker
  lazar-standup/            the daily 3 Ps, from merged PRs + tracker + unpushed local work
  lazar-tldraw/             talk → tldraw canvas: diagrams + low-fi wireframes (vendored)
  matt-*/                   Matt Pocock's 22 skills, vendored (see below)
  use-railway/              Railway ops, vendored — unprefixed on purpose (see below)
                            all are generated — edit the upstream or the patch, not the file
docs/
  PHILOSOPHY.md             the paradigm-agnostic spine, installed as a rule
  packs/                    per-paradigm packs, each scoped by its own `paths:`
test/
  install-smoke.sh          runs install.sh under a temp HOME, asserts the tree
  enforce-jj.sh             drives the hook with synthetic PreToolUse payloads
```

## Enforcement

Everything else here is guidance, and guidance dies at the first delegation boundary: `CLAUDE.md`
and `~/.claude/rules/` are **not inherited by subagents**, so a rule written there reaches a main
loop and stops. An agent that had been told not to run `install.sh` complied, then spawned a
reviewer subagent that ran it and wiped a live config directory. A `PreToolUse` hook fires for
every agent at every depth, so it is the only enforcement this harness has.

`hooks/` is therefore an install target alongside `skills/` and `agents/`, with the same purge:
a hook this repo stops shipping comes off the disk, and the same install takes its wiring out of
`settings.json`, because a wired command whose file is gone fires on every prompt and fails there.

**`enforce-jj.sh` is an allow list, and that is a deliberate trade.** It knows the git subcommands
that only read — `status`, `log`, `diff`, `show`, the plumbing, and the read spelling of the ones
that read or write depending on their arguments — and denies every other git subcommand in a jj
repo. A deny list only ever holds the mutations someone thought of, and this file shipped for
months with `git clean -fd`, `git stash`, `git checkout -b` and `git restore` in no list at all:
`git clean -fd` deletes untracked files, and jj has already snapshotted those into `@`, so they are
part of the working-copy commit rather than junk git can regenerate. The two directions fail
differently, and that is the whole argument — a missing allow-list entry costs a denial with a
message and a one-line fix, a missing deny-list entry costs the working copy, silently. So expect
it to deny the occasional harmless git command. Add it to `GIT_READ` when it does.

It also **refuses when `jq` is missing** rather than allowing everything, since jq is what parses
the payload and a guard that cannot read the call cannot clear it. That refusal is scoped to jj
repos, so one absent binary cannot brick every session on the machine.

It matches at the **command position**, so a mutation handed to another program as an argument
(`sudo git clean -fd`, `xargs git commit`, `bash -c '…'`) is not interpreted and goes through. That
is deliberate and unchanged by the allow list: another program's arguments have no closed set to
them, and this hook guards the accident, not the adversary. The enforcement that matters is that
the obvious spelling steers to jj.

Hooks are the one target that does not resolve through the runtime's config home. `settings.json`
names a hook by absolute path rather than discovering it under a home, so a single
`~/.claude/hooks/` serves every Claude Code profile on the machine that points at it.
`HARNESS_SURFACE=sandbox` has one config home and no profiles, so there it resolves like
everything else.

**Install every profile in one go.** A run purges that shared directory but rewrites only the
`settings.json` it was pointed at, because that is the only one it can see. So between the first
profile's install and the last, a profile not yet installed still wires a hook that is already
gone, and fires it on every prompt. The plan is worth reading before the first run rather than
between the second and the third.

**OpenCode gets none of this.** It has no hook equivalent, so enforcement is Claude Code's alone
and OpenCode keeps guidance. Enforcement where it is available beats enforcement nowhere; the
asymmetry is chosen.

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

## Surfaces

A laptop and an Open-Inspect sandbox differ in one way the harness has to answer for: whether the
agents working a repo share a filesystem. On a laptop they do, and a subagent reads the same working
copy its parent edits. In a sandbox they don't, and a spawned agent boots a clean clone of the base
branch that has never seen the parent's checkout.

`HARNESS_SURFACE` names which of the two is being installed for. It takes `local`, the default, or
`sandbox`, which a sandbox image build passes when it invokes the installer. It is the *environment*,
not the runtime: Claude Code and OpenCode both run in both places.

Prose that turns on it is authored inline, in the file it belongs to, between markers:

```markdown
<!-- surface:local -->
…what to do when the agents share a disk…
<!-- /surface:local -->

<!-- surface:sandbox -->
…what to do when they don't…
<!-- /surface:sandbox -->
```

The installer keeps the blocks matching the surface and drops the rest, in every file that carries
them. Which files those are is read off the files, so a skill that grows a block needs no change to
`install.sh`. A block that never closes, a name outside `local`/`sandbox`, or a file missing the
surface being installed all stop the run: each one otherwise ships silently, and the first truncates
the file at the marker.

Four files use it today:

- **`CLAUDE.md`** — which jj workspace to work in. `§28` states the isolation principle for both
  surfaces; only the default action differs, since a sandbox is already a checkout of its own.
- **`skills/lazar-review/SKILL.md`** — what diff the reviewers are handed, and whether the verdict
  is posted. Sharing a disk means `jj diff --from 'trunk()' --to @`, committed plus uncommitted.
  Not sharing one means the pushed PR, which each reviewer fetches with `gh` for itself, and
  nothing pushed means say so and spawn nobody rather than booting a sandbox per reviewer to fail
  identically. Posting is refused on a laptop, where nothing goes out under Alex's name unread,
  and required in a sandbox, where the review carries a bot's identity and the transcript reaches
  nobody.
- **`skills/lazar-ship/SKILL.md`** — whether Step 3 waits to be OK'd before committing. An
  approval gate with nobody to answer it strands finished work in a checkout that is about to be
  destroyed, and push, PR and merge all sit downstream of it.
- **`agents/git-hygiene-reviewer.md`** — where the commit history is read from. It is the one
  reviewer that gathers its own input, so a `jj log` of `trunk()..@` on a machine that only ever
  cloned the base branch reports a clean stack for work it never saw.

Both variants sit next to each other in the file someone edits, so the two surfaces are reviewed as
one diff and neither is a copy of the other. `install.sh` carries the reasoning at the transform.

## Machine-local repo notes

Skills need to know which tracker owns a repo. Where the repo can't carry that itself, they keep
a note per repo at `~/.lazar-harness/repos/<host>/<owner>/<repo>.md`. Nothing installs these —
a skill writes one the first and only time it has to ask, and reads it forever after.
`CLAUDE.md` carries the resolution order and the note's format.

## Vendored skills

Five upstreams are vendored through the [`skills` CLI](https://skills.sh):
[Matt Pocock's skills](https://github.com/mattpocock/skills) as `matt-*`,
[Agents365-ai/tldraw-skill](https://github.com/Agents365-ai/tldraw-skill) as `lazar-tldraw`, and
[railwayapp/railway-skills](https://github.com/railwayapp/railway-skills) as `use-railway`,
[Plannotator](https://github.com/backnotprop/plannotator)'s six published skills, and
[nicobailon/visual-explainer](https://github.com/nicobailon/visual-explainer) as the visual
dependency Plannotator delegates to.
Nothing here is hand-edited, so there is nothing to hand-merge and no local edits an update could
lose:

```sh
./vendor-skills.sh --update    # pull upstream's current content and repin the lockfile
./vendor-skills.sh --update-plannotator  # update Plannotator without moving unrelated pins
./vendor-skills.sh             # re-vendor exactly what the lockfile pins, or fail
./vendor-skills.sh --regen-patch   # rebuild patches/lazar-tldraw.patch from an edited lazar-tldraw
```

`skills-lock.json` pins each skill's source repository, its path within that repository, and the
content hash of its `SKILL.md`. Without `--update`, the script fetches upstream and refuses to
write anything if a pinned `SKILL.md` no longer hashes to what it pinned, so a re-vendor either
reproduces those prompts or tells you upstream moved. A skill's supporting files are not covered
by that hash — they are pinned only by being committed here, where a re-vendor shows any upstream
change to them as a diff.

The harness owns Plannotator's skill definitions, not its executable or runtime plugins. Install
the `plannotator` binary separately on machines that invoke these skills. Sandbox images need the
same binary before the skills can run there.

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

### The invocation lock, stripped

Upstream ships 13 of its 22 skills with `disable-model-invocation: true`, which makes them
reachable only by a hand-typed slash command. The vendor removes that line.

The flag guards against an agent spontaneously firing an expensive workflow, which is a real
concern and not the one that bites here. The cost lands on voice-to-text: the agent can name the
command you should have typed and nothing else, and typing it means abandoning the brain-dump that
carried the context in the first place. `matt-ask-matt` is itself one of the locked ones, so
`CLAUDE.md`'s instruction to reach for Matt's skills *through the router* cannot be followed as
written.

It is a frontmatter transform rather than a patch for the same reason the prefix is: the patch tool
matches context exactly and refuses to fuzz, so a patch would break the next time upstream edited
anything near that frontmatter. The strip stops at the closing `---`, so a skill that *documents*
the flag in its prose keeps it — `matt-writing-great-skills` does exactly that, and
`test/model-invocation.sh` pins it, along with leaving an explicit `false` alone.

Each skill still gates itself in its own instructions, and `CLAUDE.md`'s "nudge, don't nag, don't
auto-run" rule already covers this class of skill. If a specific skill turns out to need the guard
back, the fix is to keep the lock on that one rather than to restore it wholesale.

### User-only `/bro` across runtimes

Claude Code reads `disable-model-invocation: true` and exposes the skill only when the user invokes
it. OpenCode ignores that field: it advertises every discovered skill to the model and uses
`commands/` for slash commands. The installer therefore writes `opencode/commands/bro.md` as the
OpenCode `/bro` adapter and sets `permission.skill.bro` to `deny`. The command stays available to
the user while the model-facing skill route stays hidden.

### Upstream names that are interop surfaces

Plannotator's six skills keep the names its installer writes. `visual-explainer` keeps the exact
name `plannotator-visual-explainer` delegates to. Renaming either set would leave the external
installer refilling one spelling while the harness shipped another.

`use-railway` has the same constraint, and it is the first name a tidy-up will try to prefix, so
here is why it must not be.

The name is not this harness's to choose. `railway skills install` reports, in its own help:

> Always installs to `~/.agents/skills`. Additionally installs to any detected tool directories
> (e.g. `~/.claude/skills`, `~/.cursor/skills`).

So another tool's installer writes a skill called `use-railway` into a root this harness owns. The
name is an **interop surface with that installer**, not a label. Rename the vendored copy to
`railway-use-railway` and the CLI goes on writing plain `use-railway` into `~/.claude/skills` for
the next harness install to purge — the ping-pong survives untouched, and now there are two skills
where there was one. That is strictly worse than the problem.

`skills/use-railway/` is therefore vendored under its upstream name, and the prefix rewrite skips
it by never listing it in `UPSTREAM_SKILLS`. `test/prefix-rewrite.sh` asserts that rather than
assuming it: adding the name to that list turns three assertions red.

**Why the ping-pong stops, which is not the reason you would guess.** It is not that both
installers write the same bytes. It is that Railway's installer **defers**: it records a SHA-256
of every file it writes in `~/.railway/skills.json`, and on the next run a file whose hash it
cannot verify is one it skips —

```
! 1 skill(s) skipped because of local changes. Re-run with railway skills update --force to overwrite them.
```

The harness's pinned copy differs from what the CLI would write (or, on a fresh machine, has no
recorded hash at all), so `railway skills install` leaves it alone. Only `--force` overwrites it.
The pinned copy in `~/.claude/skills` is therefore stable: the harness put it there, and Railway
will not take it back.

**`~/.agents/skills` stays emptied and never written into**, exactly as before. The two rules read
like they conflict — "never write into `~/.agents`" and "`use-railway` must survive" — but they do
not, because `~/.agents` does not have to *serve* the skill for the skill to survive. OpenCode
reads `~/.claude/skills` directly, so the pinned copy is resolvable without a second tree; and
`~/.agents/skills` **outranks** `~/.claude/skills` in OpenCode, so a copy left there would shadow
the pinned one and hand the two runtimes different skills under one name. Emptying it is what makes
the pinned copy authoritative in both. Writing the harness's copy into it would buy nothing and
cost a third tree to drift.

What remains is bounded and is the drift vendoring trades for. A `railway skills install` refills
`~/.agents/skills/use-railway`, where it shadows OpenCode until the next harness install empties
it again; and if upstream has moved past the pin by then, that install **downgrades** the skill
back to the pinned revision. That is the lockfile working as intended rather than a bug — it is
the same contract every other vendored skill has — and `./vendor-skills.sh --update` is the
answer. The pin is set to the revision the CLI ships today, so there is no skew to start with.

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
bash test/enforce-jj.sh
bash test/prefix-rewrite.sh
bash test/tldraw-patch.sh
bash test/model-invocation.sh
```

`install-smoke.sh` is one end-to-end pass: it runs the installer with `HOME` pointed at a temp
directory and asserts what landed on disk. Both runtimes get the same pinned skills, supporting
files, agents, and instructions. Matt's skills carry their rewritten names; Plannotator,
`visual-explainer`, and `use-railway` keep their upstream-owned names; `bro` remains user-invoked.
The suite also checks that no Matt skill dispatches to an unprefixed name and that OpenCode agents
carry generated frontmatter without changing their prompts.

It also drives `opencode debug skill` against that temp `HOME` and asserts what OpenCode
**resolved**, which is the one thing a disk check cannot stand in for: a skill planted in
`~/.agents/skills` shadows the harness's own copy of the same name, so every file assertion passes
while the two runtimes run different skills under one name. That needs `opencode` on `PATH`; the
run prints a loud `SKIP` and says so on its last line when it is missing, because a skipped
resolution check that reads as a pass is the failure this suite exists to avoid.

`enforce-jj.sh` drives the hook with the `PreToolUse` payloads Claude Code sends it and reads the
decision back out of its JSON. Synthetic, because the alternative is proving a matcher by
attempting the mutations it exists to stop. The two seams are separate on purpose: this one pins
what the hook decides, and `install-smoke.sh` pins that `settings.json`'s matcher hands it the
calls to decide on — a hook can be perfectly correct about a tool it is never asked about.

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
- **Test behaviour with fewer, coherent workflow tests.** Keep related actions
  and assertions together, climb the fidelity ladder, and prefer recorded
  fixtures over invented stubs. Unit tests are a tool, not the load-bearing layer.
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
  commercial posture), so they belong to the repo that holds those standards. The set in
  `agents/` survive globally because they encode habits that hold in every repo.
- Hook configs (`lefthook.yml`, `.husky/`, etc.) — these are project-flavoured and live
  in the project repo.
- Anything project-specific. The skills started life in a working product repo; the
  domain references are stripped out here.

## License

MIT. Take it, fork it, edit it, ship a variant tuned to your shop.
