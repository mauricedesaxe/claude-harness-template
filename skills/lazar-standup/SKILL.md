---
name: lazar-standup
description: >
  Draft my daily standup update ("3 Ps": Progress, Problems, Priorities) in my voice,
  for whatever repo I'm in, with links to the PRs and issues it references. Reconciles
  what landed since the last standup against open PRs, my assigned issues, and work
  that only exists on this machine. Use when I say "/lazar-standup", "write my 3 Ps",
  "standup update", "daily update", or "what's my progress/problems/priorities today".
---

# lazar-standup

Draft my daily standup post. Three sections: **Progress**, **Problems**, **Priorities**.
**Always deliver it as raw markdown inside a fenced code block** (see Format) — never as
already-rendered prose.

Nothing here is pinned to one repo or one team. Infer the repo, the tracker, my identity,
the issue-key format and the destination, then gather.

## What to infer

- **Repo** — from the remote: `git remote get-url origin`, normalised to `<host>/<owner>/<repo>`.
- **Tracker and issue-key format** — resolve per **Tracker resolution** in `CLAUDE.md`.
- **Author** — from the API, never hardcoded. GitHub: `gh api user --jq .login`. Linear: the
  viewer, via `mcp__linear__list_my_issues` or the equivalent.
- **Destination** — where the post goes (a Slack channel, the tracker, a doc). The note records
  it if I've said before. If not, ask, and write the answer to the note.

## How to gather

1. Resolve repo, tracker, author, destination as above. Connect the tracker's MCP if it isn't
   already (authenticate if needed).

2. **Progress = what actually changed since the last standup, stated honestly about its state.**
   Gather from both sides and reconcile them:

   - **Remote.** `gh pr list --author <login> --state merged --limit 10 --json number,title,mergedAt`
     for what landed, plus the tracker's equivalent (issues I moved or closed). Plus any
     substantial non-PR work I mention (reviews, planning, investigation).
   - **Local.** Work that only exists on this machine is still progress, and it's often the
     honest answer to what I'm doing today. Read the working copy and the commits that aren't
     on any remote, whichever VCS the repo uses:

     ```bash
     # jj — use it whenever .jj exists (a colocated repo has both, jj is the working copy)
     jj st
     jj log -r 'mine() & ~::trunk() & ~::remote_bookmarks()'   # my commits on no remote
     jj workspace list                                         # other workspaces' @ are mine too

     # git
     git status --short
     git log --oneline --branches --not --remotes              # commits on no remote
     git worktree list
     ```

   - **Reconcile.** A local branch or stack whose PR is already open is the PR's story, not a
     second bullet — phrase it by the PR's state. A stack with no PR yet is work in progress.
     Don't double-count the same work once as local and once as remote.

3. **Problems:** only things someone other than me could act on — a dependency not ready, a
   decision I'm waiting on from the team, an environment issue affecting others. My own gating
   tasks (re-recording cassettes, finishing my own PR) are not problems. Usually `none rn`.

4. **Priorities:** check each open PR's draft state
   (`gh pr list --author <login> --state open --json number,title,isDraft,baseRefName,headRefName`)
   and phrase the action to match it (open vs finish+open vs land — see the phrasing rule in
   Rules). Plus the next issues I'm picking up. Note stacking when one builds on another.

5. If I've just planned my day in another skill, pull the priorities straight from the plan I
   picked.

Confirm the draft with me before I post it — this goes out under my name to a team.

## Format

- Open with my greeting — `Morning everyone :sun_with_face:` or `Hello hello :sun_with_face:`. I vary it; pick by time of day, and drop the "morning" wording if I'm posting later.
- Three headers: **Progress**, **Problems**, **Priorities**.
- Lowercase, terse fragment bullets. Not full sentences. Real lines of mine:
  - `landed PR#299 (strategic summary, ICON-49)`
  - `start the Clarity preprocessing pipeline (WCO) for ICON-147 stacked on PR#316 (office extraction)`
  - `mapped out where artefact submission + strategic summary actually stand, what's blocked vs what i can pick up`
- **One item per line.** Never combine two issues or PRs on one line ("ICON-148 and ICON-146 …") — split them into separate lines, even when the action is the same.
- **Links (settled 2026-07-16 — Slack now renders markdown):** I turned on markdown rendering in my Slack, so inline markdown links `[text](url)` now work and are the format I want from now on. Wrap the ref word itself in the link, with the short parenthetical name in plain text after it:
  - PRs: `[PR#<n>](<repo-url>/pull/<n>)`, built from the inferred repo — e.g. `land [PR#369](https://github.com/iconicshift/platform/pull/369) (conflict detection, ICON-286)`.
  - Tracker issues: `[<KEY>](<full issue url>)` in the repo's own key format — e.g. `started on [ICON-93](https://linear.app/iconicshift/issue/ICON-93/context-capture-recovery-loop) (context capture recovery loop)`. Use the real URL the tracker's API returns (Linear's `url` field carries the slug; the slug-less `…/issue/ICON-93` form is not what I use). On a GitHub-tracked repo the key is `#<n>` and the URL is the issue URL.
  - I still copy the post as raw markdown **source** (from the fenced code block), so the markdown links paste straight into Slack and render there — that's why the whole thing must stay in a code block.
  - Inline markdown links don't fire Slack's unfurl previews, so the old "only first 5 previews are shown" caveat no longer applies. Nothing to restructure or work around.
- **Still hand me the whole post as raw markdown inside a fenced code block**, so I copy the source rather than a rendered preview.

## Rules

- **A problem is something someone OTHER than me could or should act on.** A genuine problem is cross-team: I'm blocked on a person or a dependency, waiting on a decision, or hitting a team-wide nuisance — something where listing it prompts someone else to do something. Work I can handle entirely on my own is NOT a problem, even when it's hard, tedious, or gating my own other work (e.g. "I still have to re-record my cassettes" is my own task, not a problem). When in doubt, ask: could anyone but me move this? If no, it's not a problem.
- **Do NOT put review requests in Problems.** A PR needing review belongs in Priorities, not Problems. (It came out of the Iconic team asking to stop listing "need a review on PR#X" as a problem, but it holds everywhere.)
- If nothing meets that bar, Problems is just `none rn`. That's the common case, not a fallback.
- **Progress = what actually changed since the last standup, stated honestly about its state.** A PR moving to MERGED is progress. A draft PR, and equally a stack that only exists on my machine, is work-in-progress, NOT something "opened for review" — never phrase it as "opened PR#X" or word it so the team thinks it's ready to look at, because that pulls reviewers in before it's ready. If you mention wip work at all, keep it light ("got the X fix together, still wip", "clarity moving along, still wip") and do not detail its internals — that invites scrutiny it isn't ready for and tells the team more than they need.
- **One bullet per distinct thing done. Do NOT pad Progress with bullets that just explain a single PR** — the files it touched, that checks passed, its internal structure. That's all inside the PR and anyone can click through to see it; it isn't separate work I progressed on. If the day's progress is one PR, Progress is one bullet.
- **Phrase each priority by the PR's actual state, not the end goal.** The next action depends on where the PR is: not yet a PR → "open PR#X" / "get PR#X up"; a draft / still wip → "finish + open PR#X" (it can't be landed before it's even open for review); already open for review → "land PR#X". Never say "land PR#X" for something that isn't open for review yet — landing is only the priority once it's actually reviewable.
- Keep it short. My updates are a handful of bullets per section, not paragraphs. (Teammates who write longer prose updates — that's their style, not mine.)
- **Matter-of-fact, no editorialising.** State what happened, not the colour around it. Don't thank people, don't celebrate unblocks, don't narrate dependencies landing ("prompts landed, thanks James" → just "started working on ICON-148"). A review coming back is "got approved by John with some comments I am to address", not a story.
- **My verbs, exactly:** "address John's review" (never "action" the review), "keep working on" (never "keep finishing"), "started working on", "landed", "got approved".
- **A review that approved-with-comments is a Priority, not a Problem** — phrase it "address John's review on PR#X + land". An approval with action items is still the PR's work to absorb; it is never a Problem.
- **Don't park speculative cross-team questions in Problems.** Whether some finding is really someone else's call (a schema/compliance decision, an ownership question) is something I settle once I'm in the PR and can see what's what — not when drafting the 3 Ps. If you're unsure whether something is a genuine cross-team blocker, that uncertainty is not itself a Problem: leave it out or ask me, don't invent one.
- Voice: plain, lowercase, contractions, occasional "rn". Follow the "writing in my voice" rules in the global CLAUDE.md (no em dashes, no LLM tells, no over-structuring).

## Calibration sample (Iconic, 2026-06-29)

Not a template — don't copy its shape onto a repo it doesn't fit. It's here because I posted it
with zero edits, the first I changed nothing on. It pins the bar. Match it.

```
Morning everyone :sun_with_face:

**Progress**
- integrity check on ICON-148 (three-level integrity check) moving along, still wip https://linear.app/iconicshift/issue/ICON-148/three-level-integrity-check

**Problems**
none rn

**Priorities**
- land PR#322 (clarity WCO, ICON-147)
- land PR#327 (backfill guard tests)
- finish + open the ICON-148 PR (three-level integrity check), stacked on PR#322
```

Why it landed:

- **Progress was one honest light line.** The day's real work was the 148 integrity check (orchestration tests, wiring) but it's not a PR yet, so it stayed "moving along, still wip" with no internals — didn't pull reviewers in early, didn't pad with the files/tests/structure inside the work.
- **Priorities phrased by actual PR state.** PR#322 and PR#327 were open + non-draft → "land". The 148 stack wasn't a PR yet → "finish + open", never "land". Stacking called out (148 on PR#322).
- **Problems was `none rn`, correctly.** The open 148 questions (route wiring, e2e) were my own calls, not cross-team blockers — so they stayed out.
- **Links exactly to format.** Bare `PR#<n>` with short parenthetical, no URL. Linear ref `ICON-148 (...)` followed by the bare full URL with the title slug.

> Note (2026-07-16): this example predates the switch to markdown links. Its bare `PR#<n>` and trailing-bare-URL style is the **old** format — follow the current Links section (inline `[text](url)` wrapping the ref) instead. Everything else about why it landed still holds.
