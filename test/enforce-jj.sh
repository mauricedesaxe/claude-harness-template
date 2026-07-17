#!/usr/bin/env bash
# Drives hooks/enforce-jj.sh with synthetic PreToolUse payloads. Synthetic because the alternative
# is attempting the mutations it exists to stop, and a test that proves a matcher by running
# `git push` for real proves it once and costs a branch. The payloads are the same shape Claude
# Code sends, and the decision is read back out of the hook's own JSON.
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HARNESS_SOURCE/hooks/enforce-jj.sh"
failures=0

pass() { printf 'ok   %s\n' "$1"; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

# A jj repo, and a plain git repo standing in for every repo this hook has no business in. The
# nested dir is not decoration: the hook walks up for `.jj`, and an agent's cwd is rarely the root.
JJ_REPO=$(mktemp -d)
GIT_REPO=$(mktemp -d)
trap 'rm -rf -- "$JJ_REPO" "$GIT_REPO"' EXIT
mkdir -p -- "$JJ_REPO/.jj" "$JJ_REPO/src/deep" "$GIT_REPO/.git"
JJ_CWD="$JJ_REPO/src/deep"

# The hook stays silent to allow, so an empty response is the allow, not a jq failure.
decision_of() {
  if [ -z "$1" ]; then
    printf 'allow'
  else
    printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "malformed"'
  fi
}

reason_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""'
}

bash_response() {
  jq -n --arg cwd "$1" --arg command "$2" \
    '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$command}}' | "$HOOK"
}

assert_bash() {
  local want=$1 cwd=$2 command=$3 got
  got=$(decision_of "$(bash_response "$cwd" "$command")")
  if [ "$got" = "$want" ]; then
    pass "$want: $command"
  else
    fail "$want: $command (got $got)"
  fi
}

# A denial that does not say what to do instead is a denial an agent retries, so every matcher's
# message is pinned to the jj command it is steering toward, not just to the fact that it denied.
assert_reason() {
  local wanted=$1 cwd=$2 command=$3
  case "$(reason_of "$(bash_response "$cwd" "$command")")" in
  *"$wanted"*)
    pass "the denial of '$command' names $wanted"
    ;;
  *)
    fail "the denial of '$command' names $wanted"
    ;;
  esac
}

# The verbs that sat in no list in this file at all and were allowed for it. `git clean` is the
# sharp one: jj snapshots untracked files into `@`, so they are not junk git can regenerate, and
# `git clean -fd` is what an agent reaches for when it wants a tidy tree. Each of these is denied by
# a matcher of its own rather than by the catch-all, so each is named here rather than folded in.
for unlisted in \
  'git clean -fd' \
  'git clean -fdx' \
  'git clean -n' \
  'git stash' \
  'git stash push -m wip' \
  'git stash pop' \
  'git checkout -b feature' \
  'git checkout main' \
  'git checkout -- src/x.ts' \
  'git switch -c feature' \
  'git restore .' \
  'git restore --staged src/x.ts'; do
  assert_bash deny "$JJ_CWD" "$unlisted"
done

# The point of the direction change. None of these is in any list in the hook, and every one of them
# writes; under a deny list each was allowed, silently, for as long as nobody thought of it. Under
# an allow list the answer for an unrecognised subcommand is deny, so this set needs no maintenance
# to keep working — which is the property being pinned, more than any one row.
for unrecognised in \
  'git gc --prune=now' \
  'git rm -r --cached src' \
  'git mv a b' \
  'git apply patch.diff' \
  'git update-ref refs/heads/x HEAD' \
  'git filter-branch --tree-filter true HEAD' \
  'git reflog expire --expire=now --all' \
  'git remote add origin git@example.com:x/y' \
  'git remote remove origin' \
  'git tag v1.0.0' \
  'git tag -d v1.0.0' \
  'git notes add -m note' \
  'git config user.email me@example.com' \
  'git config --global --unset user.name' \
  'git submodule update --init' \
  'git fetch --prune' \
  'git pull --rebase' \
  'git prune' \
  'git bisect start' \
  'git replace a b' \
  'git this-subcommand-does-not-exist'; do
  assert_bash deny "$JJ_CWD" "$unrecognised"
done

# `git worktree add` and `git branch -D` are mutations too, but each is denied by a matcher of its
# own with its own message, so each is named rather than folded into the list below.
for mutation in \
  'git commit -m wip' \
  'git push origin main' \
  'git rebase -i main' \
  'git merge feature' \
  'git reset --hard origin/main' \
  'git cherry-pick abc123' \
  'git revert abc123' \
  'git am patch.diff' \
  'git -C /tmp/other commit -m x' \
  'git --no-pager push' \
  'cd /tmp && git push' \
  'ls | git commit' \
  'x=$(git push)' \
  'GIT_SSH_COMMAND=ssh git push' \
  'GIT_SSH_COMMAND="ssh -i /tmp/key" git push' \
  'echo one
git push'; do
  assert_bash deny "$JJ_CWD" "$mutation"
done

# A shell reserved word introduces a command, so git after one is git at command position. These are
# not exotic: a conditional commit and a loop that pushes per item are what an agent actually writes,
# and a matcher that only anchored on the start of a segment missed every one of them.
for compound in \
  'if [ -n "$x" ]; then git push; fi' \
  'if ! git diff --quiet; then git commit -m wip; fi' \
  'for f in a b; do git commit -m "$f"; done' \
  'while read -r l; do git push; done <list' \
  '! git push'; do
  assert_bash deny "$JJ_CWD" "$compound"
done

assert_bash deny "$JJ_CWD" 'git worktree add ../iso'

for branch_mutation in \
  'git branch -d old' \
  'git branch -D old' \
  'git branch --delete old' \
  'git branch -m old new' \
  'git branch -M old new' \
  'git branch --move old new' \
  'git branch new-thing'; do
  assert_bash deny "$JJ_CWD" "$branch_mutation"
done

# The other half of that boundary. `git branch` given nothing but flags lists, and listing is a
# read; given an operand it creates a ref jj would import as a bookmark it did not make, which is
# the same "mutate state jj expects to own" as the row above. That distinction is the only thing
# separating the two, so without these a matcher that took every `git branch` — or one that took
# none — would satisfy the whole block above.
for branch_read in \
  'git branch' \
  'git branch --list' \
  'git branch -a' \
  'git branch -vv'; do
  assert_bash allow "$JJ_CWD" "$branch_read"
done

# Each denial names the jj command it is steering toward, because a denial that does not say what to
# do instead is a denial an agent retries. The four the ticket added are pinned the same way the
# three that predate it are.
assert_reason 'jj workspace add' "$JJ_CWD" 'git worktree add ../iso'
assert_reason 'jj bookmark delete' "$JJ_CWD" 'git branch -D old'
assert_reason 'jj describe' "$JJ_CWD" 'git commit -m wip'
assert_reason 'jj abandon' "$JJ_CWD" 'git clean -fd'
assert_reason 'jj new' "$JJ_CWD" 'git stash'
assert_reason 'jj edit' "$JJ_CWD" 'git checkout -b feature'
assert_reason 'jj restore' "$JJ_CWD" 'git restore .'

# `git clean` is denied for a reason no other verb here shares, and the message has to carry it or
# the agent reads "use jj" and reaches for `rm -rf` next.
assert_reason 'untracked files into the working-copy commit' "$JJ_CWD" 'git clean -fd'

# The catch-all names the subcommand it did not recognise. A default-deny whose message is the same
# for everything tells an agent it is blocked but not what it is blocked on, and this is the one
# message no author will have thought about the specific case for.
assert_reason "'git gc'" "$JJ_CWD" 'git gc --prune=now'
assert_reason "'git this-subcommand-does-not-exist'" "$JJ_CWD" 'git this-subcommand-does-not-exist'

# The whole point of the rule: git is only steered where jj owns the working copy, and a mutation
# is a mutation. Read-only git is how an agent reads the repo it is standing in, and `gh` is how the
# work lands — `gh pr merge` names a mutation this hook denies through a route it permits, which is
# what makes it the gh spelling worth pinning rather than one with no `git` in it to get wrong.
#
# Default-deny is only affordable if the reads it keeps are actually kept, so **every entry in the
# hook's GIT_READ is driven here, and nothing is in GIT_READ that is not driven here**. An
# allow-list entry no assertion exercises is a hole that would ship green, which is the failure this
# suite exists to prevent, pointed at the list rather than at the matcher.
for allowed in \
  'git status' \
  'git log --oneline -5' \
  'git diff HEAD' \
  'git show abc123' \
  'git show-ref --heads' \
  'git blame src/x.ts' \
  'git grep -n needle' \
  'git shortlog -sn' \
  'git describe --tags' \
  'git version' \
  'git ls-files' \
  'git ls-tree -r HEAD' \
  'git ls-remote --heads origin' \
  'git cat-file -p HEAD' \
  'git rev-parse --show-toplevel' \
  'git rev-list --count HEAD' \
  'git merge-base main HEAD' \
  'git for-each-ref --format="%(refname)"' \
  'git diff-tree --no-commit-id --name-only -r HEAD' \
  'git check-ignore -v target' \
  'gh pr merge 12 --squash' \
  'jj git push --bookmark feature'; do
  assert_bash allow "$JJ_CWD" "$allowed"
done

# `git help commit` names a denied verb in an argument, so it also pins that the read is decided by
# the subcommand at command position and not by a verb appearing anywhere in the segment.
assert_bash allow "$JJ_CWD" 'git help commit'

# Subcommands that read in one spelling and write in another. The read spelling has to survive, or
# default-deny costs more than it is worth; the write spelling is denied above. `git stash list` in
# particular: `git stash` is denied by a matcher broad enough to take every spelling, so its own
# read form is the thing most likely to have been taken with it.
#
# Each of these is carried by exactly one of the hook's two lists. `git config --list` and
# `git remote -v` were briefly on both, which made them vacuous — either entry could be deleted and
# they stayed green, so they pinned neither.
for mode_switching_read in \
  'git stash list' \
  'git stash show' \
  'git config --get remote.origin.url' \
  'git config --list' \
  'git remote -v' \
  'git remote show origin' \
  'git worktree list' \
  'git reflog show' \
  'git reflog' \
  'git tag' \
  'git tag --list'; do
  assert_bash allow "$JJ_CWD" "$mode_switching_read"
done

# A read that is redirected or trailed by a comment is still a read. The flags-only rule anchors on
# the end of the segment, so without saying so it would read `> /tmp/out` as the operand that makes
# `git branch` a write — denying a listing for the file it was being written into. `main` allowed
# these, so getting this wrong is a regression rather than a new restriction. `|` needs no such
# handling: it is a separator, so it has already ended the segment.
for redirected_read in \
  'git branch -a > /tmp/out' \
  'git branch -a 2>/dev/null' \
  'git branch -a # list them all' \
  'git tag --list > /tmp/tags' \
  'git config --list >/tmp/cfg' \
  'git branch -a | head -5'; do
  assert_bash allow "$JJ_CWD" "$redirected_read"
done

# ...and the redirect does not become a way to smuggle an operand past the flags-only rule.
for redirected_write in \
  'git branch new-thing > /tmp/out' \
  'git tag v1.0.0 2>/dev/null' \
  'git branch -D old # tidy up'; do
  assert_bash deny "$JJ_CWD" "$redirected_write"
done

# The false positive, which is the half of this that cost real work. The old matcher took `git`
# after any non-word character, so every one of these was denied: the ticket that filed the bug was
# blocked by the bug, because its own text quotes the strings below.
#
# Each mention is written with a space after the mutation, which is the only spelling the matcher
# this replaced ever caught: it wanted whitespace or end-of-line after the subcommand, so
# `'git commit'` slipped through on its own closing quote and proved nothing. A fixture that passes
# for the reason the bug failed to fire is a fixture that would pass with the bug still in.
for mention in \
  'gh issue comment 17 --body "the hook denied git push and the body went to a file"' \
  'gh pr create --title "fix: stop denying git commit in prose"' \
  "rg -n 'git reset --hard here' docs/" \
  'grep -rn "git rebase -i" README.md' \
  'echo "never git merge in a jj repo"' \
  'cat notes.md # git commit is mentioned here' \
  '# git push is what this line is about' \
  'sed -i "" "s/git commit -m/jj commit -m/" README.md' \
  'gh issue create --title "hook allows git clean -fd and fails open without jq"' \
  'gh issue comment 57 --body "git stash moves work somewhere jj will not look for it"' \
  "rg -n 'git checkout -b ' hooks/" \
  'echo "git restore . overwrites what jj snapshotted"'; do
  assert_bash allow "$JJ_CWD" "$mention"
done

# A command substitution is data that becomes a command again, so the one quoted string that must
# still be denied is the one that runs.
assert_bash deny "$JJ_CWD" 'echo "$(git push)"'

# Contract, not coverage. #17 scoped this hook to the command position: a mutation handed to another
# command as an argument is not interpreted, because another program's arguments have no closed set
# to them and this hook guards the accident rather than the adversary. Default-deny does not widen
# that — `git clean` reaches the matcher through `sudo` exactly as `git push` always did — and the
# scope is easier to argue with than to notice, so it is pinned rather than left to be rediscovered
# as a hole. If this row ever has to flip, it should flip because someone decided it, in a ticket.
assert_bash allow "$JJ_CWD" 'sudo git clean -fd'

# Every repo that is not this one. The hook has no opinion there, and a hook with an opinion
# everywhere is a hook that gets turned off.
for anywhere in 'git commit -m real' 'git push' 'git worktree add ../x' 'git clean -fd' 'git stash' \
  'git checkout -b feature' 'git restore .' 'git gc --prune=now'; do
  assert_bash allow "$GIT_REPO" "$anywhere"
done

agent_response() {
  local cwd=$1 isolation=$2
  if [ -n "$isolation" ]; then
    jq -n --arg cwd "$cwd" --arg isolation "$isolation" \
      '{tool_name:"Agent",cwd:$cwd,tool_input:{prompt:"review the diff",isolation:$isolation}}'
  else
    jq -n --arg cwd "$cwd" \
      '{tool_name:"Agent",cwd:$cwd,tool_input:{prompt:"review the diff"}}'
  fi | "$HOOK"
}

# The hole. `Agent(isolation:"worktree")` cuts a git worktree through neither Bash nor
# EnterWorktree, so the two tools the matcher watched never saw it, and an agent fanning out
# worktree-isolated subagents in a jj repo did exactly what the rule forbids with nothing said.
worktree_agent=$(agent_response "$JJ_CWD" worktree)

if [ "$(decision_of "$worktree_agent")" = deny ]; then
  pass "deny: Agent with isolation worktree"
else
  fail "deny: Agent with isolation worktree"
fi

# A denial that does not say what to do instead is a denial an agent retries. The rule it is
# enforcing has a name, and the message has to carry it.
case "$(reason_of "$worktree_agent")" in
*"jj workspace add"*)
  pass "the worktree Agent denial names jj workspace add"
  ;;
*)
  fail "the worktree Agent denial names jj workspace add"
  ;;
esac

# Isolation is a parameter, not the tool: subagents are how the work gets done, and denying Agent
# outright would deny the harness its own reviewers.
for benign in '' none remote; do
  if [ "$(decision_of "$(agent_response "$JJ_CWD" "$benign")")" = allow ]; then
    pass "allow: Agent with isolation '${benign:-unset}'"
  else
    fail "allow: Agent with isolation '${benign:-unset}'"
  fi
done

if [ "$(decision_of "$(agent_response "$GIT_REPO" worktree)")" = allow ]; then
  pass "allow: Agent with isolation worktree outside a jj repo"
else
  fail "allow: Agent with isolation worktree outside a jj repo"
fi

enter_worktree_response() {
  jq -n --arg cwd "$1" '{tool_name:"EnterWorktree",cwd:$cwd,tool_input:{}}' | "$HOOK"
}

enter_worktree=$(enter_worktree_response "$JJ_CWD")

if [ "$(decision_of "$enter_worktree")" = deny ]; then
  pass "deny: EnterWorktree"
else
  fail "deny: EnterWorktree"
fi

if [ "$(decision_of "$(enter_worktree_response "$GIT_REPO")")" = allow ]; then
  pass "allow: EnterWorktree outside a jj repo"
else
  fail "allow: EnterWorktree outside a jj repo"
fi

case "$(reason_of "$enter_worktree")" in
*"jj workspace add"*)
  pass "the EnterWorktree denial names jj workspace add"
  ;;
*)
  fail "the EnterWorktree denial names jj workspace add"
  ;;
esac

# The hook runs on every tool call of every session, so a payload it has no opinion about has to be
# a pass and not a stack trace: Claude Code reads a non-zero PreToolUse exit as a block, which would
# turn a bad payload into a tool that stops working everywhere.
# Run from inside the jj repo and with no `cwd` in the payload, which pins two things at once. The
# hook falls back to $PWD when the payload carries no cwd, and that fallback is otherwise never
# driven; and without it these fixtures would prove nothing wherever the suite's own checkout is not
# a jj repo — they would exit at the `.jj` walk before reaching any of the code they are about. That
# is true of the Linux sandbox this suite also runs in, so it would pass there for the wrong reason.
#
# Asserting `allow` and not merely exit 0: deny() exits 0 too, so an exit status cannot tell the two
# apart, and a hook that denied everything it could not parse — bricking every tool call in every
# session — would satisfy a status check.
# Both halves, because each alone passes for a hook that is broken in the other way. Claude Code
# reads a non-zero PreToolUse exit as a block, so a crash is a denial with no message: an exit-status
# check alone would miss a hook that denied cleanly (deny() exits 0 too), and a decision check alone
# would read a crash's silence as an allow.
assert_survives() {
  local label=$1 payload=$2 out status
  out=$(cd "$JJ_CWD" && printf '%s' "$payload" | "$HOOK" 2>/dev/null)
  status=$?
  if [ "$status" -eq 0 ] && [ "$(decision_of "$out")" = allow ]; then
    pass "a payload it has no opinion about is allowed: $label"
  else
    fail "a payload it has no opinion about is allowed: $label (exit $status, $(decision_of "$out"))"
  fi
}

# A PATH with everything the hook runs except jq. Not an empty PATH: the hook shells out to cat,
# dirname, grep, sed and tr, and `#!/usr/bin/env bash` needs to find bash, so a PATH with nothing in
# it would prove the hook denies when it cannot run *at all* — which every broken hook does — rather
# than that it denies on this one missing dependency. Only the hook's PATH is reduced; the suite
# keeps its own jq to read the decision back out.
NOJQ_PATH=$(mktemp -d)
trap 'rm -rf -- "$JJ_REPO" "$GIT_REPO" "$NOJQ_PATH"' EXIT
for binary in bash cat dirname grep sed tr; do
  ln -s "$(command -v "$binary")" "$NOJQ_PATH/$binary"
done

if [ -n "$(PATH="$NOJQ_PATH" command -v jq 2>/dev/null)" ]; then
  fail 'the no-jq PATH really has no jq'
else
  pass 'the no-jq PATH really has no jq'
fi

# The reduced PATH is only a jq test if the hook still works on it, otherwise every assertion below
# passes for a hook that crashed on a missing `tr`.
nojq_response() {
  (cd "$1" && printf '%s' "$2" | env PATH="$NOJQ_PATH" "$HOOK" 2>/dev/null)
}

# Without jq the hook cannot read the payload, so it cannot tell a mutation from a read — and the
# whole point of the ticket is that the answer to that is a refusal, not a shrug. Fail-open here was
# not a degraded guard, it was no guard, reached silently and with no diagnostic.
#
# The command is read-only on purpose: it is the one the hook allows when it can see it, so a hook
# that denied it for the *matcher's* reason rather than for jq's would be indistinguishable from the
# fix. Nothing in the payload can be seen at all, which is exactly why it has to deny.
nojq_deny=$(nojq_response "$JJ_CWD" '{"tool_name":"Bash","cwd":"'"$JJ_CWD"'","tool_input":{"command":"git status"}}')

if [ "$(decision_of "$nojq_deny")" = deny ]; then
  pass 'deny: a missing jq fails closed rather than waving the payload through'
else
  fail 'deny: a missing jq fails closed rather than waving the payload through'
fi

# The deny JSON is built by the hook itself here, not by jq, so it is worth checking it is JSON a
# consumer can read and not a printf that lost a quote — this is the one response on the only path
# where jq cannot be asked to format it.
case "$(reason_of "$nojq_deny")" in
*jq*)
  pass 'the no-jq denial says jq is why it refused'
  ;;
*)
  fail 'the no-jq denial says jq is why it refused'
  ;;
esac

# Scoped to the repos this hook has an opinion in. A missing jq denying every Bash call everywhere
# would make one absent binary brick every session on the machine, including the `brew install jq`
# that fixes it — the guard has to fail closed where it guards and stay out of the way elsewhere.
if [ "$(decision_of "$(nojq_response "$GIT_REPO" '{"tool_name":"Bash","tool_input":{"command":"git push"}}')")" = allow ]; then
  pass "allow: a missing jq outside a jj repo is still none of this hook's business"
else
  fail "allow: a missing jq outside a jj repo is still none of this hook's business"
fi

assert_survives 'not JSON' 'not json at all'
assert_survives 'a tool with no command' \
  '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
assert_survives 'Bash with no command' '{"tool_name":"Bash","tool_input":{}}'
assert_survives 'an empty object' '{}'

if [ "$failures" -eq 0 ]; then
  echo "enforce-jj: all assertions passed"
else
  printf 'enforce-jj: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
