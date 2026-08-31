---
name: lazar-ux-audit
description: Drive a change through a real browser and judge its UI and UX against the design principles in §34. Same target resolution and browser discipline as lazar-qa, but the scorecard is the §34 heuristic checklist, not the issue's acceptance criteria. Reports visual design gaps (hierarchy, spacing, color, depth, type, action order) and cognitive fit gaps (Hick, Fitts, Jakob, Miller, serial position, Von Restorff, proximity, aesthetic-usability), each tied to a screenshot and a concrete change. Use when I say "/lazar-ux-audit", "audit the UX", "review the UI", "check the design", or want a change judged against the design principles before it ships.
---

# lazar-ux-audit

I point at a change. You open the real app, drive it like a user, and tell me where the interface
fails the design principles in §34.

This is the design counterpart to `lazar-qa`. `lazar-qa` asks "does it work, and does it do what
the issue asked." This skill asks "does it read well, and does it fit how the user thinks." The two
share a target and a browser, and nothing else. Run `lazar-qa` for bugs and intent. Run this skill
for design.

## Step 1: resolve the change and get a running app

Do exactly what `lazar-qa` Step 1 and Step 2 do. Resolve the change (PR, branch, or working copy),
read the diff to learn the screens and states the change touches, and get a real running app, a
preview deploy first and local as the fallback. Isolate in a jj workspace per **Workspace
isolation** in `CLAUDE.md`.

The diff read serves a different purpose here than in `lazar-qa`. There it builds a functional test
plan. Here it builds the **audit surface**: every screen, state, and flow the change made visible.
Those are the things you judge against §34.

## Step 2: drive the browser, and prove it

Same hard rule as `lazar-qa` Step 3. Use the Playwright MCP and actually click. Every finding comes
from a real browser interaction with a screenshot. A judgement derived from reading the component
source is not an audit finding. Screenshot every meaningful state and every finding, check
`browser_console_messages` at the error level as you go, and resize to a phone viewport for the
primary public flow.

Cover the audit surface deliberately:

- The **happy path** end to end, once.
- **Each state** the change reaches: default, loading, empty, error. §14's two zeros apply.
  "Genuinely nothing here" and "it broke" are different screens. Judge both.
- **Mobile**: a phone viewport (390×844 is a fine default) on the primary flow.
- **Roles** if the change has them: each principal sees its own surface.

## Step 3: judge against §34

Score every observation against the two checklists in §34, and sort each into its bucket. Every
finding names the screen, the principle it fails, the screenshot, and the concrete change. "Looks
off" is not a finding.

**Visual design** (Refactoring UI, §34):

- **Hierarchy.** Is emphasis spent on the few things that matter? Flag a screen where everything
  competes for attention, or where the primary action does not read as primary.
- **Spacing.** Does proximity carry the relationships? Flag cramped groups, orphaned labels, and an
  inconsistent rhythm between sections.
- **Color.** One accent and its shades, or many hues fighting? Flag low-contrast text, decorative
  color, and a palette that drifts across screens.
- **Depth.** Do shadows and elevation mark what the user can act on? Flag flat-but-interactive and
  raised-but-static.
- **Type.** Is body text readable? Flag thin body copy, long measures, and tight line-height on long
  passages.
- **Action order.** Is there one primary action per view? Flag competing primary buttons and a
  secondary action styled as primary.

**Cognitive fit** (Laws of UX, §34):

- **Hick.** Any screen that asks for a decision among too many options at once.
- **Fitts.** Primary targets too small or too far from where the user is.
- **Jakob.** A control that breaks convention without a named reason (a custom dropdown where the
  native one would do, a non-standard checkbox).
- **Miller.** A long ungrouped list that asks the user to hold it in working memory.
- **Serial position.** Key actions buried mid-sequence, or a destructive action placed where the user
  skims past it.
- **Von Restorff.** The important thing not distinct from its neighbors, or the wrong thing
  distinct.
- **Proximity.** Related fields or actions sitting apart, or unrelated ones sitting together.
- **Aesthetic-usability.** Polish gaps that lower the user's tolerance for real friction. Judge
  substance, not preference.

**Accessibility** is not a §34 heuristic, it is a floor. Carry `lazar-qa`'s a11y checks forward:
keyboard reach, focus order, labels on inputs. A finding that is both a §34 gap and an a11y failure
gets filed under the bucket it most needs fixing for, and notes the other.

**A deliberate visual style is not a finding by itself.** §34's earn-its-keep clause covers
neo-brutalism, dense data UIs, terminal tools. Name the style, and check it still honours the
underlying principle: hierarchy, proximity, the important thing standing out. File a finding only
when the style drops a principle, not when it picks a vocabulary you would not.

Note the positives worth knowing, briefly. A hierarchy that reads, a flow that fits. It calibrates
the gaps.

## Step 4: deliver the verdict

Verdict-first, then findings ordered by impact, then coverage. Follow the writing rules in §30 and
§33.

```
# UX/UI audit of <PR/branch>, tested on <preview URL | local>

**Verdict.** <ships as-is / fix these first / rework>, one line.
**Covered.** <screens and states judged>. **Not covered.** <what you couldn't reach, and why>.

## Visual design
- <screen>, <principle>, <what fails> → <the concrete change>. [screenshot]

## Cognitive fit
- <screen>, <heuristic>, <what fails> → <the concrete change>. [screenshot]

## Accessibility
- <screen>, <what fails> → <the concrete change>. [screenshot]

## Notes
- <positives, deliberate-style judgements, anything I shouldn't re-check>
```

An empty section gets no heading. Attach the screenshots, don't just name them.

### Where it goes: chat or the PR

The destination is my call, and the default is to **ask** if I didn't say. Chat is a private
briefing for me; a PR post goes out under my name where the author and everyone else reads it. Those
are different audiences, so never guess between them.

<!-- surface:local -->

**Attended run: ask, then default to chat.** If I said "report here" or "post it to the PR", do
that. If I said neither, ask which before publishing anything, and until I answer the report lives
in chat and nothing goes to GitHub. When I do ask for a post, say what you'll post and where, wait
for my yes, then post as a PR review or comment (`gh pr review` / `gh pr comment`) and nothing else:
no merge, no close, no issue edit. Send the screenshots into chat with the report; a PR comment
can't embed a local file, so link or attach them where the runtime allows and describe each finding
precisely regardless.

<!-- /surface:local -->

<!-- surface:sandbox -->

**Unattended run: posting is the deliverable.** There's no chat for anyone to read and the sandbox
is torn down at the end, so a report you keep is an audit that never happened. Post the verdict as a
PR review or comment under the bot's identity. Only the report goes out: no merge, no close, no
issue edit. Name what you couldn't cover, and if screenshots can't be attached from here, describe
each finding so it stands without the image.

<!-- /surface:sandbox -->

## Step 5: record the run

Write the record before you clean up, to the contract in `records.md`, which sits beside the spine
in the rules directory. The repo's own convention wins where it has one; otherwise the record goes
to the machine-local store keyed by the git remote.

`kind: ux-audit`. The verdict is the same word the report leads with, one of `ships as-is`,
`fix first`, or `rework`. Count the sections you just wrote into `visual`, `cognitive` and
`accessibility`, set `findings_total` to their sum, and set `surface` by where you tested. The body
is the report verbatim, screenshot paths left as paths.

The record is never the deliverable and never delays it. Where it cannot be written, say so in one
line and clean up anyway.

## Step 6: clean up

Leave the machine as you found it. Stop the dev server you started, `jj workspace forget` the
workspace and remove its directory, and don't leave a browser session or a local DB behind. If you
tested a preview, there's nothing to tear down. Say in the report what you left running if anything
has to stay up for me to look at.
