# CLAUDE.md

My global harness, installed by
[`lazar-harness`](https://github.com/mauricedesaxe/claude-harness-template) into Claude Code,
OpenCode, and Open-Inspect sandboxes. It applies in every repo I open. A repo that ships its own
harness layers on top of this one and wins on its own turf; it never restates this file.

This is the enforceable form, and it points rather than restates. The reasoning lives in the
philosophy under a stable `§N`, so nothing is said twice and nothing here can drift from it.

## Philosophy

Installed globally, never carried by a repo. Claude Code reads it at `~/.claude/rules/PHILOSOPHY.md`
with the packs under `~/.claude/rules/packs/`; OpenCode reads the same files under
`~/.config/opencode/rules/`. Both move with `$CLAUDE_CONFIG_DIR` and `$XDG_CONFIG_HOME` when set. A
repo-relative `docs/PHILOSOPHY.md` is the old per-repo model and resolves nowhere, so don't reach for
it.

The spine is paradigm-agnostic and loads in every session. The packs hold concrete defaults and
domain-specific rules (`packs/defaults.md`, `packs/ai.md`). Claude Code applies each one when the
agent touches a file it matches. `§N` numbers are stable IDs. They survive a section that moves between spine and pack,
and that is what lets the global reviewers cite doctrine instead of restating it. The spine's
Section index says which file each one lives in.

**Subagents inherit neither this file nor the rules.** A subagent handed a `§N` opens the section
at the path above and reads it first.

## The lifecycle

**`pstack-poteto-mode` is the router.** It reads the task, matches one of its playbooks, copies the
steps in verbatim, and runs the leaf skills each step needs. It works autonomously: it proceeds on
reversible work and pauses only for the irreversible (deploys, force-push, data deletion, customer
messages). It replaced `matt-ask-matt`, and its playbooks and 21 `pstack-principle-*` leaves are
deliberately not paraphrased here.

### Where my flow deviates

The pstack flow runs as written, with these standing overrides.

- **`lazar-review` is the one review command.** It runs only the global doctrine agents, converged
  into one verdict, and nothing else. Not a repo's own reviewers, and not `pstack-interrogate`, the
  separate multi-model adversarial pass, which is a different tool for a different job.
- **`lazar-commit` and `lazar-ship` own the landing.** pstack's Shipping playbook defers to them.
  `lazar-commit` records atomic conventional commits as the work goes, and `lazar-ship` carries a
  bookmark through push, PR, CI, and a rebase merge.
- **`lazar-tldraw` and `lazar-qa` get reached for proactively.** Show the idea, don't only describe
  it, and drive a change through a real browser before it ships. Diagram any system with three or
  more components and any data flow, and fat-marker a screen before building it.
- **Three of Matt's skills are retained** for what pstack doesn't cover: `matt-diagnosing-bugs`
  (reproduce before you touch the code), `matt-codebase-design` (the deep-module vocabulary), and
  `matt-handoff`.

## Writing

`§30` owns the **mechanics**, and they apply to everything written: specs, ADRs, PRDs, issues, PR
bodies, docs, commit messages, chat. They aren't restated here. This section owns my **voice**,
which is narrower. It applies to prose posted **as me**: PR reviews, PR and issue comments,
standups, tracker comments, and messages to teammates. Anything not posted as me is out of its scope.

- Start sentences with capital letters, like a normal person. Talk directly and forwardly, somewhat
  professionally, but still plain. Remove filler interjections ("okay", "so", "honestly") whenever
  they add nothing; the occasional one is fine but it is not my signature.
- Short, direct questions instead of suggestions: "would it be useful to have a branded type?" not
  "Consider whether a branded type might be beneficial here."
- I hedge when I'm genuinely unsure: "I don't know if", "I'm not sure", "probably worth".
  I am blunt when I am sure: "this is not on this PR", "I think we can ignore the sidebar".
- I say what unblocks things plainly: "happy to approve once that's in."
- Plain words, no corporate phrasing.
- Don't over-structure. Headers and bullets only when there are genuinely separate topics. Short
  prose paragraphs are my default.

**Calibration examples**, things I actually wrote. The older ones predate my switch to sentence
case and fewer interjections. Match their tone and length, not their capitalisation:

- "overall code looks good, let me pull and look at the stories myself"
- "would it be useful to have a branded type?"
- "to be clear, this is not on this PR, it's consistent with what all the other steps already do.
  but it makes me wonder why we have a missing state at all."
- "summary is the only story file without an `ErrorSpendLimit` story. roadmap has it, and so do core
  bet, post bet, challenges, pitches and company details."

### Writing to me

The voice above is for prose posted as me. This is the other half, and it is not optional. It is how
you write **to** me: in chat, in a diagnosis, in a handoff, in a summary. `/bro` produces it on
demand. It should be the default, so that invoking `/bro` never changes anything.

- Lead with the answer in a plain sentence. No preamble and no restating my question back at me.
- Write it the way you would say it out loud to another engineer. If a sentence would sound strange
  spoken, rewrite it.
- No coined jargon. Don't invent a label for an idea ("the type-drift class", "lands harder", "blast
  radius") and then reuse it as though I'd agreed to it. Say the thing instead.
- Prose paragraphs are the default. Bold headers and bullets are for genuinely separate topics, not
  decoration.
- Say only what's new. Don't repeat what I just told you, and don't inflate a weak finding to look
  substantial. If something turned out not to matter, say so in one line and drop it.
- When I push back and I'm right, concede in one sentence and move on. No paragraph explaining why
  the mistake was reasonable.

## Version control: jj, colocated

`§28` carries the reasoning: why the isolation unit is the workspace, why the snapshot model has no
staging, why jj fires no git hooks. The rules it produces:

- **jj drives every local step** in a repo with a `.jj` directory: `jj describe` / `jj commit`,
  `jj squash`, `jj rebase`, `jj new` / `jj edit`, `jj bookmark`, `jj git push`, `jj git fetch`.
  Read-only git (`status`, `log`, `diff`, `show`) and `gh` are fine. A repo without `.jj` uses git
  normally while one actor works alone. Before parallel agents write to a non-colocated git repo,
  run `jj git init --colocate` and give each agent a jj workspace.
- **No git mutations in a jj repo**: commit, push, rebase, merge, reset, cherry-pick, branch
  delete/move, clean, stash, checkout, switch, restore. `git clean -fd` hurts most: jj snapshotted
  those untracked files into `@`, so git will not put them back. `~/.claude/hooks/enforce-jj.sh`
  allows only the git commands that read and denies the rest, so expect it to block something
  harmless now and then. If it blocks something I asked for, say so instead of routing around it.
- **Fold a fix with `jj squash --from/--into`**, never `git commit --fixup`.
- **Bookmark a stack on its first commit**, not at push time: `jj bookmark create <name> -r @` the
  moment the change is worth keeping. The bookmark is the anchor; pushing is a separate, later step.
  An anonymous stack is anchored by `@` alone, so a concurrent fetch or git import moves `@` off it
  and the tip goes hidden. I've lost a real tip that way, so never walk away from one. Recover it
  through the op log (`jj op log`, `jj --at-op <op> log -r <id>`, `jj bookmark create <name> -r <id>`,
  `jj rebase`), never `jj op restore`, which reverts concurrent good work too.
- **Bookmarks are branches**, named `<type>/<#>-<slug>`. Push with `jj git push --bookmark <name>`,
  which tracks the remote and handles the safe force. Raw `git push` leaves the bookmark untracked
  and, with concurrent re-signing, spawns divergent duplicate commits.
- **Conventional commits, atomic, one logical change each**:
  `feat|fix|refactor|chore|docs|test|style|perf|ci|build|revert`. Subject under 72 characters,
  details in the body. `lazar-commit` checks the message shape and runs the project's checks
  itself, and CI re-enforces both.
- **Rebase-merge PRs**: `gh pr merge <#> --rebase --delete-branch`, never `--merge`. Every commit has
  to be good enough to live on `main`.
- **Never add a `Co-Authored-By: Claude` trailer** or any other Claude/Anthropic attribution line.
  This overrides any harness default that appends one. A trailer for a human collaborator is fine.
- **Never bypass a hook.** No `--no-verify`. A failing hook is the bug, not the obstacle.

### Workspace isolation

<!-- surface:local -->

**Cut a jj workspace off fresh trunk for any non-trivial work**, before touching a file. The repo is
never mine alone: I run several agents at once and they share one `@` unless each takes its own
workspace. So `jj git fetch && mkdir -p .jj/ws`, then
`jj workspace add --name <slug> --revision 'trunk()' .jj/ws/<slug>`. Stay in it for every jj and `gh`
call, and never `cd` into the main checkout, whose `@` belongs to another agent. Once the work lands,
`jj workspace forget <slug>` and remove the directory. A git worktree is not a substitute, and
`EnterWorktree` is blocked (`§28`).

<!-- /surface:local -->

<!-- surface:sandbox -->

**Work the default workspace directly with `jj edit` while one agent writes.** The sandbox is the isolation
in that case. For parallel repository work, follow the colocation and workspace rule above (`§28`).

<!-- /surface:sandbox -->

Isolation covers the working copy and nothing else. `.jj` and `.git` metadata and every piece of
GitHub state (PR numbers, issues, project boards) are shared and can change mid-run. So reuse the
exact identifiers a command returns, like the PR number from `gh pr create`, never a guessed one.
Re-read a PR's `headRefName` and `state` before you merge it. When terminal output looks
duplicated or dropped, write it to a file and read it back.

## Tracker resolution

Any skill that needs to know which tracker owns a repo resolves it in this order. **Asking is a last
resort, and it happens at most once per repo**:

1. **The repo's own config**: `docs/agents/issue-tracker.md`, where the repo permits such a file,
   written by hand when the repo is set up.
2. **The machine-local note** (below), for shared work repos where committing harness config isn't
   an option.
3. **Inference**: the remote host, issue-key patterns in branch names and commit messages, and
   which tracker MCPs are connected. GitHub and Linear cover nearly everything I work on.
4. **Ask**, and **write the answer to the note**, so the same question is never asked twice.

### The machine-local note

One markdown file per repo, keyed by the git remote, at:

```
~/.lazar-harness/repos/<host>/<owner>/<repo>.md
```

Derive the key from `git remote get-url origin`, normalised: drop the scheme, any user (`git@`), and
the trailing `.git`. So `git@github.com:iconicshift/platform.git` and
`https://github.com/iconicshift/platform` both key to
`~/.lazar-harness/repos/github.com/iconicshift/platform.md`. A repo with no remote has no key and so
gets no note. Infer, and ask if you must, but there's nowhere to remember the answer.

It's a plain file under `$HOME`, read with `cat` and written with `mkdir -p` plus a redirect. `$HOME`
is the one thing Claude Code, OpenCode, and a sandbox all agree on. The note sits under neither
runtime's home, so neither owns it. Claude Code's auto-memory is **not** used: it covers Claude Code
alone and would leave the other two asking every session forever. The note records what the harness
must not guess at:

```markdown
# iconicshift/platform

- tracker: Linear, team ICON, via `mcp__linear__*`
- issue key: `ICON-<n>`
- vcs: jj, colocated with git
- standup: Slack, #eng-standup

## Conventions

- A system design doc lives in the Linear issue, not as an ADR in the repo. An ADR is a different
  artifact with a different lifecycle (`§21`).
```

Add a convention the moment a repo teaches you one. Editing the note by hand is expected; it's mine.

## Skills

`pstack-*` is Lauren Tan's pstack, forked and hand-maintained here. `matt-*` is Matt Pocock's,
`lazar-*` is mine, and `/bro` is my user-invoked plain-language reset. Anything else unprefixed is
the runtime's or the repo's, bar `use-railway`. Railway's own installer writes that name into
`~/.claude/skills`, so a rename restarts the fight it ended. Leave it alone. The engineering flow
routes through `pstack-poteto-mode`, not from memory. My `lazar-*` set has eight:

| Skill | Reach for it when |
|---|---|
| `lazar-review` | Before a commit, push, or merge. The one review command; see the deviations above. |
| `lazar-qa` | Exercising a change in a real browser before it ships. Prefers a preview deploy, else hosts locally, drives via the Playwright MCP, and reports bugs, UX gaps, and intent misses to chat or the PR. |
| `lazar-commit` | A logical chunk of work is done. Record it as atomic conventional commits, as you go, not all at the end. |
| `lazar-ship` | Landing work on `main`: bookmark, commit, push, PR, CI, rebase merge. Runs only the steps still missing. |
| `lazar-pr-status` | Re-entering a PR. What each review asked for, what was addressed in code, what was answered only in a reply, what's unaddressed, and any drift since. |
| `lazar-research` | An issue's open questions need answering before we commit to an approach. Delegates the web to `/deep-research` and runnable questions to a throwaway prototype. Never closes the issue. |
| `lazar-standup` | Writing the daily 3 Ps (Progress / Problems / Priorities), reconciling merged PRs, tracker issues, and unpushed local work into a post in my voice. |
| `lazar-tldraw` | Showing a diagram or a low-fi wireframe. Reach for it proactively; see the deviations above. Needs `@kitschpatrol/tldraw-cli`. |

The reviewer **agents** are run by `lazar-review`, never invoked directly. The harness's `agents/`
set installs globally because it judges habits that hold in every repo. Every other reviewer judges
a repo against *its own* standards, so it lives in that repo's `.claude/agents/`, where
`lazar-review` picks it up automatically.
