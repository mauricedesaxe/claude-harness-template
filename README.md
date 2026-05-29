# claude-harness-template

A portable workflow harness for [Claude Code](https://claude.com/claude-code) projects.
Install it in any repo with one command (`/bootstrap-harness`) and get the same
opinionated end-to-end flow: capture → work (plan → adversarial plan review → implement
→ review → ship) with atomic conventional commits, no `Co-Authored-By` trailers, and a
shared "Lemon Pie" UI vocabulary.

## What's in here

```
.claude/
  skills/
    work/                   pick up a GitHub issue end-to-end
    commit/                 atomic conventional commits, no --no-verify
    review/                 run reviewer agents on the diff, chat report
    capture/                file a GH issue — only if it clears the felt-value bar
    ship/                   land on main (branch/commit/push/PR/CI/rebase-merge)
    setup/                  fresh-clone onboarding skeleton
    neobrutalist-pop/       neo-brutalist UI tokens + components
  agents/
    code-reviewer.md        engineering-quality reviewer
    test-reviewer.md        adversarial test reviewer
    plan-reviewer.md        adversarial plan reviewer (run before code exists)
CLAUDE.md                   skeleton: universal philosophy + per-project TODOs
bootstrap-harness/
  SKILL.md                  the global skill that installs everything above
```

## Install (one-time, per machine)

The `bootstrap-harness` skill needs to live globally so it's available in any repo.
Copy it from this repo into your user-scope Claude skills:

```sh
git clone --depth 1 https://github.com/mauricedesaxe/claude-harness-template.git /tmp/cht
mkdir -p ~/.claude/skills/bootstrap-harness
cp /tmp/cht/bootstrap-harness/SKILL.md ~/.claude/skills/bootstrap-harness/SKILL.md
rm -rf /tmp/cht
```

From then on, `/bootstrap-harness` works in any Claude Code session.

## Use (per-project)

Inside any git repo:

```
/bootstrap-harness
```

Claude clones the template, overwrites the universal skills/agents into `.claude/`,
preserves any non-universal ones already there, and writes a `CLAUDE.md` skeleton (only
if one doesn't exist). Then fill the `<!-- TODO -->` markers in `CLAUDE.md` with the
project's specifics: what the project does, its architecture, the load-bearing bar
("the score stays trustworthy and explainable", "the latency budget stays under N",
etc.), area labels, and (if applicable) GitHub Project IDs.

## Customizing

The universal skills are deliberately opinionated. If you need to diverge for a
specific project — different test runner, no GitHub Project board, etc. — edit the
files in that project's `.claude/` after install.

**Improvements you'd want everywhere should be backported here.** Open a PR against
`mauricedesaxe/claude-harness-template`. The next `/bootstrap-harness` run picks it
up. There is no auto-sync — manual backport discipline is the price of having one
template feeding many projects with different needs.

## Philosophy in one breath

- **Atomic conventional commits**, no `--no-verify`, no `Co-Authored-By`.
- **Plan first, attack the plan, gate on the user, then write code.**
- **Fail loud, distinguish "no data" from "fetched zero"** — the "two zeros" rule.
- **No `throw` in app code** — return a `Result<T, E>`.
- **Parse at boundaries** — schema-validate every external response.
- **Pure domain core**, side effects live at the edges.
- **Rebase-merge**, linear history, branch commit messages good enough to live on
  `main`.
- **Felt product value** is the bar for issues — not "feature vs refactor".

Full text in `CLAUDE.md` (the universal sections are kept; per-project sections are
marked TODO).

## Not in here

- Domain-specific reviewer agents (e.g. a `payments-reviewer` or `geo-scoring-reviewer`)
  — ship them in the project's own `.claude/agents/` and list them in the project's
  `CLAUDE.md`. The `review` skill picks them up automatically.
- Hook configs (`lefthook.yml`, `.husky/`, etc.) — these are project-flavoured and live
  in the project repo.
- Anything WalkUp-specific. The skills started life there; the domain references are
  stripped out here.

## License

MIT. Take it, fork it, edit it, ship a variant tuned to your shop.
