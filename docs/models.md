# Model roles

pstack's fan-out skills (`pstack-interrogate`, `pstack-arena`, `pstack-architect`, `pstack-swarm`,
`pstack-how`, `pstack-why`) delegate to subagents by **role**, never by a hardcoded vendor slug. This
file names the roles, gives a real default per runtime, and states how a role resolves at run time.

The harness runs in three runtimes with different providers. Claude Code uses Anthropic. OpenCode and
the `background-agents` OpenInspect fork use OpenAI, with GLM (Z.AI) as the fallback when OpenAI
credits run out. So a role resolves to a different slug depending on where the skill runs, and the
skills degrade rather than break when only one provider is available.

## The roles

Five roles cover every delegation. Four are single models. One is a panel (a list), and the list
length sets the fan-out count. The harness thinks in two tiers, **hard** and **normal**, so most
roles collapse onto one of those two models.

- **`code`** — the default implementation delegate. The **normal** model.
- **`code-hard`** — cross-cutting design, gnarly concurrency, subtle algorithms. The **hard** model.
- **`code-fast`** — trivial mechanical edits. The **normal** model, unless a cheaper one is set.
- **`judge`** — prose, synthesis, and judgment (lead-reviewer, cross-judge, synthesizer). The
  **hard** model, because judging is a hard problem.
- **`pool`** — the diversity panel every adversarial skill draws from: `pstack-interrogate`
  reviewers, `pstack-arena` and `pstack-architect` runners, `pstack-how` critics. One subagent runs
  per entry. The **cross-judge** is one pick from `pool`, preferring a family different from the
  parent's.

A skill that names a narrower pstack role (`how explorer`, `why investigator`, `swarm worker`) maps
onto these: exploration and worker roles use `code`, synthesis and explanation use `judge`.

## Resolution

Everything is keyed by runtime, because one machine runs several runtimes with different providers. A
skill resolves a role in this order, first hit wins:

1. **The machine-local file** at `~/.lazar-harness/models.md`, the block for the runtime the skill is
   running in. `install.sh` seeds this file from the defaults below on the first install and never
   overwrites it again, so it is yours to edit per machine (the OpenAI-vs-GLM swap lives here). No
   installer owns it after that, exactly like the tracker note.
2. **The runtime default block below**, for the same runtime. This is the shipped fallback, and it is
   re-installed to `rules/models.md` on every run, so a deleted or partial machine-local file still
   resolves to something real.
3. **The parent chat model.** With no line either place, the subagent omits its `model` and inherits
   the parent. Always safe.

Each block is a runtime heading followed by one `role: slug` line per role. `pool` takes a
comma-separated list.

## Runtime defaults

### Claude Code (Anthropic)

Aliases, so no per-machine editing is needed. `opus` is Opus 4.8, `fable` is Fable 5.

```
code: opus
code-hard: fable
code-fast: opus
judge: fable
pool: fable, opus
```

Vendor diversity is thin here (one vendor), so `pool` is tier-diverse across Fable and Opus, not
vendor-diverse. The adversarial signal from `pstack-interrogate` and `pstack-arena` is weaker than it
is under OpenCode, and the skills say so when they run against a thin pool.

### OpenCode and background-agents (OpenAI, GLM fallback)

OpenAI is the default. When you are out of OpenAI credits, comment the OpenAI lines and uncomment the
GLM ones in your `~/.lazar-harness/models.md`. Slugs are `provider/model`.

```
code: openai/gpt-5.6-terra
code-hard: openai/gpt-5.6-sol
code-fast: openai/gpt-5.6-terra
judge: openai/gpt-5.6-sol
pool: openai/gpt-5.6-sol, openai/gpt-5.6-terra

# GLM fallback (Z.AI Coding Plan, needs ZHIPU_API_KEY). Confirm the exact slugs for your plan.
# code: <glm-normal-slug>
# code-hard: <glm-hard-slug>
# code-fast: <glm-normal-slug>
# judge: <glm-hard-slug>
# pool: <glm-hard-slug>, <glm-normal-slug>
```

Real cross-vendor diversity is available here, so a mixed `pool` (OpenAI plus GLM) is where
`pstack-interrogate` and `pstack-arena` earn the most.

## Degradation

A fan-out skill uses whatever `pool` lists. It never hard-requires a second vendor.

- **`pool` has one entry.** The skill runs that model N times. Parallel coverage survives, the
  cross-model disagreement signal does not. The skill states that its diversity was thin, so its
  verdict reads as lower-confidence.
- **A listed slug is unresolvable at run time** (no credits, wrong key). The skill drops it, proceeds
  with the rest, and notes the drop. It never blocks the run on one bad slug.

Diversity is best-effort, and the harness prefers a degraded run with an honest caveat over a run
that refuses to start.
