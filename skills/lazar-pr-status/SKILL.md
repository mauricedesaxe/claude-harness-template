---
name: lazar-pr-status
description: Point at a PR number and get its full context back, so I can re-enter a review without re-reading everything. Pulls the PR and its issue from whatever tracker owns it, then reports what the reviews asked for, what's addressed in code, what was only answered in a reply, what's unaddressed, and what drifted in since. Use when I say "/lazar-pr-status", "status of PR 386", "where is PR 386 at", "what's still open on that PR", or hand you a PR number and ask what's left.
---

# lazar-pr-status

I point at a PR number. You hand back what I'd have got by re-reading the whole thing.

It's an API-first skill: no checkout, no fetch, no branch switching. It publishes nothing unless I
ask it to, and then only after it asks me. See **This doesn't write unless I ask it to** at the
bottom.

## Step 1: resolve the PR

The PR number is what I gave you. Everything else you work out.

`gh` finds the repo by shelling out to git, and a jj workspace has no `.git`, so it fails there
with "not a git repository". Pass `--repo` explicitly, always. An inherited `GITHUB_TOKEN`
outranks `gh auth`'s own credentials, so unset it or `gh` answers as the wrong account:

```sh
jj git remote list                     # origin git@github.com:owner/repo.git
git remote get-url origin              # same answer where there's no jj

R=owner/repo
env -u GITHUB_TOKEN gh pr view <n> --repo "$R" \
  --json number,title,state,body,headRefName,baseRefName,commits
env -u GITHUB_TOKEN gh api "repos/$R/pulls/<n>" --jq '{head: .head.sha, base: .base.sha}'
```

Hold on to the head sha and the base sha. Every later step is "what happened between some
earlier sha and this head".

## Step 2: load the issue behind the PR

The intent lives in the tracker, and which tracker owns this repo is not this skill's guess to
make. Resolve it per **Tracker resolution** in `CLAUDE.md`, then find the issue:

- The PR body's closing keyword (`Closes #N`, `Fixes ICON-147`), the branch name, and the commit
  messages are where the key usually is. Read all three before asking me.
- GitHub: `env -u GITHUB_TOKEN gh issue view <n> --repo "$R"`.
- Linear: the issue via `mcp__linear__*`, including its comments. Connect the MCP if it isn't
  already.
- **No issue named** is an answer, not a blocker. Say the PR names no issue and carry on with the
  PR body as the only statement of intent.

## Step 3: gather the surrounding context

The point is to judge the PR against decisions already made, not from scratch.

- **PR-level conversation** (not review threads, those are Step 4):
  `env -u GITHUB_TOKEN gh api "repos/$R/issues/<n>/comments"`.
- **Design docs and ADRs.** Where these live is a per-repo fact, and the machine-local note
  (see **The machine-local note** in `CLAUDE.md`) records it. Read the note first. On some repos
  the system design sits in the Linear issue and there's no ADR in the tree at all, so don't go
  hunting `docs/adr/` on a repo that never had one.
- **Whatever else reaches**: any connected MCP, the linked issue's own links, a doc the PR body
  points at.

## Step 4: read the reviews

Two surfaces, and you need both. Reviews carry the verdict and the sha; threads carry the
conversation and the resolution state.

```sh
# each review: its state, and the head sha the reviewer was looking at
env -u GITHUB_TOKEN gh api "repos/$R/pulls/<n>/reviews" \
  --jq '.[] | {id, state, commit_id, user: .user.login, submitted_at, body}'

# the threads: resolution, outdatedness, and the replies under each comment
env -u GITHUB_TOKEN gh api graphql -f query='
{ repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <n>) {
      reviewThreads(first: 100) { nodes {
        isResolved isOutdated path line originalLine resolvedBy { login }
        comments(first: 20) { nodes {
          author { login } createdAt body
          originalCommit { oid } commit { oid } diffHunk } } } } } } }'
```

**No reviews at all** (both come back empty) means stop here. Report the TLDR from Steps 1 to 3:
what the PR does, what the issue asked for, what context bears on it, and what it changes. Then
say there are no reviews yet and stop. Don't invent a review of your own. This skill being
useful *before* review starts is the point, not a degraded mode.

## Step 5: reconstruct the code at each review point

A review is anchored to a sha: `commit_id` on the review, `originalCommit.oid` on the comment.
That sha is what the reviewer actually saw, and it's the only honest fixed point. **`commit_id`
on the review is the PR head at the time of review**, so one review is one point in time, however
many threads hang off it.

Three ways to get the code back, cheapest first:

1. **`diffHunk` on the comment** carries the reviewed lines verbatim, stored on the comment
   itself. It survives anything that happens to the branch afterwards. It's a hunk, not a file,
   so it answers "what was this comment pointing at" and nothing wider.
2. **The file at that sha**:
   `env -u GITHUB_TOKEN gh api "repos/$R/contents/<path>?ref=<sha>" -H "Accept: application/vnd.github.raw"`.
   Use it when the hunk is too narrow to judge, which is most of the time.
3. **What changed since that review**:
   `env -u GITHUB_TOKEN gh api "repos/$R/compare/<review_sha>...<head_sha>"` gives per-file status,
   counts, and patches. This is the workhorse of Steps 6 and 7.

**A force-push doesn't sink this.** The review's own sha is the before, and GitHub keeps a
force-pushed-away commit readable by sha, so a rewritten branch reconstructs like any other. If a
`compare` or `contents` call 404s on a review sha, the review point is genuinely gone. Say so on
that thread, fall back to its `diffHunk`, and don't guess.

**A rebased PR makes every path look touched.** Compare from a review sha to head after a rebase
includes the trunk commits the branch was replayed onto. Sanity-check `behind_by` and the base
sha before you call something a change the author made.

## Step 6: the three buckets

For each thread, decide which of three it is. The distinction is the whole product.

- **Addressed in code.** The code the comment pointed at changed after the review, in a way that
  answers it. Establish it in two moves: the compare from that thread's review sha to head touches
  the thread's `path`, and the change at that region actually does what the comment asked. Then
  say what the fix was in one line, so I can stop re-checking it.
- **Answered in a reply only.** The thread has a reply from the author but the code is unchanged
  since the review. **Judge the reply.** "Sufficient" when it answers the question, corrects a
  reviewer who was wrong, or names a trade I'd accept. Not sufficient when it defers ("good
  catch, will do"), agrees without doing anything, or answers a different question than the one
  asked. Say which, and why, in one line. This is the bucket I'm actually asking about: it's where
  things quietly die.
- **Unaddressed.** No reply, no code change. List every one. This bucket existing at
  all is why the skill exists, so never fold it into the others and never summarise it as "minor".

**`isOutdated` and `isResolved` are signals, not verdicts.**

- `isOutdated: true` only means the line no longer appears in the current diff. An edit three
  lines away outdates a comment without addressing a word of it. Never read it as "fixed".
- `isResolved` records that someone clicked resolve. It's evidence about intent, not about code.
  A resolved thread whose code never moved and whose reply defers is **answered in a reply only**,
  and worth flagging precisely because the checkbox says otherwise.

Both are worth reporting when they disagree with the code. That disagreement is a finding.

## Step 7: drift

Anything introduced since the PR opened that no review mentioned. This is code that would ship
unexamined, which is the failure the whole skill guards.

Compare the earliest review's sha to head, take the files the reviews never point at, and read
what changed there. A file no thread names is a candidate, not automatically drift: a change the
author made *because* of a review is addressed work, even where it lands in an untouched file.
Read it and decide.

**If there's no drift, say nothing about drift.** No heading, no "no drift found" line, no
padding.

## Step 8: the report

```
# PR#<n> <title>, <state>, <n> reviews, <n> threads

**Intent.** <what the issue asked for, one or two lines, with the issue link>
**Context.** <the ADR, the design doc, the decision this rests on, or omit the line>
**Change.** <what the PR does, one or two lines>

## Addressed in code
- <path>:<line>, <what was asked> → <what the fix was>

## Answered in a reply only
- <path>:<line>, <what was asked> → <the reply>. **Sufficient** / **Not sufficient**: <why>

## Unaddressed
- <path>:<line>, <what was asked>, from <reviewer>'s <state> review

## Drift
- <path>, <what changed after review that nobody looked at>

Net: <n> addressed, <n> answered, <n> open<, plus drift in <n> files>.
```

- **A bucket with nothing in it gets no heading**, drift included.
- **Link every thread**, so I can jump straight to it rather than scroll the PR.
- **One line per thread.** If a thread needs a paragraph, it's a finding I need to read myself:
  say that, don't write the paragraph.
- **Order by what I'd act on**: unaddressed first, then insufficient replies, then the rest.
- Quote a reviewer's ask in their words when the wording is the point. Otherwise compress it.
- Follow the writing rules in PHILOSOPHY §30, same as everything else.

## This doesn't write unless I ask it to

Nothing goes out under my name without me seeing it first. The default is the report in front of
me and nothing published: `gh pr view`, `gh issue view`, `gh api` with GET, and the tracker's read
tools are the whole surface. Never resolve a thread, never touch the tracker's state, never
`gh api` with a write method.

The default holds wherever this runs. This report's audience is me, not the PR: it's the briefing
I read before reviewing someone else's work, so posting it unasked would drop my private notes on
their PR. That's what makes it different from `lazar-review`, whose output *is* a review and whose
destination *is* the PR.

**Publishing happens only when I ask for it, and only after you ask me.** If I say to post it,
say what you're about to post and where, then wait for me to confirm. A confirmed post is a PR
comment (`gh pr comment`) and nothing else: never `gh pr review`, which carries an approval state
this skill never formed an opinion on, and never a merge, a close, or an edit to an issue body.

**If nothing answers, don't post.** A sandbox isn't the same thing as an unattended run: a session
I'm driving has me reading it, an automation run has nobody, and you can't tell which one you're
in. So treat silence as a no. Say in the report that a post was asked for, that the confirmation
went unanswered, and that nothing went out.

The working copy is off limits too. Don't check the PR out, don't fetch, don't switch branches.
Whatever I'm in the middle of stays as I left it, and the API answers every question this skill
asks anyway.
