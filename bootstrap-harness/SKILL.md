---
name: bootstrap-harness
description: Install the Claude Code + Codex harness (universal skills, reviewer agents, philosophy spine + packs, CLAUDE.md skeleton, AGENTS.md Codex bridge) from lazar-harness into the current repo. Use when the user says "/bootstrap-harness", "$bootstrap-harness", "bootstrap the harness", "set up the harness here", or when starting a new project that should follow the standard work -> review -> ship flow with atomic conventional commits and the reviewer agents.
---

# Bootstrap Harness

> **Superseded by `install.sh`; frozen.** `lazar-harness` is installed globally, not copied
> into a repo, because every copy is a fork that starts drifting the day it lands. This skill
> is the old per-repo model and the manifest below is no longer authoritative.

Install the portable parts of `lazar-harness` into the current repo. This is an
**LLM-driven install**: you clone the template, copy a fixed manifest of files, and fill in
the project-specific `CLAUDE.md` TODOs using what you can read from the repo. There is no
bash installer to run — you do the copies yourself with judgment where the skeleton needs it.

The harness is **opinionated**: the standard workflow is the standard workflow. Don't ask
which skills the user wants — install them all. The one thing to ask up front is which
agent(s) this repo is for, because that decides whether the Codex bridge gets written.

## Step 0: preconditions

Confirm we're inside a git repo (`git rev-parse --show-toplevel`). If not, refuse and offer
to `git init`. The skills drive version control through **Jujutsu, colocated** (PHILOSOPHY
§28) — if the repo isn't jj yet, mention the user can opt in with `jj git init --colocate`,
but don't do it for them. If we're inside a vendored copy or submodule we don't own, ask
before installing.

## Step 1: which agent(s)?

Ask: **Claude Code, Codex, or both?**

- The skills, agents, and `docs/` files install the same way regardless — they're the
  shared source of truth both agents read.
- `CLAUDE.md` is always written (it's the canonical project guidance; Codex reads it through
  the bridge).
- `AGENTS.md` (the Codex bridge) is written **only when Codex is in play**. Skip it for a
  Claude-Code-only repo.

## Step 2: fetch the template

Clone a fresh copy to a temp dir — never reuse a stale local clone, since the template
changes between runs and a stale copy reintroduces the drift this skill exists to prevent.

```sh
TMPDIR_HARNESS="$(mktemp -d -t claude-harness-XXXXXX)"
trap 'rm -rf "$TMPDIR_HARNESS"' EXIT
git clone --depth 1 https://github.com/mauricedesaxe/claude-harness-template.git \
  "$TMPDIR_HARNESS"
```

If the clone fails (offline, repo moved/private), surface the error and stop. Don't fall back
to a stale copy.

## Step 3: copy the manifest

Copy these from the temp clone into the repo root. **Universal files are overwritten** every
run — that's how the conventions stay synced. **Anything not in this list under `.claude/`
or `docs/` is the project's own and is left untouched.**

**Skills** → `.claude/skills/<name>/SKILL.md` (overwrite):
- **Issue layer:** `work`, `research`, `commit`, `review`, `capture`, `ship`, `setup`.
- **Initiative layer** (Shape Up, §29): `shape`, `bet`, `prune`.
- **Planning & assessment:** `next-task`, `viability`.
- **Reporting:** `codebase-report` (plus its `collect-metrics.sh` + `test-collect.sh`).
- **UI / design:** `neobrutalist-pop` (plus `neobrutalist-pop/assets/brutpop.css`),
  `lazar-tldraw` (plus its `LICENSE` — a vendored MIT skill).
- **Engineering skills (Matt Pocock):** the full `matt-*` family — copy each skill's
  whole directory (several carry supporting `.md` files or `scripts/`, not just a lone
  `SKILL.md`): `matt-grill-with-docs`, `matt-grilling`, `matt-grill-me`, `matt-to-spec`,
  `matt-to-tickets`, `matt-implement`, `matt-tdd`, `matt-code-review`, `matt-wayfinder`,
  `matt-triage`, `matt-handoff`, `matt-domain-modeling`, `matt-codebase-design`,
  `matt-diagnosing-bugs`, `matt-improve-codebase-architecture`, `matt-prototype`,
  `matt-research`, `matt-resolving-merge-conflicts`, `matt-teach`, `matt-ask-matt`,
  `matt-writing-great-skills`, and `matt-setup-matt-pocock-skills`. They keep the `matt-`
  prefix as a distinct engineering-skills layer, cross-reference each other by that name, and
  bring their own review sub-agents (they don't depend on the universal reviewers below).
  They're **issue-tracker-agnostic**: after install, run `/matt-setup-matt-pocock-skills`
  once in the repo — it writes `docs/agents/issue-tracker.md` (GitHub / GitLab / local /
  other) that the rest read from.

`lazar-tldraw` needs an external CLI: mention that the user should
`npm install -g @kitschpatrol/tldraw-cli` to use it (it's not a repo dependency).

**Agents** → `.claude/agents/<name>.md` (overwrite):
`code-reviewer`, `test-reviewer`, `plan-reviewer`, `data-reviewer`, `security-reviewer`,
`git-hygiene-reviewer`, `yagni-reviewer`, `clarity-reviewer`.
(The security reviewer only *runs* when `CLAUDE.md` declares `Commercial readiness: yes`, but
it's always installed. `git-hygiene-reviewer`, `yagni-reviewer`, and `clarity-reviewer` run on
every `/review` — history/PR-meta shape, speculative generality, and documentation/comment +
self-explanatory-code discipline (§21) respectively; none reviews code quality, that's
`code-reviewer`.)

**Docs** → overwrite:
`docs/PHILOSOPHY.md` (the paradigm-agnostic spine — the canonical "why"),
`docs/packs/web.md`, `docs/packs/ai.md`.
The spine always travels so the conventions land even when an existing `CLAUDE.md` is kept.
A non-web repo keeps the spine and can ignore the web pack; you may skip copying a pack that
is plainly irrelevant to the repo's paradigm, but when unsure copy it — it's cheap and inert.

**`.gitignore`** → append `.jj/ws/` if absent (the `work`/`ship` skills create jj workspaces
there; PHILOSOPHY §14 + §28).

## Step 4: CLAUDE.md

- **Missing** → copy the template's `CLAUDE.md` skeleton, then fill its `<!-- TODO -->`
  markers from what you can read in the repo: what the project does, the load-bearing **bar**,
  `Commercial readiness: yes/no`, architecture, runtime, area labels, formatter/linter, and
  the project-board URL/IDs if you can find them. Leave a TODO in place only when you genuinely
  can't infer it, and tell the user which ones you left.
- **Present** → leave it untouched. The project owns its `CLAUDE.md`; that's its identity. The
  spine you just copied carries the conventions regardless. Don't auto-merge into it.

## Step 5: AGENTS.md (only if Codex is in play)

The Codex bridge stays thin and delegates back to `CLAUDE.md`, the spine, and the
`.claude/skills/` workflows — Codex reads the project skills *through* the bridge rather than
from a duplicated `.agents/skills` copy (one source of truth, no drift).

- **Missing** → copy the template's `AGENTS.md`.
- **Present with the `<!-- BEGIN/END CLAUDE HARNESS CODEX BRIDGE -->` markers** → replace the
  block between them with the template's current bridge.
- **Present without markers** → append the bridge block, leaving existing content intact.

## Step 6: recommended MCPs

The harness assumes a few MCP servers are available (they're user-scope, not repo config, so
this is a recommendation, not a copy). Mention the ones the skills lean on and let the user
wire the ones they want:

- **Browser (Playwright)** — the load-bearing one. The `work`/`review` flow verifies UI
  changes by driving a real browser (navigate, snapshot, screenshot) rather than trusting the
  code compiled. Any UI-shaped repo wants it. Install: `claude mcp add playwright -- npx
  @playwright/mcp@latest`, then, on first use, install the browser binary the error names
  (`npx @playwright/mcp install-browser chrome-for-testing`). New MCP tools need a session
  restart to register.
- **GitHub** — `capture`/`ship`/`work` touch issues, PRs, and the project board. The `gh` CLI
  covers most of it; the GitHub MCP is a convenience.
- **Deploy platform** (Railway / your host) — optional, for driving deploys and reading logs.

Don't install these for the user or write them into the repo. Name them, point at the install
commands, and move on.

## Step 7: report

Tell the user what was added vs. overwritten vs. preserved, which `CLAUDE.md` TODOs you filled
and which you left, and the next step (fill any remaining TODOs; wire any recommended MCPs;
for Codex, restart it once so it discovers the bridge).

## Drift policy

The template is the source of truth; this skill installs *from* it. Improvements made to a
universal skill/agent/pack in some project do **not** flow back automatically. When you make a
change worth keeping everywhere, PR it into `mauricedesaxe/claude-harness-template`; the next
`/bootstrap-harness` run picks it up. Manual backport is the price of one template feeding many
projects — don't edit the global skill copies separately.

## Don't

- **Don't** ask which universal skills to install. They all install. Edit after if needed.
- **Don't** auto-merge into an existing `CLAUDE.md`, or skip copying the spine/packs. The
  spine is canonical; a local edit to it should have been a PR to the template.
- **Don't** duplicate project rules into `AGENTS.md` or mirror skills into `.agents/skills` —
  the bridge already points Codex at `.claude/skills/` (double state, PHILOSOPHY §26).
- **Don't** delete or rename non-universal skills/agents — they're the project's.
- **Don't** fall back to a stale local clone if the fetch fails.
- **Don't** add a `Co-Authored-By` trailer or "Generated with Claude Code" line to any commit.
