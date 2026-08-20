# Automated-reviewer triage

Use this reference when the Babysit playbook (`../playbooks/babysit.md`) handles comments from an
automated reviewer: a CI bot, a security scanner, a linter, or any bot that files findings on a PR.
The goal is not to ignore the bot by default. The goal is to stop treating every comment as a
required code change.

## Decision rubric

Classify each thread before acting:

- `fix`: The comment identifies a plausible correctness, security, privacy, data loss, auth,
  billing, migration, idempotency, race, or shipped-behavior issue. Fix it in the lowest owning PR,
  then reply with the commit SHA and resolve the thread.
- `dismiss`: The comment matches a documented low-risk noisy pattern, and the current code proves
  the concern does not need a code change. Reply with a short reason and resolve the thread.
- `ask`: The comment is novel, high-severity, security, privacy, or data-related, or ambiguous. Ask
  the user instead of guessing.

When in doubt, ask. Skipping a noisy code-quality comment is cheap; skipping a real data or security
bug is not.

## Ask by default

Do not auto-skip these categories, even if a previous PR dismissed something similar:

- Security, privacy, auth, billing, data retention, and permission-boundary findings.
- High-severity findings.
- Migration, schema, idempotency, concurrency, and cross-system behavior findings.
- Comments where the suggested fix is small and clearly reduces risk without changing product intent.

## Learned pattern format

This harness ships no accumulated skip list. Accumulate your own as real dismissals recur, in this
shape, so a documented pattern replaces a repeated judgment call (the **encode-lessons-in-structure**
principle skill):

```markdown
### <short pattern name>

- Confidence: candidate | recurring | strong
- Skip when: <conditions that must be true>
- Do not skip when: <risk boundaries>
- Example signal: <phrases or code context that identify the pattern>
- Source: <PR/comment URL or short historical note>
```

Use `candidate` for one or two examples. Use `recurring` after multiple real dismissals. Use
`strong` only when the pattern is narrow, repeatedly verified, and low-risk. Promote a candidate
into a standing section here once several PRs confirm it.
