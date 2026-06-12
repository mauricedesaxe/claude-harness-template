# AGENTS.md

Guidance for Codex and OpenAI agents working in this repository.

<!-- BEGIN CLAUDE HARNESS CODEX BRIDGE -->
## Claude Mirror

This repository is bootstrapped from `claude-harness-template`. `CLAUDE.md` is the
canonical project guidance for both Claude Code and Codex. Treat it as if its
contents were copied here, unless higher-priority Codex instructions or a more
specific nested `AGENTS.md` conflicts.

At the start of substantive work:

- Read `CLAUDE.md`.
- Read the relevant `docs/PHILOSOPHY.md` sections when `CLAUDE.md` references them
  or when a rule needs its reasoning.
- When the user invokes a workflow such as `/work`, `/research`, `/review`,
  `/commit`, `/ship`, `/setup`, or `/capture`, read the matching
  `.claude/skills/<name>/SKILL.md` and follow it as workflow guidance.
- When a workflow references reviewer agents in `.claude/agents/`, use those files
  as the review prompt or checklist.

Keep durable project rules in `CLAUDE.md`. Keep this file thin; it exists so Codex
loads the same project guidance that Claude Code loads.
<!-- END CLAUDE HARNESS CODEX BRIDGE -->
