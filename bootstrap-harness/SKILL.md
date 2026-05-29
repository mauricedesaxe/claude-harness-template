---
name: bootstrap-harness
description: Install the Claude harness (universal skills, reviewer agents, CLAUDE.md skeleton) from claude-harness-template into the current repo. Use when the user says "/bootstrap-harness", "set up the harness here", "install the skills + agents in this repo", or when starting a new project that should follow the standard workflow (work → review → ship, atomic conventional commits, plan-reviewer, code-reviewer, test-reviewer).
---

# Bootstrap Harness

Install the portable parts of the `claude-harness-template` into the current repo. The
universal skills (`work`, `commit`, `review`, `capture`, `ship`, `setup`,
`neobrutalist-pop`) and reviewer agents (`code-reviewer`, `test-reviewer`,
`plan-reviewer`) are overwritten with the template's versions. Domain-specific skills
and agents already in `.claude/` are left alone. `CLAUDE.md` is written only if missing.

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

- **Not a git repo** → refuse. The harness presumes a git workflow; offer to run
  `git init` if the user explicitly wants to start one.
- **Inside a worktree of a repo we don't own** → ask before installing into someone
  else's submodule / vendored copy.

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

For each, overwrite the file at the target path with the template's copy. Leave any
sibling skill/agent in `.claude/` (e.g. `.claude/agents/payments-reviewer.md`,
`.claude/skills/run-evals/`) untouched — those are domain-specific and belong to the
project.

```sh
mkdir -p .claude/skills .claude/agents

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
for a in code-reviewer test-reviewer plan-reviewer; do
  cp "$TMPDIR_HARNESS/.claude/agents/$a.md" ".claude/agents/$a.md"
done
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

- **Present** → don't touch it. Print a pointer:
  > "Found existing `CLAUDE.md` — preserved. The template skeleton is at
  > `$TMPDIR_HARNESS/CLAUDE.md` if you want to diff against it for sections you might
  > want to adopt (Hard rules, Type system, Testing, Git workflow, Style, Issue
  > triage shape)."

  Don't auto-merge. The project's `CLAUDE.md` is its identity — the user owns it.

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

  CLAUDE.md: <added skeleton | preserved existing>

  Preserved (project-specific, untouched):
    <list any .claude/skills/* or .claude/agents/* not in the universal manifest>

Next:
  - Fill the <!-- TODO --> markers in CLAUDE.md (if added).
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
- **Don't** delete or rename non-universal skills/agents. They are the project's
  domain extensions and not yours to touch.
- **Don't** install if the target isn't a git repo. The harness presumes git.
- **Don't** fall back to a stale local clone if the fetch fails. Surface the error.
- **Don't** add a `Co-Authored-By` trailer or "Generated with Claude Code" line to
  any commit this skill writes — the harness's own commit policy forbids it.
