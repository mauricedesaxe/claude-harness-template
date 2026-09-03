### Orchestrate

<!-- surface:local -->

Orchestrate is not a local route. Use **Autonomous run** when one agent can drive the work to one
done predicate. Use **pstack-figure-it-out** for a large, cross-cutting, or multi-part run that needs
a custom playbook.

Do not add a local coordination store. The local runtime shares one filesystem, so the extra state
would duplicate the task and version-control state that existing workflows already own.

**Reply:** name the selected route and why it fits.

<!-- /surface:local -->

<!-- surface:sandbox -->

**You own the program, never the code. Author complete briefs, drain completions, keep the frontier
green, and decide.** Use this playbook for a standing program that outlives one agent. It fits
multi-day work, many PRs, and dozens to hundreds of background children. Use Autonomous run for one
task driven to a predicate. Use **pstack-figure-it-out** for one ambitious run that needs a custom
workflow.

Measured head-to-head, this coordination cost turned one half-hour, 12-unit job into one landed
unit while a plain agent landed all 12. If one agent can finish within the session budget, stop and
use Autonomous run. At about 70 percent of the wall-clock budget, stop new work and land verified
units. Finished work that never lands counts as zero.

Open a todolist with the steps below copied in verbatim. Keep a skipped step with
`skip: <reason>`.

#### Ownership and durable state

Use Beads only when the target repository's origin already has `refs/dolt/data` or the user
explicitly asks you to initialize it. Check the origin first:

```sh
git ls-remote --exit-code origin refs/dolt/data
```

When the ref exists, adopt and refresh its graph before any Beads read or mutation:

```sh
bd bootstrap
bd dolt pull
bd prime
```

Do not replace this sequence with an empty local initialization. If the ref does not exist and the
user did not ask for initialization, use **pstack-figure-it-out**. Never initialize Beads by
inference. If the user asked, run `bd init --skip-agents --skip-hooks` once. Run `bd prime` before
the first graph operation, then commit and push the resulting state.

The root coordinator is the sole Beads writer. A Beads epic owns the program's task beads and
dependency edges. Children receive immutable briefs with their bead IDs. They never create, update,
close, or push beads. Do not use JSONL as a sync mechanism. Never force a Beads push.

GitHub and jj own branches, commits, bookmarks, PRs, merges, and stack order. Child-session tools
own live session state. Beads does not own either. Existing Lazar records own verification evidence
when their contract applies. A task bead can point to that evidence, but it does not replace it.

After every durable transition, run `bd dolt commit -m "<transition>"`, then `bd dolt push`. Durable
transitions include program creation, task and dependency creation, assignment, a new pushed head
SHA, a PR, a verification verdict, a blocked state, a task close, and program close. If a commit or
push fails, stop Beads writes. Reconcile the remote state, then retry without force.

#### Roles

- **Root coordinator.** Frames the program, writes Beads, authors briefs, starts background
  children, drains completions, and reports to the human. It does not edit program code. Code fixes,
  conflicts, and restacks are tasks for children. The coordinator may perform mechanical landing
  only when the relevant landing workflow allows it.
- **Track coordinator.** Add one only when the root cannot process one rolling window. It receives
  an immutable track brief. It can start and drain its own children, but it sends state changes to
  the root. It never writes Beads. Keep the hierarchy to root, track, and worker.
- **Worker or verifier.** Runs through the existing background child tools. Give each repository
  writer one jj workspace or bookmark. Use a verifier from a different model family for expensive,
  judgment-heavy, or high-risk work. A cheap deterministic command stays with the worker, and the
  root spot-checks its receipt.

Prefer fewer, broader children. Keep about ten children in flight when one drain can process that
many. Refill the rolling window as children finish. Do not wait for a blocking batch, which pays for
the slowest child in every batch.

#### The brief

Every child gets the complete brief. A missing field means the task is not ready.

```text
BEAD         task bead ID; epic bead ID
GOAL         one sentence with an outcome a stranger can execute
SCOPE        paths allowed and forbidden; exclusive jj workspace or bookmark
CONTEXT      files, PRs, and complete upstream reports needed by this task
DEPENDENCIES prerequisite bead IDs and the facts each dependency produced
ACCEPTANCE   checkable criteria, one per line
VERIFY       exact commands or control-skill path, plus known problems
TIMEBOX      runtime cap; return partial findings when it expires
FORBIDDEN    no Beads writes, no rebase, no force, and no work outside scope
REPORT       status, bead ID, child session ID, branch, head SHA, PR, verdict,
             commands run, deviations, and suggested follow-ups
STANDING     all program constraints, copied verbatim
```

Collapse the template for a one-command task, but keep the bead ID, goal, scope, verification, and
report shape. A dependency carries context, not only order. Paste the upstream result into the
downstream brief because children cannot read sibling sessions. Never resume with a partial prompt.
Start a fresh child with a consolidated brief when the scope changes.

Audit one sampled brief per track during each wave. Do not gate the current wave on that audit. If
the brief fails, stop the next refill and fix the track coordinator's contract.

#### Steps

1. **Frame.** Write a countable done predicate. Quantify tasks, effort, expected PRs, and the
   wall-clock budget. Name the tracks. If one agent can finish within the budget, use Autonomous run.
   Send contested decomposition or an irreversible design choice through **pstack-arena** first.
2. **Create durable state.** Confirm the remote Beads ref or the explicit initialization request. If
   the ref exists, run `bd bootstrap`, `bd dolt pull`, and `bd prime` before any graph command. Create
   one epic with `bd create --type epic --title "<program>"`. Create task beads with
   `bd create --type task --title "<task>" --parent <epic-id>`. Add each dependency with
   `bd dep add <task-id> <prerequisite-id>`. Commit and push Dolt after this setup.
3. **Pilot.** Move one task through brief, worker, independent verification when needed, PR, exact-SHA
   verdict, and merge. Use `bd update <task-id> --status in_progress` before work. Record the child
   session ID with `bd update <task-id> --notes "child: <session-id>"`. Fix the task size and brief
   from pilot evidence before broad fan-out. For cheap repeated tasks, the first normal task is the
   pilot.
4. **Scale.** Query ready work with `bd ready`. Start a rolling window through the background child
   tools. Relay dependency results into each immutable brief. Add a track coordinator only after one
   root drain cannot keep up.
5. **Drain.** Process completions in groups after a critical section, at a track report, before a
   human report, and before a landing action. Classify each task as ready for verification, blocked,
    failed, abandoned, or ready to land. Apply all Beads updates as the root, then commit and push
    Dolt.
6. **Land.** Land continuously from the first verified task. Keep the merge frontier green. Use one
   stacker per stack for serialized jj rebases. Update each bead with its branch, PR, current head
    SHA, and landing state. Commit and push Dolt after each important change.
7. **Close.** Reconcile every child to a terminal task state. Confirm the done predicate against the
   repository and merged PRs. Confirm that each landed PR has a verdict for its exact current head
   SHA. Close tasks with `bd close <task-id> --reason "<result>"`. Close the epic only after every
    task is terminal. Commit and push Dolt after the final task and epic transitions.

#### Drain and stack safety

Completions are queue events, not interrupts. Finish the current critical section before a drain.
Critical sections include brief creation, a stack operation, a conflict decision, a Beads update,
and a human gate. A completion that needs review becomes a verifier task. Do not review a large diff
inside a drain.

At each drain, use the child-status tool once for the completed set. Account for every child as
arrived, respawned, abandoned, or absorbed into a named replacement task. Recompute ready tasks with
`bd ready`, update the affected beads, push Beads, and refill the window in one tool call.

Exactly one stacker per stack may run `jj rebase`. Workers never rebase. Babysitters follow
`playbooks/babysit.md` against one observed frontier. PR closure, retargeting, and stack surgery go
through the stacker. Re-read GitHub and jj after every merge or stack change. Never infer stack state
from Beads.

#### Verification

Every verdict is keyed by PR number and exact head SHA. A new head SHA voids the old verdict. CI
green is evidence, not a verdict. Behavioral work needs more than a type check. A blocked verifier
does not pass. A failed verifier creates a fix task, not a repeat of the same verification.

Use the existing Lazar record when the verification skill writes one. Otherwise, put the exact
command and result in the child report. The root records the session ID, exact head SHA, and verdict
on the task bead, then commits and pushes Dolt. A machine-local Lazar record inside a disposable
sandbox is not a durable pointer. The background-agent session transcript remains the evidence owner.

A task is not complete until its code and evidence survive its child. The worker pushes its branch.
The verifier writes its record where required and returns the verdict in its child report. The root
writes the session ID, branch, PR, head SHA, and verdict to the task bead.

#### Recovery and failure

Do not resume a child to check whether it is alive. Read child status. Recover work by child session
ID, pushed branch, PR, and exact head SHA. Treat the transcript as context, not durable program state.

Retry by failure type. Shrink scope after a cap or memory failure. Retry a network failure as-is.
Use a different model after a tool failure. Retry an unknown failure once. After two retries, abandon
the task and replan its dependants.

Reconcile a late child against the current branch, PR, and head SHA before accepting anything. Put
unique findings into a fresh task. Never merge late work without this check.

After a runtime restart, run `bd bootstrap`, `bd dolt pull`, and `bd prime` before any graph read.
Then read the epic with `bd show <epic-id>`, query open work with `bd list`, and query ready work with
`bd ready`. Reattach work by child session ID, branch, PR, and head SHA. Spawn replacement track
coordinators from complete current briefs. Do not assume a prior local session is alive.

If broken inputs or infrastructure make further fan-out unsafe, stop new children. Let current
children finish, fix the cause, and resume from Beads. Bound coordinator retries too. When the
executor stays unavailable, push the last durable Beads transition and return a handoff with the
exact resume command.

#### Escalation

Batch human gates. Ask only about irreversible actions, true product choices, a standing order that
conflicts with observed facts, or a program dead end that survived a replan. Route other work around
the gate.

Do not ask about retries, CI triage, formatting, stack maintenance, or whether to continue. Fix only
discoveries that block the merge frontier. Put other discoveries into follow-up task beads when they
belong to this program, then push Beads.

**Reply:** report the done predicate and task counts from Beads. Name what each track landed. List
the PR frontier with exact head SHAs and verdicts. Name abandoned tasks and open human gates. Include
the epic ID and only those Lazar record paths that survive the sandbox. Do not claim that Beads
stores branches, GitHub state, session transcripts, or verification evidence.

<!-- /surface:sandbox -->
