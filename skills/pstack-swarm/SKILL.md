---
name: pstack-swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /pstack-swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration."
---

# Swarm

Fan out N parallel workers. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report. In Claude Code and OpenCode the workers are local background subagents; the background-agents runtime can run them as real cloud workers.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare `first pass`, `rank all`, or `best-of` before spawning.
3. Set N from the user or derive it from the shape. N is total workers, not the concurrency limit.
4. Pick the worker model from the `code` role in `models.md`, resolved through `~/.lazar-harness/models.md` when present. For a model race, name each arm's model up front.
5. Give each worker its own writable output when it writes. Use a jj workspace, branch, or `/tmp/swarm-<slug>/worker-<n>/`.

## Phase B: Fan out

Spawn all N workers in one message with `subagent_type: general-purpose`, `run_in_background: true`, and the configured model. Each worker gets its own jj workspace or output path (`§28`, pstack-principle-separate-before-serializing-shared-state). On the background-agents runtime these can run as real cloud workers; in Claude Code and OpenCode they run locally.

When a worker must start from a non-default pushed branch, base its workspace on that branch: `jj git fetch` then `jj workspace add --revision <branch>`.

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence.

If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read the terminal results. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.
