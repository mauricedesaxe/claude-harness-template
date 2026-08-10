---
name: lazar-qa
description: Drive a change through a real browser and report what's wrong with it. Prefers a per-PR preview deploy, falls back to hosting the app locally, then uses the Playwright MCP to click through the actual UI (never text or curl), capturing screenshots as it goes. Hunts for bugs, UX gaps against the Doherty bar, and places the change misses the intent of its issue. Ends with a verdict in chat or a posted PR review, and asks which if I didn't say. Use when I say "/lazar-qa", "QA this", "QA PR 41", "test this in the browser", "click through it", "smoke test the feature", or want a change exercised for real before it ships.
---

# lazar-qa

I point at a change. You open the real app, drive it like a user, and tell me what's broken, what's
clumsy, and where it misses what the issue asked for.

This is the manual-QA counterpart to `lazar-review`. That one reads the diff; this one *uses the
software*. The two hard rules: you run against a real running app, and you drive it through the
browser for real. Reading the code is how you learn what to test, never how you conclude it works.

## Step 1: resolve the change and its intent

Work out what I'm asking you to exercise, then what it was supposed to do.

- **The change.** A PR number if I gave one; otherwise the current branch or the uncommitted working
  copy. In a jj workspace, `gh` needs `--repo` explicitly, and an inherited `GITHUB_TOKEN` outranks
  `gh auth`, so unset it:

  ```sh
  jj git remote list                                  # origin owner/repo
  R=owner/repo
  env -u GITHUB_TOKEN gh pr view <n> --repo "$R" --json number,title,body,headRefName,state
  ```

- **The intent.** The issue behind the change is the scorecard. Resolve the tracker per **Tracker
  resolution** in `CLAUDE.md`, find the issue from the PR body's `Closes #N`, the branch name, or
  the commit messages, and read its acceptance criteria. **No issue named** is an answer: say so and
  QA against the PR body as the only statement of intent.

- **The surface.** Read the diff and the changed files to build the test plan: every screen, form,
  state, and role the change touches. This is the one place you read code, and it's to know *what to
  click*, not to judge whether it works. §18: the bugs live at the seams, so plan to cross them.

## Step 2: get a running app, preview first

You need a real target. Prefer the one closest to production.

1. **A per-PR preview deploy (§24).** This is the full stack, already built, with none of the local
   setup. Look for it before building anything:

   ```sh
   env -u GITHUB_TOKEN gh pr view <n> --repo "$R" --json statusCheckRollup \
     --jq '.statusCheckRollup[] | select(.targetUrl) | {name, targetUrl}'
   env -u GITHUB_TOKEN gh api "repos/$R/deployments?ref=<headRef>" \
     --jq '.[0].id' | xargs -I{} env -u GITHUB_TOKEN gh api "repos/$R/deployments/{}/statuses" \
     --jq '.[0].environment_url'
   ```

   A preview bot comment often carries the URL too. If you find a live one, use it and skip to
   Step 3. Note in the report that you tested the preview, and its URL.

2. **Local, when there's no preview.** Host it yourself. A project documents how to start it in its
   `README` or `CLAUDE.md`, and often ships a start script. Read that first, don't guess the command.
   Typical shape: install deps, copy the example env file and fill required secrets, run migrations,
   start the dev server. Local sign-in and seed data are the usual snag: find the project's own hook
   for it (a dev endpoint that surfaces the auth code, a seed script, test fixtures) rather than
   inventing an account. Note in the report that you tested local, since it's a rung below the
   preview on the fidelity ladder.

Isolate the work per **Workspace isolation** in `CLAUDE.md`: cut a jj workspace off the change's
revision so a running dev server and its local DB don't collide with anything else. Tear it down in
Step 6.

## Step 3: drive the real browser, and prove it

**Use the Playwright MCP. Actually click.** This is the rule the whole skill exists to enforce. Every
claim in the report has to come from a browser interaction you performed: `browser_navigate`,
`browser_snapshot`, `browser_click`, `browser_type`, `browser_select_option`, `browser_press_key`.
A finding derived from reading the source, from `curl`, or from an API call alone is not a QA
finding and does not go in the report. If a state is only reachable by a real click, you reach it by
a real click.

**Leave a visual record.**

- Screenshot every meaningful state with `browser_take_screenshot`, and one at every finding, so I
  see the bug rather than read a description of it. The Playwright MCP tends to root screenshot
  paths at the repo it started in, not the workspace, so confirm where they land and collect the
  paths.
- If the Playwright MCP is configured to record **video or a trace**, save it and reference it. Not
  every setup exposes that, so screenshots are the guaranteed record and video is the bonus. Don't
  claim a video you didn't produce.
- Check `browser_console_messages` at the error level as you go. A red console on an otherwise
  fine-looking screen is a finding.

**Cover the surface from Step 1 deliberately:**

- The **happy path** end to end, once, so you know the feature works at all.
- **Each acceptance criterion** from the issue, exercised as its own path. Tick or fail each.
- **Edge and failure states**: validation (empty, too long, wrong type, duplicates), the empty
  state, the loading state, the error/unavailable state. §14's two zeros: "genuinely nothing" and
  "it broke" are different screens, check both exist.
- **Keyboard and a11y (§20)**: primary actions reachable and labelled, focus order sane, shortcuts
  where the product promises them.
- **Mobile**: `browser_resize` to a phone viewport (390×844 is a fine default) and re-run the
  public or primary flow.
- **Authorization**: if the change has roles or a public surface, drive each principal. A reviewer
  who shouldn't see setup, an anonymous visitor who should see the public page. Verify the boundary
  by trying to cross it, not by trusting the UI hid a button.

## Step 4: judge what you found

Sort every observation into one of three, and be honest about which:

- **Bug.** It's broken, wrong, or throws. Functional defects and console errors. These carry the
  report.
- **UX improvement.** It works but it's clumsy, slow past the Doherty ~400 ms bar (§20), confusing,
  or missing an affordance. Say what you'd change, concretely.
- **Intent gap.** An acceptance criterion the change doesn't meet, or meets only halfway. Tie it to
  the criterion's words.

Two disciplines keep the report trustworthy:

- **Separate real defects from by-design-for-this-slice.** A feature built in slices will have
  deliberately-unfinished edges (a later step stubbed, a lock not yet reachable). Flagging those as
  bugs is noise. When you're unsure which a thing is, check the issue's scope before you call it.
- **Note the positives worth knowing**, briefly. A boundary that held, an edge case handled well.
  It tells me what not to re-check, and it calibrates the bugs.

Every finding needs a **reproduction**: the exact steps, and the screenshot. A finding I can't
reproduce from your report isn't actionable.

## Step 5: deliver the verdict

The report is verdict-first, then the findings ordered by what I'd act on, then coverage. Follow the
writing rules in §30 and §33.

```
# QA of <PR/branch>, tested on <preview URL | local>

**Verdict.** <ship / fix these first / not close>, one line.
**Covered.** <criteria and flows exercised>. **Not covered.** <what you couldn't reach, and why>.

## Bugs
- <screen/path>, <what's wrong> → repro: <steps>. Severity: <high/med/low>. [screenshot]

## UX
- <screen>, <what's clumsy> → <the concrete change>. [screenshot]

## Intent gaps
- <criterion>, <how the change misses it>. [screenshot]

## Notes
- <positives, by-design edges, anything I shouldn't re-check>
```

An empty section gets no heading. Attach the screenshots, don't just name them.

### Where it goes: chat or the PR

The destination is my call, and the default is to **ask** if I didn't say. Chat is a private
briefing for me; a PR post goes out under my name where the author and everyone else reads it. Those
are different audiences, so never guess between them.

<!-- surface:local -->

**Attended run: ask, then default to chat.** If I said "report here" or "post it to the PR", do
that. If I said neither, ask which before publishing anything, and until I answer, the report lives
in chat and nothing goes to GitHub. When I do ask for a post, say what you'll post and where, wait
for my yes, then post as a PR review or comment (`gh pr review` / `gh pr comment`) and nothing else:
no merge, no close, no issue edit. Send the screenshots into chat with the report; a PR comment
can't embed a local file, so link or attach them where the runtime allows and describe the repro
precisely regardless.

<!-- /surface:local -->

<!-- surface:sandbox -->

**Unattended run: posting is the deliverable.** There's no chat for anyone to read and the sandbox
is torn down at the end, so a report you keep is QA that never happened. Post the verdict as a PR
review or comment under the bot's identity. Only the report goes out: no merge, no close, no issue
edit. Name what you couldn't cover, and if screenshots can't be attached from here, describe each
repro so it stands without the image.

<!-- /surface:sandbox -->

## Step 6: clean up

Leave the machine as you found it. Stop the dev server you started, `jj workspace forget` the
workspace and remove its directory, and don't leave a browser session or a local DB behind. If you
tested a preview, there's nothing to tear down. Say in the report what you left running if anything
has to stay up for me to look at.
