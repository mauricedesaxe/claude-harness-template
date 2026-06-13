# Harness convergence design

Status: design reference for epic [#6](https://github.com/mauricedesaxe/claude-harness-template/issues/6).
Per PHILOSOPHY §21, design docs are temporary. The durable conclusions fold into
`docs/PHILOSOPHY.md` / the packs / `CLAUDE.md` as each slice lands; this file is
archived when #6 closes. It exists now because the work spans several PRs (#9, #10, and
v2-v4) that need one shared spec.

## The problem

Bringing the harness into a repo that already has its own guidelines, philosophy, or
skills currently forces a false choice: blunt overwrite (loses their rules) or blind
preserve (the harness conventions never land). Neither converges. The repos where this
bites are exactly the mature ones with established opinions of their own.

## Stance: guest, not owner

The harness is built to be the opinionated dictator ("the standard workflow is the
standard, overwrite"). That is correct greenfield and for repos the harness owns. The
moment it enters a repo with its own established philosophy it is a guest: it proposes,
and on a genuine contradiction the default is host-wins. You cannot walk into a
day-365 Mongo codebase and prescribe Postgres, and Mongo there is not a sin.

## Paradigm-aware (the spine/pack split)

`docs/PHILOSOPHY.md` was a paradigm-agnostic engineering spine wearing a web/backend
domain pack. Split it: a universal **spine** that always applies, plus **domain packs**
that apply when they match the repo's paradigm. A smart-contract or mobile repo takes
the spine and omits the web pack rather than being told "Postgres only" and "no
serverless." This split is what #9 delivers; `§` numbers are stable IDs and the spine's
Section index records where each lives.

## Maturity-aware

Existing decisions win. The repo's committed stack and platform are fixed inputs, not
deviations to correct. Day-1 you might choose Postgres; day-365 with Mongo load-bearing,
the harness does not get to prescribe Postgres.

## Convergence is semantic, not mechanical

All file-level schemes (managed blocks, extends-by-reference, 3-way merge, core
extraction) converge *bytes*, not *rules*. None of them decides what happens when the
harness says "return Result, never throw" and the repo says "throw everywhere." That
decision is the actual convergence, and it needs an LLM step in the SKILL (bash cannot),
human-gated. The Copier/Cruft recorded-base machinery was considered and rejected as the
primary mechanism: it over-applies to template-owned files and carries a corruptible
version pin; the spine/pack split removes the files it was meant to save.

## Auto-apply, gate on conflict

Bootstrap auto-applies the unambiguous (the spine, the matching pack adapted to existing
choices, tooling with no collision, skipping irrelevant rules) and gates on human
approval **only** for genuine contradictions and real merge situations. No friction on
the clear stuff; no silent resolution on the hard stuff. This makes reliable conflict
*classification* the load-bearing capability, a lower bar than full auto-resolution.

## Tooling has four outcomes

For a skill or agent that collides with one the repo already has: take ours, keep theirs,
keep both, or **converge into a new merged skill**. The converge option is the same
semantic-merge capability the rules need, with the unit being a skill file instead of a
rule.

## New paradigms grow the harness

First contact with a paradigm that has no domain pack (smart contracts, mobile) drafts
one from the repo plus human input, which backports to the template so the harness learns
the paradigm once.

## Bash vs SKILL split

The bash installer stays deterministic, fail-loud, and LLM-free: it does the mechanical
writes, stages files that need judgment into a gitignored dir, and emits machine-readable
classification lines. The SKILL does the assessment, surfaces contradictions verbatim
with host-wins defaults, and writes the converged result only after the human ratifies.

## Conflict / failure UX

When both sides changed the same rule, the SKILL surfaces both texts verbatim with their
sources and a one-line why, offering keep-host / take-harness / model-authored-compromise
(the compromise clearly marked unverified). Nothing is rewritten until the human chooses;
the default if they skip is host-wins.

## Roadmap

- **v1** — paradigm/maturity assessment + guest-mode apply-and-gate.
  - #9 (this slice): spine/pack split, stable §-index, installer + test, this doc.
  - #10: bootstrap assesses the repo and applies as a guest, gating on conflicts.
- **v2** — richer auto-convergence of rules once the conflict-classification spike (#8)
  proves out.
- **v3** — tooling convergence including converge-into-new-skill (same engine).
- **v4** — draft-a-pack flow for unsupported paradigms + backport.

## Known limitation (deferred to #10)

The `CLAUDE.md` skeleton body still inlines web defaults (Architecture defaults, Hosting,
External integrations, Frontend) as if universal. #9 only repoints its Philosophy section
at the spine + packs. Scoping the skeleton body behind the same pack boundary is part of
#10.

## Open questions / spikes before committing the harder slices

- **#7 — paradigm + maturity assessment reliability.** Can an agent reliably classify a
  repo's paradigm and committed stack? If not, the assessment step is sand.
- **#8 — conflict classification + convergence trust.** Is classification (clean-apply
  vs genuine contradiction) trustworthy enough to gate on?
- **`@`-import reliability.** If a pointer in `CLAUDE.md` imports pack/spine content,
  confirm the rules actually reach the agent's context (keep the chain shallow). Do not
  stake conflict resolution on `@`-import "proximity/recency precedence" — that is
  folklore, not spec.
