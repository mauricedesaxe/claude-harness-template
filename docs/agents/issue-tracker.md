# Issue tracker

Issues for this repo live in **GitHub Issues**, on `mauricedesaxe/claude-harness-template`.

Skills that read from or write to the tracker (`to-tickets`, `triage`, `to-spec`, `wayfinder`,
and the `lazar-*` skills) use the `gh` CLI:

- read: `gh issue list`, `gh issue view <n>`
- write: `gh issue create`, `gh issue edit <n>`
- link: `Closes #<n>` in a PR body

**PRs as a request surface:** off. External PRs do not enter the triage queue.

## Triage labels

The five canonical roles, each label string equal to its name:

`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`

Only `ready-for-agent` exists on the repo so far; the rest are created on first use.
