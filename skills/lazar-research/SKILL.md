---
name: lazar-research
description: >
  Answer an issue's open questions without implementing it, and hand back a verdict-first
  write-up. Web research goes to /deep-research, runnable questions go to a throwaway prototype.
  Never closes the issue. Use when I say "/lazar-research", "research #12", "look into
  ICON-147", "investigate this issue", "is X feasible", or want an issue explored before we
  commit to an approach.
---

# lazar-research

Answer the questions an implementation would trip over, then hand me the verdict.

Most of the work belongs to skills someone else maintains. Your job is to aim them at the right
questions and to synthesize what comes back.

## 1. Read the issue

Resolve the tracker per **Tracker resolution** in `CLAUDE.md`. Then read the issue with that
tracker's own tooling: `gh issue view` on GitHub, the Linear MCP on Linear, and so on. Read
the comments too. Prior research often already lives there. A closed issue is still worth
researching.

The arg is an issue ref in whatever key format that tracker uses, optionally followed by
questions I want pinned. A bare question with no issue is fine too.

Pull out the thing the issue is actually blocked on: what has to be true before anyone can
commit to an approach. That uncertainty is the target.

## 2. Split the questions by method

Turn the target into 3 to 7 falsifiable questions, and sort each into a lane:

- **The open web** (docs, upstream issues, prior art, how a thing is normally measured) →
  `/deep-research`.
- **Runnable** ("is the data actually shaped like that", "does this state model hold") →
  the Prototype playbook in `pstack-poteto-mode`.
- **This codebase** → read it yourself. It's cheap, and it's the lane where the issue's framing
  turns out to be wrong about the current code. Catching that is a finding.

Show me the split before you spend anything on it. Going deep on the wrong question is the
expensive mistake this skill exists to avoid.

## 3. Delegate

Hand each web question to **`/deep-research`**, one question per run, phrased specifically.
Don't run its pipeline by hand alongside it. It's a workflow bundled with Claude Code, so if it
isn't available where you're running, say so rather than quietly reimplementing it.

Hand each runnable question to the Prototype playbook in `pstack-poteto-mode`
(`playbooks/prototype.md`). A probe that measures something shouldn't turn into code I keep by
accident, and that playbook builds throwaway sketches for exactly this.

Synthesize what comes back yourself. A finding you can't trace to a source or a probe is worse
than no finding.

## 4. Hand back the verdict, first

In chat, in this order:

1. **Verdict.** Feasible, not, or feasible with caveats, plus the direction you'd take. If I
   stop reading here I still know what to do.
2. **What the evidence showed.** The findings that moved the verdict, each with its source or
   its probe.
3. **What we can't do.** The honest limits, specifically.
4. **The questions you pursued**, so I can see whether you aimed right.

Don't walk me through the reasoning and reveal the answer at the end.

If the verdict looks clean, aim one more probe at breaking it before you hand it over. A
conclusion that agrees with what we hoped isn't tested yet.

Write a doc, comment on the issue, or file a follow-up only if I ask for it. The answer comes
first.

## Don't

- **Don't close the issue**, reopen it, or move it to done. Not directly, and not with a
  `Closes` in a commit or a PR body. Deciding is mine.
- **Don't implement it.** A production change the research concludes is needed is a finding, not
  an edit.
- **Don't soften a negative verdict.** "Don't build this" is a good outcome, and it's often the
  one I'm paying for.
