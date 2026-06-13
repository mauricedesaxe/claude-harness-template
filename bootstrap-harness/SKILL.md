---
name: bootstrap-harness
description: Install the Claude Code + Codex harness (universal skills, reviewer agents, CLAUDE.md skeleton, AGENTS.md Codex bridge) from claude-harness-template into the current repo. Use when the user says "/bootstrap-harness", "$bootstrap-harness", "bootstrap the harness", "set up the harness here", "install the skills + agents in this repo", or when starting a new project that should follow the standard workflow (work -> review -> ship, atomic conventional commits, plan-reviewer, code-reviewer, test-reviewer).
---

# Bootstrap Harness

Install the portable parts of the `claude-harness-template` into the current repo. The
writes are done by one script — `bootstrap-harness/scripts/install.sh` — run from a fresh
template clone. Do **not** retype the file-copy logic here or do it by hand; the script is
the single source of truth, so Claude Code and Codex install exactly the same files.

The universal skills (`work`, `research`, `commit`, `review`, `capture`, `ship`,
`setup`, `neobrutalist-pop`), reviewer agents (`code-reviewer`, `test-reviewer`,
`plan-reviewer`, `data-reviewer`, `security-reviewer`), and the durable philosophy doc
(`docs/PHILOSOPHY.md`) are overwritten with the template's versions on every run.
Domain-specific skills and agents already in `.claude/` are left alone. `CLAUDE.md` is
written only if missing. `AGENTS.md` is the Codex bridge: written if missing, its bounded
bridge block synced in place if already present, appended if the file exists without one.

`docs/PHILOSOPHY.md` is the canonical "why" doc behind the rules in `CLAUDE.md` — it
travels with every bootstrap so the conventions land even when an existing `CLAUDE.md` is
preserved.

Codex should not get a parallel rule set. `AGENTS.md` stays thin and delegates back to
`CLAUDE.md`, `docs/PHILOSOPHY.md`, and the `.claude/skills/` workflows so Claude Code and
Codex operate from the same project guidance. Codex auto-discovers skills only under
`.agents/skills`, so the project workflows reach Codex *through* the bridge (it reads
`.claude/skills/<name>/SKILL.md` when a workflow is invoked) rather than by duplicating
every skill file into a second directory — one source of truth, no drift.

This skill is **opinionated** — it doesn't ask which skills you want or whether you've
"customized" the universal ones. The bar is: "the standard workflow is the standard
workflow; if you want a divergence, edit after install." Manual backport discipline keeps
the template in sync (see Drift, below).

## Where this skill lives

The skill is installed globally for both agents, plus tracked in the template:

- **Claude Code**: `~/.claude/skills/bootstrap-harness/SKILL.md` — available in any repo.
- **Codex**: `~/.agents/skills/bootstrap-harness/SKILL.md` — available in any repo
  (Codex's user-level skills directory; invoke with `$bootstrap-harness`).
- **Template repo**: `bootstrap-harness/SKILL.md` — the source of truth that both global
  copies are installed from, alongside `scripts/install.sh`.

Only `SKILL.md` is installed into the global skill directories — never a copy of
`scripts/install.sh`. The installer is always run from the just-cloned template (Step 1),
so it can never be a stale local copy.

## Step 0: preconditions

```sh
git rev-parse --show-toplevel        # must be inside a git repo
```

- **Not a git repo** → refuse. The harness presumes a git repo underneath; offer to run
  `git init` if the user explicitly wants to start one. The skills drive version control
  through **Jujutsu, colocated** (PHILOSOPHY §28) — if the repo isn't jj yet, mention the
  user can run `jj git init --colocate` to opt in, but don't do it for them.
- **Inside a workspace / worktree of a repo we don't own** → ask before installing into
  someone else's submodule / vendored copy.

The template repo:
```
https://github.com/mauricedesaxe/claude-harness-template
```

## Step 1: fetch the template

Clone into a temp dir (depth 1, no LFS, no submodules). Don't reuse a stale local clone —
the template can change between runs, and bootstrapping with a stale copy is exactly the
kind of silent drift this whole system exists to prevent.

```sh
TMPDIR_HARNESS="$(mktemp -d -t claude-harness-XXXXXX)"
trap 'rm -rf "$TMPDIR_HARNESS"' EXIT
git clone --depth 1 https://github.com/mauricedesaxe/claude-harness-template.git \
  "$TMPDIR_HARNESS"
```

If the clone fails (offline, repo private/moved), surface the error and stop. Don't fall
back to a stale local copy — that would defeat the point.

## Step 2: run the installer

Run the shared installer from the freshly cloned template, targeting the repo root from
Step 0. It does every write and prints its own summary — relay that summary, don't
re-render it:

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"
bash "$TMPDIR_HARNESS/bootstrap-harness/scripts/install.sh" "$REPO_ROOT"
```

The script overwrites the universal files, preserves project-specific ones, handles
`CLAUDE.md` and `AGENTS.md`, updates `.gitignore`, and exits non-zero on any failure
(target not a git repo, a missing template source). If it fails, say which step and stop
— don't claim a partial install succeeded.

The temp clone is removed by the `trap` from Step 1 on exit.

## Installer contract (reference)

What the script writes, kept in sync with the template manifest. This section documents
behaviour; the script enforces it.

**Skills** — `.claude/skills/<name>/SKILL.md`, overwritten:
`work`, `research`, `commit`, `review`, `capture`, `ship`, `setup`, `neobrutalist-pop`
(and its `assets/brutpop.css`).

**Agents** — `.claude/agents/<name>.md`, overwritten:
`code-reviewer`, `test-reviewer`, `plan-reviewer`, `data-reviewer`, `security-reviewer`
(the security reviewer runs at review time only when the project's `CLAUDE.md` declares
`Commercial readiness: yes`, but is always installed).

**Docs** — `docs/PHILOSOPHY.md`, overwritten. The canonical "why" doc; it travels
independently of `CLAUDE.md` so the philosophy lands even when an existing `CLAUDE.md` is
preserved.

**`CLAUDE.md`** — copied from the skeleton only when missing. Present → left untouched
(the project owns it; it's its identity). The skeleton carries `<!-- TODO -->` markers for
the project-specific body (description, bar, architecture, runtime, area labels,
project-board IDs).

**`AGENTS.md`** — the Codex bridge. Missing → copied. Present with the
`<!-- BEGIN/END CLAUDE HARNESS CODEX BRIDGE -->` markers → the block between them is
**synced in place** to the template's current bridge (same overwrite-on-every-run contract
as the universal files). Present with a legacy heading (`Claude Mirror` /
`Claude Guidance Bridge`) but no markers → left as-is. Present with neither → the bridge is
appended, leaving the existing content intact.

**`.gitignore`** — `.jj/ws/` appended if absent (the `work`/`ship` skills create jj
workspaces under `.jj/ws/`; PHILOSOPHY §14 + §28).

Files in `.claude/` or `docs/` outside this manifest are left untouched — they're the
project's domain extensions, not the harness's.

## Drift policy

Improvements made to a universal skill or agent in *this* repo do **not** flow back to the
template automatically. The template is the source of truth; this skill installs *from*
it. The Claude Code and Codex global copies of `bootstrap-harness` should always be updated
from the same template checkout, not edited separately.

When you make an improvement worth keeping, PR it into the template repo
(`mauricedesaxe/claude-harness-template`). The next `/bootstrap-harness` (or
`$bootstrap-harness`) run picks it up everywhere.

This is on purpose — improvements come from many projects, and an auto-sync would fight
that. Manual backport discipline is the price of multi-project consistency.

When the change touches `scripts/install.sh`, run its smoke test before backporting —
there's no CI here to catch a regression in a script every bootstrap depends on:

```sh
bash bootstrap-harness/scripts/install.test.sh
```

## Don't

- **Don't** retype the installer's copy logic into the chat or do the writes by hand. Run
  `scripts/install.sh`; it's the single source of truth.
- **Don't** copy `scripts/install.sh` into a global skill directory. Only `SKILL.md` is
  installed globally; the installer is always run from the fresh clone.
- **Don't** ask the user to choose which universal skills to install. The whole point is
  "the standard workflow is the standard workflow". Edit after install if needed.
- **Don't** auto-merge into an existing `CLAUDE.md`. The user owns it; the installer leaves
  it untouched and `docs/PHILOSOPHY.md` carries the conventions regardless.
- **Don't** duplicate project rules into `AGENTS.md`. It is a Codex bridge; the durable
  project identity stays in `CLAUDE.md`.
- **Don't** mirror project skills into `.agents/skills` to make Codex see them. The
  `AGENTS.md` bridge already points Codex at `.claude/skills/`; a second copy is double
  state (PHILOSOPHY §26) and a drift source.
- **Don't** skip overwriting `docs/PHILOSOPHY.md`. It's universal and canonical — drift in
  the philosophy file is exactly what this skill exists to prevent. A local edit should
  have been a PR to the template repo, not an override.
- **Don't** delete or rename non-universal skills/agents. They're the project's and not
  yours to touch.
- **Don't** install if the target isn't a git repo. The harness presumes git.
- **Don't** fall back to a stale local clone if the fetch fails. Surface the error.
- **Don't** add a `Co-Authored-By` trailer or "Generated with Claude Code" line to any
  commit this skill writes — the harness's own commit policy forbids it.
