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
  'GIT_SSH_COMMAND=ssh git push' \
  'echo one
git push'; do
  assert_bash deny "$JJ_CWD" "$mutation"
done

assert_bash deny "$JJ_CWD" 'git worktree add ../iso'
assert_bash deny "$JJ_CWD" 'git branch -D old'
assert_bash deny "$JJ_CWD" 'git branch --delete old'

# The whole point of the rule: git is only steered where jj owns the working copy, and a mutation
# is a mutation. Read-only git is how an agent reads the repo it is standing in.
for allowed in \
  'git status' \
  'git log --oneline -5' \
  'git diff HEAD' \
  'git show abc123' \
  'gh pr create --fill' \
  'jj git push --bookmark feature' \
  'jj git fetch' \
  'jj commit -m wip'; do
  assert_bash allow "$JJ_CWD" "$allowed"
done

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

enter_worktree=$(jq -n --arg cwd "$JJ_CWD" \
  '{tool_name:"EnterWorktree",cwd:$cwd,tool_input:{}}' | "$HOOK")

if [ "$(decision_of "$enter_worktree")" = deny ]; then
  pass "deny: EnterWorktree"
else
  fail "deny: EnterWorktree"
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
for odd in 'not json at all' \
  '{"tool_name":"Read","cwd":"'"$JJ_CWD"'","tool_input":{"file_path":"/tmp/x"}}' \
  '{"tool_name":"Bash","cwd":"'"$JJ_CWD"'","tool_input":{}}'; do
  if printf '%s' "$odd" | "$HOOK" >/dev/null 2>&1; then
    pass "a payload it has no opinion about exits 0: $odd"
  else
    fail "a payload it has no opinion about exits 0: $odd"
  fi
done

if [ "$failures" -eq 0 ]; then
  echo "enforce-jj: all assertions passed"
else
  printf 'enforce-jj: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
