# AGENTS.md

Guidance for Codex and OpenAI agents working in this repository.

<!-- BEGIN CLAUDE HARNESS CODEX BRIDGE -->
## Claude Mirror

This repository is bootstrapped from `lazar-harness`. `CLAUDE.md` is the
canonical project guidance for both Claude Code and Codex. Treat it as if its
contents were copied here, unless higher-priority Codex instructions or a more
specific nested `AGENTS.md` conflicts.

At the start of substantive work:

- Read `CLAUDE.md`.
- Read the relevant `docs/PHILOSOPHY.md` (and its `docs/packs/*.md`) sections when
  `CLAUDE.md` references them or when a rule needs its reasoning. `§` numbers are stable
  IDs; the spine's Section index says which file each lives in.
- When the user invokes a workflow — `work`, `research`, `review`, `commit`, `ship`,
  `setup`, or `capture` (Codex: `$work`; Claude Code: `/work`) — read the matching
  `.claude/skills/<name>/SKILL.md` and follow it as workflow guidance. These skills
  live under `.claude/` and are intentionally not duplicated into `.agents/skills`;
  read them from here so there's a single source of truth.
- When a workflow references reviewer agents in `.claude/agents/`, use those files
  as the review prompt or checklist.

Keep durable project rules in `CLAUDE.md`. Keep this file thin; it exists so Codex
loads the same project guidance that Claude Code loads.
<!-- END CLAUDE HARNESS CODEX BRIDGE -->
