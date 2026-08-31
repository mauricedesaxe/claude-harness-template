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
**Always deliver it as raw markdown inside a fenced code block** (see Format), and never as
already-rendered prose.

Nothing here is pinned to one repo or one team. Infer the repo, the tracker, my identity,
the issue-key format and the destination, then gather.

## What to infer

- **Repo**: from the remote: `git remote get-url origin`, normalised to `<host>/<owner>/<repo>`.
- **Tracker and issue-key format**: resolve per **Tracker resolution** in `CLAUDE.md`.
- **Key spaces, plural.** One repo can carry more than one, and only some of them have an API
  behind them. On `iconicshift/platform` a Linear `ICON-<n>` and a Slack-thread `WEB-<n><letter>`
  both name real work, and the second resolves to a permalink I have to hand you. The note records
  the ones I've already named. A key you meet that isn't in the note is a question for me, never a
  guess and never a bullet left unlinked.
- **Author**: from the API, never hardcoded. GitHub: `gh api user --jq .login`. Linear: the
  viewer, via `mcp__linear__list_my_issues` or the equivalent.
- **Destination**: where the post goes (a Slack channel, the tracker, a doc). The note records
  it if I've said before. If not, ask, and write the answer to the note.

## How to gather

Gather wide, then narrow. Every command below answers the question you put to it, and it also
carries evidence you didn't ask for. The post comes out wrong in exactly the places you took
one result at face value.

Two habits carry most of it. Read each output for everything it says, not only for the field
you went in for. And treat a thin or empty result as a fact about the query
before you treat it as a fact about the day: a week with nothing in it, next to a local side that
shows work every day, means the filter is wrong, not that nothing happened.

1. Resolve repo, tracker, author, destination as above. Connect the tracker's MCP if it isn't
   already (authenticate if needed).

2. **Progress = what actually changed since the last standup, stated honestly about its state.**
   Gather from both sides and reconcile them:

   - **Remote.** Everything that landed in the window, then split by my part in it. Never scope
     the merged query to my own authorship. To land someone else's PR is my work too. On a repo
     where I'm the one who lands them, an `--author me` filter hides that whole half of the
     day:

     ```bash
     gh pr list --state merged --search "merged:>=<date of my last standup>" \
       --json number,title,author,mergedAt,mergedBy
     ```

     `author == me` is what I wrote. `mergedBy == me` over someone else's `author` is what I
     landed, and it earns its own bullet ("landed copy changes leftover from John").

     **A landed PR does not always say MERGED.** Where trunk takes fast-forward pushes, the PR
     closes without GitHub ever marking it merged. Its head sha isn't an ancestor of trunk
     either, so neither `--state merged` nor an ancestry check finds it. Read trunk's own log for
     the window and match by subject:

     ```bash
     git log origin/<trunk> --since=<date> --pretty='%h %an %ad %s' --date=short
     ```

     Plus the tracker's equivalent (issues I moved or closed), and any substantial non-PR work I
     mention (reviews, planning, investigation).
   - **Local.** Work that only exists on this machine is still progress, and it's often the
     honest answer to what I'm doing today. Read the working copy and the commits that aren't
     on any remote, whichever VCS the repo uses:

     ```bash
     # jj: use it whenever .jj exists (a colocated repo has both, jj is the working copy)
     jj st
     jj log -r 'mine() & ~::trunk() & ~::remote_bookmarks()'   # my commits on no remote
     jj workspace list                                         # other workspaces' @ are mine too

     # git
     git status --short
     git log --oneline --branches --not --remotes              # commits on no remote
     git worktree list
     ```

   - **The names are evidence, not just the commits under them.** A workspace, worktree or
     bookmark is named by whoever cut it, so the list is a record of what I've had open and why.
     Read it twice. A name that carries a key not matching this repo's issue-key pattern is work
     tracked somewhere else. It needs its ref before it can be a bullet, so ask me. A name
     saying what the work *is* (`*-diagnose`, `done-*`, `review-*`) tells you how to phrase it:
     diagnosing a live failure is not the same bullet as shipping a feature. `jj workspace list`
     shows registered workspaces only, so read `.jj/ws/` as well and don't skip the forgotten ones.

   - **Reconcile.** A local branch or stack whose PR is already open is the PR's story, not a
     second bullet. Phrase it by the PR's state. A stack with no PR yet is work in progress.
     Don't double-count the same work once as local and once as remote.

   - **Date every status field before you quote it.** A PR's `reviewDecision`, and a review's
     state, are sticky. `CHANGES_REQUESTED` sits there until that same reviewer submits again.
     So it can describe last week, while the work moved on twice since. Compare the newest
     review's `submittedAt` against the head commit and against local activity before you let it
     name the day's work. When the newest activity is my own review rounds (review-record commits,
     `review-*` workspaces, a round number in a commit subject), the honest line is that I'm
     working through my own automated reviews, not that I'm addressing a teammate's.

3. **Fan out one PR-status agent per open PR in scope.** The gathering above says what moved.
   This says where each PR actually stands, and it is the difference between a real standup and a
   list of branch names. Do it every time, not only when a PR looks interesting.

   **Scope.** Every open PR authored by me or assigned to me that targets trunk, plus every PR
   whose base is one of those. That is trunk plus one level. Deeper members of a stack ride on
   their base until it lands, so they do not each need an agent. Count them anyway, because
   "PR#552 through PR#555, no rounds yet" is a real line.

   ```bash
   gh pr list --state open --limit 60 \
     --json number,title,author,assignees,baseRefName,headRefName,isDraft \
   | jq -r '.[] | select((.author.login=="<me>") or ([.assignees[].login]|index("<me>")))
            | "\(.number)\t\(.isDraft)\tbase=\(.baseRefName)\t\(.title)"'
   ```

   Run the agents **in parallel, one per PR**, each invoking `lazar-pr-status` for its number, and
   each told to stay read-only: post nothing, change nothing. Ask every one of them for the same
   four things, so the lines compare:

   - how many automated review rounds ran against **this** PR,
   - the final round's date, verdict, and finding count, split into fixed, dropped, still open,
   - the human review status: review count, states and dates, thread count, `reviewDecision`,
   - the business-logic changes made in response to reviews, behaviour and contract only.

   Wait for all of them. Never write a line about a PR whose agent has not reported.

4. **Count the automated review rounds from the records in the repo, where the repo keeps them.**
   Not all of my repos do. This is a convention some of them carry and others have never had, so
   check before you rely on it. Where it exists, use it: it is what makes a line honest about how
   far a PR has come, and it is invisible to GitHub. Where it does not, the round count is simply
   not part of the line, and the rest of the gathering stands on its own.

   A repo that runs a review skill of its own records each round as a markdown file, usually
   `work/<ISSUE>/reviews/<timestamp>-<sha>-<session>.md`, with a `pr:` field in its front matter.
   That field is the only reliable filter. A stack carries its ancestors' records forward, so a
   branch tree holding 75 records can hold 21 for the PR you asked about. Count by `pr:`, never by
   file count, and say which records are carried over when it is ambiguous.

   Three traps. Records often live only in an unpushed jj workspace, so search `.jj/ws/` as well as
   the branch tree. Round numbering restarts between sessions, so "round 14" is not the total. And
   the last recorded verdict can still read "changes requested" when every finding was fixed,
   because no further round ran to confirm them. Say that plainly rather than calling it clean.

   Tell the two zeros apart. A repo that keeps records and has none for this PR is a PR nobody has
   reviewed, and "no review rounds yet" is one of the most useful lines in the post. A repo that
   keeps no records at all says nothing about the PR, so the line carries no round count rather
   than a zero.

5. **Problems:** only things someone other than me could act on. A dependency not ready, a
   decision I'm waiting on from the team, or an environment issue that affects others. My own gating
   tasks (re-recording cassettes, finishing my own PR) are not problems. Usually `none rn`.

6. **Priorities:** check each open PR's draft state
   (`gh pr list --author <login> --state open --json number,title,isDraft,baseRefName,headRefName`)
   and phrase the action to match it. Open, finish+open, or land: see the phrasing rule in
   Rules. Plus the next issues I'm picking up. Note stacking when one builds on another.

   Where the local trail shows a cadence I'm partway through, name the step that's actually next
   instead of the generic verb. "work through one more round of automated reviews then dogfood and
   open PR#424" is what I'll do today. "finish + open PR#424" is only the shape of it. The verb
   from the Rules is the floor, not the target.

7. If I've just planned my day in another skill, pull the priorities straight from the plan I
   picked.

Confirm the draft with me before I post it. This goes out under my name to a team.

## Format

- Open with my greeting: `Morning everyone :sun_with_face:` or `Hello hello :sun_with_face:`. I vary it; pick by time of day, and drop the "morning" wording if I'm posting later.
- Three headers: `*Progress*`, `*Problems*`, `*Priorities*`. **Single asterisks**, which is Slack's
  own bold and what I actually post. Markdown's `**double**` is wrong here even though the rest of
  the post is markdown, and even though my Slack renders markdown links.
- Lowercase, terse fragment bullets. Not full sentences. Real lines of mine:
  - `landed PR#299 (strategic summary, ICON-49)`
  - `start the Clarity preprocessing pipeline (WCO) for ICON-147 stacked on PR#316 (office extraction)`
  - `mapped out where artefact submission + strategic summary actually stand, what's blocked vs what i can pick up`
- **One section per stack.** When my open PRs form stacks, Progress and Priorities each split into
  a section per stack, under an italic `_<what the stack does> (<ISSUE>)_` label. Different stacks
  are different initiatives, and one flat list hides which PR belongs to which. A repo with no
  stacks keeps the flat list.
- **Order every section base-up.** The PR that targets trunk comes first, then the one stacked on
  it, up to the tip. That is the order they land in, so it reads as the order things unblock. Name
  the base in the line itself, like `(road-map mappers, on PR#550)`, so the shape is legible
  without a click.
- **Collapse the unreviewed tail.** A run of tip PRs in the same state gets one line:
  `PR#552 → PR#555 (milestone round, on PR#551): no review rounds yet, still draft`.
- **One item per line.** Never combine two issues or PRs on one line ("ICON-148 and ICON-146 …"). Split them into separate lines, even when the action is the same.
- **Links (settled 2026-07-16, Slack now renders markdown):** I turned on markdown rendering in my Slack. Inline markdown links `[text](url)` now work, and they are the format I want from now on. Wrap the ref word itself in the link, with the short parenthetical name in plain text after it:
  - PRs: `[PR#<n>](<repo-url>/pull/<n>)`, built from the inferred repo, e.g. `land [PR#369](https://github.com/iconicshift/platform/pull/369) (conflict detection, ICON-286)`.
  - Tracker issues: `[<KEY>](<full issue url>)` in the repo's own key format, e.g. `started on [ICON-93](https://linear.app/iconicshift/issue/ICON-93/context-capture-recovery-loop) (context capture recovery loop)`. Use the real URL the tracker's API returns (Linear's `url` field carries the slug; the slug-less `…/issue/ICON-93` form is not what I use). On a GitHub-tracked repo the key is `#<n>` and the URL is the issue URL.
  - I still copy the post as raw markdown **source**, from the fenced code block. The markdown links then paste straight into Slack and render there. That's why the whole thing must stay in a code block.
  - Inline markdown links don't fire Slack's unfurl previews, so the old "only first 5 previews are shown" caveat no longer applies. Nothing to restructure or work around.
- **Still hand me the whole post as raw markdown inside a fenced code block**, so I copy the source rather than a rendered preview.

## Rules

- **A problem is one that someone OTHER than me could or should act on.** A genuine problem is cross-team. I'm blocked on a person or a dependency, waiting on a decision, or hitting a team-wide nuisance. Listing it prompts someone else to act. Work I can handle entirely on my own is NOT a problem, even when it's hard, tedious, or gating my own other work (e.g. "I still have to re-record my cassettes" is my own task, not a problem). When in doubt, ask: could anyone but me move this? If no, it's not a problem.
- **Do NOT put review requests in Problems.** A PR needing review belongs in Priorities, not Problems. (It came out of the Iconic team asking to stop listing "need a review on PR#X" as a problem, but it holds everywhere.)
- If nothing meets that bar, Problems is just `none rn`. That's the common case, not a fallback.
- **Progress = what actually changed since the last standup, stated honestly about its state.** A PR moving to MERGED is progress. A draft PR, and equally a stack that only exists on my machine, is work-in-progress, NOT something "opened for review". Never phrase it as "opened PR#X". A PR that genuinely came out of draft in the window is the different case: "opened for review" is then the honest state, and it belongs in Progress. The ban is on dressing a draft up as ready, never on reporting a real state change. Never word it so the team thinks it's ready to look at, because that pulls reviewers in early. If you mention wip work at all, keep it light: "got the X fix together, still wip", "clarity moving along, still wip". Do not detail its internals. That invites scrutiny it isn't ready for, and tells the team more than they need.
- **One bullet per distinct thing done. Do NOT pad Progress with bullets that just explain a single PR**: the files it touched, that checks passed, its internal structure. That's all inside the PR and anyone can click through to see it; it isn't separate work I progressed on. If the day's progress is one PR, Progress is one bullet. **A stack is the one exception, and only in the shape below**: each PR in it gets exactly one line, because each is a separate deliverable with its own state. One line per PR, never two.
- **Phrase each priority by the PR's actual state, not the end goal.** The next action depends on where the PR is. Not yet a PR → "open PR#X" or "get PR#X up". A draft or still wip → "finish + open PR#X", because it can't land before it's even open for review. Already open for review → "land PR#X". Never say "land PR#X" for something that isn't open for review yet, landing is only the priority once it's actually reviewable.
- Keep it short. My updates are a handful of bullets per section, not paragraphs. (Teammates who write longer prose updates, that's their style, not mine.)
- **Matter-of-fact, no editorialising.** State what happened, not the colour around it. Don't thank people, don't celebrate unblocks, don't narrate dependencies landing ("prompts landed, thanks James" → just "started working on ICON-148"). A review coming back is "got approved by John with some comments I am to address", not a story.
- **The per-PR line is a state line, not a summary of the work.** It carries the PR ref, a short
  parenthetical name and its base, how many automated review rounds ran, the finding count of the
  last one, and what I am doing about it next. Say "last automated review had 0 findings" or "last
  automated review had 4 findings". Never list the findings themselves. What each one was is in the
  PR, and nobody in a standup needs it. The two review numbers ride on the repo keeping review
  records. Where it keeps none, the line is the ref, the name, the base, and the state.
- **Then state where the PR is, in my words.** Open for review is "opened for review". A draft
  whose last round was clean is "still draft, want one last manual pass before i open it". A draft
  with findings still to work is "still draft, keep working through it". That is the whole
  vocabulary, and it never tells the team more about a wip PR than that.
- **My verbs, exactly:** "address John's review" (never "action" the review), "keep working on" (never "keep finishing"), "started working on", "landed", "got approved".
- **A review that approved-with-comments is a Priority, not a Problem**. Phrase it "address John's review on PR#X + land". An approval with action items is still the PR's work to absorb; it is never a Problem.
- **Don't park speculative cross-team questions in Problems.** Some findings are really someone else's call: a schema or compliance decision, an ownership question. I settle that once I'm in the PR and can see what's what, not when drafting the 3 Ps. If you're unsure whether something is a genuine cross-team blocker, that uncertainty is not itself a Problem. Leave it out or ask me. Don't invent one.
- Voice: plain, lowercase, contractions, occasional "rn". Follow the "writing in my voice" rules in the global CLAUDE.md (no em dashes, no LLM tells, no over-structuring).

## Calibration sample (Iconic, 2026-06-29)

Not a template, so don't copy its shape onto a repo it doesn't fit. It's here because I posted it
with zero edits, the first I changed nothing on. It pins the bar for **judgement**: what earns a
bullet, how light a wip line stays, how short the whole thing is. It does not pin **format**, which
it predates on two counts (see the note under it). Where the two disagree, the Format section wins.

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

- **Progress was one honest light line.** The day's real work was the 148 integrity check (orchestration tests, wiring) but it's not a PR yet, so it stayed "moving along, still wip" with no internals, so it didn't pull reviewers in early, didn't pad with the files/tests/structure inside the work.
- **Priorities phrased by actual PR state.** PR#322 and PR#327 were open + non-draft → "land". The 148 stack wasn't a PR yet → "finish + open", never "land". Stacking called out (148 on PR#322).
- **Problems was `none rn`, correctly.** The open 148 questions (route wiring, e2e) were my own calls, not cross-team blockers, so so they stayed out.
- **Links exactly to format.** Bare `PR#<n>` with short parenthetical, no URL. Linear ref `ICON-148 (...)` followed by the bare full URL with the title slug.

> Note (2026-07-16, extended 2026-08-04): this example predates two format changes. Its bare `PR#<n>` and trailing-bare-URL style is the **old** link format, so follow the current Links section (inline `[text](url)` wrapping the ref) instead. Its `**double-asterisk**` headers are the **old** emphasis, so post single `*Progress*`. Everything else about why it landed still holds, and the sample below is the one to copy.

## Calibration sample (Iconic, 2026-08-04)

I posted the second one unedited. It's here because the draft I was handed first missed four
things, all of them recoverable from the machine. Read it against **How to gather**.

```
*Progress*
- kept working through automated reviews [ICON-287](https://linear.app/iconicshift/issue/ICON-287/road-map-milestones-generate-without-founder-acceptance-of-annual) (targets gate)
- did diagnosis work on the pipeline failure [WEB-1T](https://findyourlightbulb.slack.com/archives/C0B09TNNT8V/p1785744184491339)
- landed copy changes leftover from John

*Problems*
none rn

*Priorities*
- work through one more round of automated reviews than dogfood and open [PR#424](https://github.com/iconicshift/platform/pull/424) (targets gate, ICON-287)
- finish + open [PR#433](https://github.com/iconicshift/platform/pull/433) (target shaping, [ICON-341](https://linear.app/iconicshift/issue/ICON-341/founders-can-shape-their-road-map-targets-with-game-gate-revision)), stacked on PR#424
```

What the first draft got wrong, and where the answer sat:

- **"landed copy changes leftover from John" never made the post.** The draft ran
  `--author me --state merged`, got nothing newer than a week back, and reported that nothing
  landed. Two PRs merged in the window with `author: graphcs` and `mergedBy: mauricedesaxe`.
  A week of silence next to a busy local tree was the tell, and one unscoped query with `mergedBy`
  recovers the whole line.
- **The 287 work is my own automated review rounds, not a teammate's review.** The draft read
  GitHub's `CHANGES_REQUESTED` and wrote "addressing James's review". That review was six days
  old. Local commits said "Record the round-12 review of PR 424", and four `review-*` workspaces
  were open. A twelfth round is nobody's single pass.
- **WEB-1T went in unlinked, and framed as delivery.** A workspace named `web1s-diagnose` sat
  in the output the draft already printed, in a key format this repo's Linear doesn't use.
  That's the moment to ask for the ref, and `*-diagnose` is the moment to say "did diagnosis work"
  rather than "got the diagnostics together".
- **Priorities named the shape, not the step.** "finish + open PR#424" is true, and useless next to
  "one more round of automated reviews then dogfood and open PR#424". That is the actual next
  thing given where the review cadence had got to.

## Calibration sample (Iconic, 2026-08-31)

The one that produced the stack sections and the fan-out. Nine open PRs across two stacks, and a
first draft that read as three vague bullets about "review rounds". Copy this shape whenever my
open work is stacked.

```
Morning everyone :sun_with_face:

*Progress*

_onboarding live save ([ICON-368](https://linear.app/iconicshift/issue/ICON-368/onboarding-fields-dont-persist-live-founder-input-lost-on-reload))_
- [PR#544](https://github.com/iconicshift/platform/pull/544) (gate refactors, base): 11 automated review rounds, last one had 2 findings, opened for review
- [PR#539](https://github.com/iconicshift/platform/pull/539) (game-eligibility live save, on PR#544): 14 rounds, last one had 1 finding, still draft, want one last manual pass before i open it
- [PR#540](https://github.com/iconicshift/platform/pull/540) (starting-position live save): 1 round, last one had 3 findings, still draft, keep working through it

_road-map two-round split ([ICON-287](https://linear.app/iconicshift/issue/ICON-287/road-map-milestones-generate-without-founder-acceptance-of-annual))_
- [PR#550](https://github.com/iconicshift/platform/pull/550) (write-prevention harness, base): 5 rounds, last one had 0 findings, opened for review
- [PR#551](https://github.com/iconicshift/platform/pull/551) (road-map mappers, on PR#550): 7 rounds, last one had 4 findings, still draft, keep working through it
- [PR#552](https://github.com/iconicshift/platform/pull/552) → [PR#555](https://github.com/iconicshift/platform/pull/555) (milestone round, on PR#551): no review rounds yet, still draft

*Problems*
none rn

*Priorities*

_onboarding live save_
- one last manual pass on [PR#539](https://github.com/iconicshift/platform/pull/539), then open it
- rebase [PR#540](https://github.com/iconicshift/platform/pull/540) onto PR#544 and work through automated reviews to get it ready

_road-map two-round split_
- land [PR#550](https://github.com/iconicshift/platform/pull/550)
- keep working through [PR#551](https://github.com/iconicshift/platform/pull/551), then PR#552 → PR#555
```

Why it landed:

- **A `lazar-pr-status` agent ran per PR, in parallel, before a word was drafted.** That is where
  every number in the post came from. It also caught what no summary would have: PRs 552 to 555 had
  never had a single review round, so the stack was further from ready than its length suggested.
- **The round counts came from the repo's own review records, filtered by `pr:`.** 21 records
  matched PR#539 out of 75 on the branch, and the local numbering said "round 14". Both numbers are
  true about different things, and the post used the one I recognise.
- **Two stacks, two sections, each ordered base-up.** The bases (#544 and #550) lead their
  sections, and every line above them names the PR it sits on. The reader sees what unblocks what.
- **Findings are counted, never listed.** "last one had 4 findings" and nothing more.
- **Progress reported real state changes.** #544 and #550 came out of draft in the window, so
  "opened for review" was honest rather than a draft dressed up.
- **Priorities carried two lines per stack, in landing order**, and left out #544 entirely, because
  nothing on it was mine to do.
