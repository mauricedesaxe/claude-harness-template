# Records

A **record** is a snapshot of one run of a judging skill, written at the moment the verdict is
delivered. `lazar-qa`, `lazar-ux-audit`, and `pstack-interrogate` each write one. The verdict itself
still goes to chat or the PR exactly as before. The record is the copy that survives the window.

A record is not an ADR. §21 retires an ADR once its decision lands, because an ADR argues a choice.
A record states what a run found at one sha, so it stays true forever and is never archived.

## Why the fields are structured

The point of a record is a later reader who counts. "How many rounds has this had, and did the last
one come back clean" is the question, and it gets asked by a standup, by a PR review, and by me
re-entering work after a week.

A free-text verdict cannot answer it. One repo that already keeps records this way has 95 of them
carrying twelve different spellings of the verdict, and only 7 with a finding count anywhere in the
frontmatter. Every count had to be recovered by opening bodies and counting by hand. So the verdict
comes from a closed set per kind, and the counts are their own fields.

## Where a record goes

In this order, first hit wins:

1. **The repo's own convention**, where it has one. A repo that already writes `work/<issue>/reviews/`
   takes the record there, in its own shape, and this contract yields to it. Match the neighbours.
2. **The machine-local store**, keyed by the git remote exactly as the tracker note is:
   `~/.lazar-harness/records/<host>/<owner>/<repo>/<kind>/`. So `git@github.com:iconicshift/platform.git`
   keys to `~/.lazar-harness/records/github.com/iconicshift/platform/qa/`.
3. **A repo with no remote has no key**, so it gets no record. Say so in one line and move on.

The filename is `<stamp>-<short-sha>-<session-short>.md`: a `YYYYMMDDTHHMMSSZ` stamp, the first 12
characters of `head_sha`, and the first 8 of `session_id`. Where no session id is available, drop
the third segment rather than inventing one.

Never block the deliverable on the record. If the record cannot be written, report the verdict and
say in one line that it went unrecorded.

## Frontmatter every record carries

```yaml
---
kind: qa | ux-audit | interrogate
recorded_at: <ISO 8601 UTC>
head_sha: <full sha of the tree that was judged>
target: <PR number, branch, or path that was judged>
session_id: <uuid, omit when the runtime exposes none>
harness: <the runtime you are actually running in>
orchestrator_model: <the exact model id you are running as>
round: <1 for the first run against this target, then up>
verdict: <one value from this kind's set below>
findings_total: <integer>
---
```

`harness` records the runtime you are in, not the one you wish you were in. An OpenCode run says
OpenCode. `round` counts runs against the same target, so read the store for this target before you
write, and never restart the numbering because a new session began.

## The per-kind fields

**`kind: qa`**, from `lazar-qa`. Verdict is one of `ship`, `fix first`, `not close`, the same word
the report leads with.

```yaml
bugs: <integer>
ux: <integer>
intent_gaps: <integer>
surface: preview | local
screenshots: <count, or 0 where the runtime attached none>
```

**`kind: ux-audit`**, from `lazar-ux-audit`. Verdict is one of `ships as-is`, `fix first`, `rework`.

```yaml
visual: <integer>
cognitive: <integer>
accessibility: <integer>
surface: preview | local
screenshots: <integer>
```

**`kind: interrogate`**, from `pstack-interrogate`. Verdict is `changes requested` when anything
landed in Act on, and `no changes requested` otherwise.

```yaml
act_on: <integer>
consider: <integer>
noted: <integer>
dismissed: <integer>
reviewers:
  - model: <slug>
    findings: <integer>
consensus: <count of findings two or more models raised independently>
disagreements: <count of findings one model raised and another contradicted>
pool_dropped: <slugs that would not resolve, omit when none>
```

`reviewers` is what makes an interrogate record worth keeping. Which model saw what is the one thing
the chat window holds and nothing else does.

## The body

The body is the report you delivered, verbatim, and nothing else. No self-assessment, and no
comparison to an earlier record. Include the findings you dismissed, each with the reason, because a
record shows what was considered and not only what survived.

Screenshots stay where the run wrote them and the body names their paths. Never inline an image and
never copy a screenshot into the record store.

Records inherit §12's rule on what never gets logged. No secrets, no tokens, and no PII in either
the frontmatter or the body. A finding that only makes sense with a credential in it gets described
instead of quoted.
