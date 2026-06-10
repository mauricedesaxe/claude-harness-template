---
name: bootstrap-harness
description: Install the Claude harness (universal skills, reviewer agents, CLAUDE.md skeleton) from claude-harness-template into the current repo. Use when the user says "/bootstrap-harness", "set up the harness here", "install the skills + agents in this repo", or when starting a new project that should follow the standard workflow (work → review → ship, atomic conventional commits, plan-reviewer, code-reviewer, test-reviewer).
---

# Bootstrap Harness

Install the portable parts of the `claude-harness-template` into the current repo. The
universal skills (`work`, `commit`, `review`, `capture`, `ship`, `setup`,
`neobrutalist-pop`), reviewer agents (`code-reviewer`, `test-reviewer`,
`plan-reviewer`), and the durable philosophy doc (`docs/PHILOSOPHY.md`) are overwritten
with the template's versions on every run. Domain-specific skills and agents already in
`.claude/` are left alone. `CLAUDE.md` is written only if missing.

`docs/PHILOSOPHY.md` is the canonical "why" doc behind the rules in `CLAUDE.md` —
it travels with every bootstrap so the conventions land in the target repo even when
an existing `CLAUDE.md` is preserved.

This skill is **opinionated** — it doesn't ask which skills you want or whether you've
"customized" the universal ones. The bar is: "the standard workflow is the standard
workflow; if you want a divergence, edit after install." Manual backport discipline
keeps the template in sync (see Drift, below).

The skill lives in two places:

- **Globally** at `~/.claude/skills/bootstrap-harness/SKILL.md` so it's available in
  any repo.
- **In the template repo** at `bootstrap-harness/SKILL.md` for reference and
  version-tracking. The global copy is the one that runs; the in-template copy is the
  one that gets edited and back-installed.

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

Clone into a temp dir (depth 1, no LFS, no submodules). Don't reuse a stale local clone
— the template can change between runs, and bootstrapping with a stale copy is exactly
the kind of silent drift this whole system exists to prevent.

```sh
TMPDIR_HARNESS="$(mktemp -d -t claude-harness-XXXXXX)"
git clone --depth 1 https://github.com/mauricedesaxe/claude-harness-template.git \
  "$TMPDIR_HARNESS"
```

If the clone fails (offline, repo private/moved), surface the error and stop. Don't
fall back to a stale local copy — that would defeat the point.

## Step 2: install — overwrite universal, preserve everything else

The universal manifest (kept in sync with what's in the template):

**Skills** — `.claude/skills/<name>/SKILL.md`:
- `work`
- `commit`
- `review`
- `capture`
- `ship`
- `setup`
- `neobrutalist-pop` (and its `assets/brutpop.css`)

**Agents** — `.claude/agents/<name>.md`:
- `code-reviewer`
- `test-reviewer`
- `plan-reviewer`
- `data-reviewer`
- `security-reviewer` (conditional at review time — runs only when the project's
  `CLAUDE.md` declares `Commercial readiness: yes`; the agent itself self-checks
  the declaration. Always installed regardless of project flavor.)

**Docs** — top-level:
- `docs/PHILOSOPHY.md` — durable "why" doc, always overwritten. See Step 3 for the
  reason this travels independently of `CLAUDE.md`.

For each, overwrite the file at the target path with the template's copy. Leave any
sibling skill/agent in `.claude/` (e.g. `.claude/agents/payments-reviewer.md`,
`.claude/skills/run-evals/`) untouched — those are domain-specific and belong to the
project. Leave any sibling docs in `docs/` untouched.

```sh
mkdir -p .claude/skills .claude/agents docs

# Universal skills
for s in work commit review capture ship setup neobrutalist-pop; do
  mkdir -p ".claude/skills/$s"
  cp "$TMPDIR_HARNESS/.claude/skills/$s/SKILL.md" ".claude/skills/$s/SKILL.md"
done
# Assets for neobrutalist-pop
mkdir -p .claude/skills/neobrutalist-pop/assets
cp "$TMPDIR_HARNESS/.claude/skills/neobrutalist-pop/assets/brutpop.css" \
   .claude/skills/neobrutalist-pop/assets/brutpop.css

# Universal agents
for a in code-reviewer test-reviewer plan-reviewer data-reviewer security-reviewer; do
  cp "$TMPDIR_HARNESS/.claude/agents/$a.md" ".claude/agents/$a.md"
done

# Universal docs
cp "$TMPDIR_HARNESS/docs/PHILOSOPHY.md" docs/PHILOSOPHY.md

# Workspace-first workflow (PHILOSOPHY §14 + §28): the work/ship skills create jj
# workspaces under .jj/ws/ — make sure they never show up as untracked noise
grep -qxF '.jj/ws/' .gitignore 2>/dev/null || \
  echo '.jj/ws/' >> .gitignore
```

Track what was written vs already-existed (for the Step 5 summary): a file that existed
before this run and was overwritten is **updated**; one that did not exist is **added**.

## Step 3: handle CLAUDE.md

```sh
test -f CLAUDE.md && echo present || echo missing
```

- **Missing** → write the template's skeleton:
  ```sh
  cp "$TMPDIR_HARNESS/CLAUDE.md" CLAUDE.md
  ```
  The skeleton has `<!-- TODO -->` markers for the project-specific body (description,
  bar, architecture, runtime, area labels, project-board IDs). The user fills those in.
  The skeleton references `docs/PHILOSOPHY.md` (just installed by Step 2) for the
  durable conventions.

- **Present** → don't touch it. Print a pointer:
  > "Found existing `CLAUDE.md` — preserved. The template skeleton is at
  > `$TMPDIR_HARNESS/CLAUDE.md` if you want to diff against it for sections you might
  > want to adopt (Philosophy pointer, Architecture defaults, Hosting & deployment,
  > Web architecture, Hard rules, External integrations & concurrency primitives,
  > Issue triage shape). `docs/PHILOSOPHY.md` was overwritten regardless and is the
  > canonical source of the durable conventions, so the existing `CLAUDE.md` does not
  > need to repeat them — pointing at the PHILOSOPHY.md sections is enough."

  Don't auto-merge. The project's `CLAUDE.md` is its identity — the user owns it.
  `docs/PHILOSOPHY.md` carries the durable conventions independently, so the
  philosophy still lands.

## Step 4: clean up

```sh
rm -rf "$TMPDIR_HARNESS"
```

Don't leave the temp clone behind even on failure — surface the error first, then clean.

## Step 5: report

Print a summary:

```
✓ Installed claude-harness from claude-harness-template

  Skills (universal, overwritten):
    .claude/skills/work/SKILL.md            (updated | added)
    .claude/skills/commit/SKILL.md          (updated | added)
    .claude/skills/review/SKILL.md          (updated | added)
    .claude/skills/capture/SKILL.md         (updated | added)
    .claude/skills/ship/SKILL.md            (updated | added)
    .claude/skills/setup/SKILL.md           (updated | added)
    .claude/skills/neobrutalist-pop/        (updated | added — SKILL.md + assets/brutpop.css)

  Agents (universal, overwritten):
    .claude/agents/code-reviewer.md         (updated | added)
    .claude/agents/test-reviewer.md         (updated | added)
    .claude/agents/plan-reviewer.md         (updated | added)
    .claude/agents/data-reviewer.md         (updated | added)
    .claude/agents/security-reviewer.md     (updated | added)

  Docs (universal, overwritten):
    docs/PHILOSOPHY.md                      (updated | added)

  .gitignore: .jj/ws/                       (added | already present)

  CLAUDE.md: <added skeleton | preserved existing>

  Preserved (project-specific, untouched):
    <list any .claude/skills/* or .claude/agents/* not in the universal manifest>

Next:
  - Fill the <!-- TODO --> markers in CLAUDE.md (if added).
  - Read docs/PHILOSOPHY.md if you haven't recently — it's the canonical source for
    the durable conventions referenced from CLAUDE.md.
  - Review the universal skills/agents; tune to taste and back-port useful edits to
    the template repo (see Drift, below).
```

If a step failed, say which and stop — don't claim success on a partial install.

## Drift policy

Improvements made to a universal skill or agent in *this* repo do **not** flow back to
the template automatically. The template is the source of truth; this skill installs
*from* it.

When you make an improvement worth keeping, PR it into the template repo
(`mauricedesaxe/claude-harness-template`). The next `/bootstrap-harness` run picks it
up everywhere.

This is on purpose — improvements come from many projects, and an auto-sync would
fight that. Manual backport discipline is the price of multi-project consistency.

## Don't

- **Don't** ask the user to choose which universal skills to install. The whole point
  is "the standard workflow is the standard workflow". Edit after install if needed.
- **Don't** auto-merge into an existing `CLAUDE.md`. Diff yourself; the user owns it.
- **Don't** skip overwriting `docs/PHILOSOPHY.md`. It's universal and the
  canonical source — drift in the philosophy file is exactly what this skill exists
  to prevent. If the user has edited `docs/PHILOSOPHY.md` in a target project, that
  edit should have been a PR to the template repo, not a local override.
- **Don't** delete or rename non-universal skills/agents. They are the project's
  domain extensions and not yours to touch.
- **Don't** touch other files under `docs/` — only `docs/PHILOSOPHY.md` is in the
  manifest. Project-specific docs (PRDs, ADRs, runbooks) belong to the project.
- **Don't** install if the target isn't a git repo. The harness presumes git.
- **Don't** fall back to a stale local clone if the fetch fails. Surface the error.
- **Don't** add a `Co-Authored-By` trailer or "Generated with Claude Code" line to
  any commit this skill writes — the harness's own commit policy forbids it.
