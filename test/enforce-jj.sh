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
  'git branch --move old new'; do
  assert_bash deny "$JJ_CWD" "$branch_mutation"
done

# The other half of that boundary: `git branch` without one of those flags lists or creates, which
# is not a mutation of anything jj owns. Without this, a matcher that took every `git branch` would
# satisfy every assertion above.
assert_bash allow "$JJ_CWD" 'git branch new-thing'

assert_reason 'jj workspace add' "$JJ_CWD" 'git worktree add ../iso'
assert_reason 'jj bookmark delete' "$JJ_CWD" 'git branch -D old'
assert_reason 'jj describe' "$JJ_CWD" 'git commit -m wip'

# The whole point of the rule: git is only steered where jj owns the working copy, and a mutation
# is a mutation. Read-only git is how an agent reads the repo it is standing in, and `gh` is how the
# work lands — `gh pr merge` names a mutation this hook denies through a route it permits, which is
# what makes it the gh spelling worth pinning rather than one with no `git` in it to get wrong.
for allowed in \
  'git status' \
  'git log --oneline -5' \
  'git diff HEAD' \
  'git show abc123' \
  'gh pr merge 12 --squash' \
  'jj git push --bookmark feature'; do
  assert_bash allow "$JJ_CWD" "$allowed"
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
  'sed -i "" "s/git commit -m/jj commit -m/" README.md'; do
  assert_bash allow "$JJ_CWD" "$mention"
done

# A command substitution is data that becomes a command again, so the one quoted string that must
# still be denied is the one that runs.
assert_bash deny "$JJ_CWD" 'echo "$(git push)"'

# Every repo that is not this one. The hook has no opinion there, and a hook with an opinion
# everywhere is a hook that gets turned off.
for anywhere in 'git commit -m real' 'git push' 'git worktree add ../x'; do
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
