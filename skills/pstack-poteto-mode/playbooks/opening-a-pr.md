### Opening a PR

Invoked at the end of every other playbook.

**Workspace.** In a jj repo, cut a workspace off fresh trunk per `§28` (`jj git fetch`, then `jj workspace add --revision 'trunk()'`), or work the default workspace directly when one sandbox agent writes. Prepare parallel repository writers through the **separate-before-serializing-shared-state** principle skill. Each gets a jj workspace because a shared `@` collides. A lone agent can use plain git.

**Commits.** Record atomic conventional commits, one logical change each, as the work goes, via the **lazar-commit** skill. Each commit is landable and ordered to tell the story. Fold a fix into an earlier commit with `jj squash --from/--into`, never `git commit --fixup` (`§28`).

**PRs.** Apply the **pstack-unslop** skill to the diff, the PR description, and commit bodies; run the **pstack-no-comments** skill over the diff before review. Small PRs, 5 narrow over 1 fat. For a stacked change, a jj stack of bookmarks named `<type>/<#>-<slug>`; the principle is small, ordered slices with the stack visible to reviewers. `gh pr view <number>` before referencing PR status. No `## Summary` / `## Test plan` boilerplate on small PRs; commit bodies don't restate the subject. The full push, PR, CI, and rebase-merge is the **lazar-ship** skill. After opening, the **Babysit** playbook; push back when feedback drifts from intent.

A subagent that opens a PR runs `interrogate`, the **pstack-unslop** skill, and the **pstack-no-comments** skill, returns the URL, and does NOT babysit. Return to the parent.
