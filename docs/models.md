# Model roles

pstack's fan-out skills (`pstack-interrogate`, `pstack-arena`, `pstack-architect`, `pstack-swarm`, `pstack-how`, `pstack-why`) delegate to
subagents by **role**, never by a hardcoded vendor slug. This file is the harness equivalent of
pstack's `~/.cursor/rules/pstack-models.mdc`. It names the roles, gives a default per runtime, and
states how a role resolves at run time.

The harness runs in three runtimes with different providers. Claude Code has Anthropic only.
OpenCode and the `background-agents` OpenInspect fork use GLM, OpenAI, and OpenRouter. So a role
resolves to a different slug depending on where the skill runs, and the skills must degrade rather
than break when only one provider exists.

## The roles

Five roles cover every delegation. Four are single models. One is a panel (a list), and the list
length sets the fan-out count.

- **`code`** — the default implementation delegate.
- **`code-hard`** — cross-cutting design, gnarly concurrency, subtle algorithms. The strongest
  judgment model when the task needs judgment or the intent is vague.
- **`code-fast`** — trivial mechanical edits.
- **`judge`** — prose, synthesis, and judgment. The lead-reviewer, cross-judge, and synthesizer
  role. Also the base for any skill that scores or writes.
- **`pool`** — the diversity panel every adversarial skill draws from: `pstack-interrogate` reviewers,
  `pstack-arena` and `pstack-architect` runners, `pstack-how` critics. One subagent runs per entry. The **cross-judge**
  is one pick from `pool`, preferring a family different from the parent's.

A skill that names a narrower pstack role (`how explorer`, `why investigator`, `swarm worker`) maps
onto these: exploration and worker roles use `code`, synthesis and explanation use `judge`.

## Resolution

A skill resolves a role in this order, first hit wins:

1. **The machine-local override** at `~/.lazar-harness/models.md`, when present. This is per machine
   and no installer owns it, exactly like the tracker note. Edit it to your real slugs for this
   machine's providers. A role with no line falls through.
2. **The runtime default block below** for the runtime the skill is running in.
3. **The parent chat model.** With no default either, the subagent omits its `model` and inherits
   the parent. That is always safe.

The machine-local override uses the same shape as a runtime block:

```
# ~/.lazar-harness/models.md
code: glm-4.6
code-hard: gpt-5-codex
code-fast: glm-4.5-air
judge: gpt-5
pool: glm-4.6, gpt-5, deepseek-v3, gemini-2.5-pro
```

## Runtime defaults

### Claude Code (Anthropic only)

Stable aliases, so these need no per-machine editing.

```
code: sonnet
code-hard: opus
code-fast: haiku
judge: opus
pool: opus, sonnet
```

Vendor diversity is thin here. `pool` is tier-diverse, not vendor-diverse, so the adversarial
signal from `pstack-interrogate` and `pstack-arena` is weaker than it is under OpenCode. The skills say so in
their output when they run against a thin pool.

### OpenCode and background-agents (GLM / OpenAI / OpenRouter)

These are placeholders. Set your real slugs in the machine-local override above, because the
available slugs differ per machine and per subscription.

```
code: <your GLM slug>
code-hard: <your strongest OpenAI or GLM slug>
code-fast: <your fast GLM slug>
judge: <your OpenAI slug>
pool: <GLM slug>, <OpenAI slug>, <optional OpenRouter: deepseek / gemini / minimax>
```

Real vendor diversity is available here, so `pool` should list slugs from different vendors. That is
where `pstack-interrogate` and `pstack-arena` earn the most.

## Degradation

A fan-out skill uses whatever `pool` lists. It never hard-requires a second vendor.

- **`pool` has one entry.** The skill runs that model N times. Parallel coverage survives, the
  cross-model disagreement signal does not. The skill states that its diversity was thin, so its
  verdict reads as lower-confidence.
- **A listed slug is unresolvable at run time.** The skill drops it, proceeds with the rest, and
  notes the drop. It never blocks the run on one bad slug.

Diversity is best-effort, and the harness prefers a degraded run with an honest caveat over a run
that refuses to start.
