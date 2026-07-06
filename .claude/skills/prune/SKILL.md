---
name: prune
description: Periodic backlog hygiene (PHILOSOPHY §29) — the backlog is kept deliberately as re-entry state, so this culls only the genuinely dead while keeping everything still live. Proposes closes (stale, obsolete, superseded, no-longer-felt) and surfaces dups; never closes anything without the user's say-so. Use when the user says "/prune", "prune the backlog", "the backlog is bloated", "clean up the board", or "what's dead in here". Read-then-recommend: it gathers and proposes, the user approves.
---

# Prune (backlog hygiene)

Shape Up kills the backlog; we keep ours **deliberately** — it's the re-entry state for a
side project you don't touch daily (PHILOSOPHY §29). So `prune` is not "empty the backlog", it's
"keep it honest": cull the genuinely dead so the live items aren't buried, and never delete the
memory of work that's still real. A future agent must not tidy the backlog out of existence —
this skill is the *only* sanctioned cull, and it's user-approved every time.

## Step 1: gather (read-only)

The project board and repo coordinates are bound in CLAUDE.md (board ID/URL, owner, repo).
Prefix `gh` with `env -u GITHUB_TOKEN` when the ambient token lacks `project` scope.

```sh
env -u GITHUB_TOKEN gh issue list --repo <owner>/<repo> --state open \
  --limit 300 --json number,title,labels,milestone,updatedAt,url,body
env -u GITHUB_TOKEN gh project item-list <project-number> --owner <owner> --format json --limit 300
```

Focus on **Backlog** and **Icebox** items (and any open issue with no board item). Don't touch
anything **In progress**, **Ready to build**, or attached to an **active bet** (an open
milestone with a due date) — those are live by definition.

## Step 2: classify each candidate

Sort backlog/icebox items into:

- **Dead — propose close.** With a one-line reason from a readable source:
  - **Superseded** — another issue or a shipped PR already delivers its outcome (name it).
  - **Obsolete** — the code, app, or plan it referenced is gone (e.g. it names a retired
    service, a removed module, an abandoned approach).
  - **No-longer-felt** — re-run `capture`'s bar: if you can't still name the felt product
    outcome, it doesn't earn a slot. (This is the bar that lets it back in later too — closing
    isn't forever; a genuinely-felt need gets re-`capture`d, per §29's "re-pitch if it matters".)
  - **Stale + vague** — untouched for a long stretch *and* too thin to act on. Staleness alone
    is not death (the backlog is memory); stale **and** un-actionable is.
- **Duplicate — propose merge.** Point at the issue it duplicates; close the thinner one,
  keep the richer body.
- **Live — keep, untouched.** Everything still felt and actionable. The default. When unsure,
  **keep** — the backlog's whole job is to remember, and a wrong close costs more than a wrong keep.
- **Misfiled — propose a fix, not a close.** Live but in the wrong column / missing `app:*` /
  missing `area/*` / should be **Icebox** not Backlog. Note the fix.

## Step 3: propose (don't act)

Present a tight table — proposed closes with reasons, dups with their target, misfiles with the
fix. Nothing is mutated yet.

```
Prune proposal (<n> open backlog/icebox items):

Close (<k>):
  #<N> <title> — <superseded by #M | obsolete: <what's gone> | no-longer-felt | stale+vague>
  ...
Merge (<j>):
  #<N> → dup of #<M> (keep #<M>)
Fix (<i>):
  #<N> — <move to Icebox | add app:<x> | add area/<x>>

Keep: <rest> live, untouched.
```

## Step 4: act only on the user's say-so

After approval, close / relabel / move only the approved items. Closing a backlog issue is a
genuine outward action on shared GitHub state — confirm the set before running it, and use the
exact issue numbers from Step 1 (don't re-derive). On close, leave a one-line comment with the
reason so the memory of *why* it died survives, and set its board `Status` to **Done** (or
remove the board item for a pure dup). Refetch field/option IDs before any `gh project
item-edit` (see `capture`'s board section).

```sh
env -u GITHUB_TOKEN gh issue close <N> --repo <owner>/<repo> \
  --comment "Pruned: <reason>. Re-capture if it becomes felt again."
```

## Don't

- **Don't auto-close.** Every cull is user-approved. The backlog is memory; deleting it
  silently is the exact thing §29 forbids.
- **Don't touch live work** — anything In progress, Ready to build, or under an active bet.
- **Don't treat staleness alone as death.** Stale-but-still-felt stays; the backlog remembers
  where you left off precisely *because* you don't work this daily.
- **Don't lose the reason.** Every close carries a one-line why, so a re-`capture` later starts
  informed.
