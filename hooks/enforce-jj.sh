#!/usr/bin/env bash
# PreToolUse guard: in jujutsu-colocated repos, steer agents off git mutations and off git worktree
# isolation, toward the jj equivalents. Read-only git, gh, and all git in non-jj repos pass through.
#
# This is the only rule the harness enforces rather than asks for. CLAUDE.md and ~/.claude/rules
# are not inherited by subagents, so every rule written there reaches a main loop and stops at the
# first delegation boundary; a PreToolUse hook fires for every agent at every depth. Installed and
# wired by install.sh — see the hooks note there for why one copy serves every profile.
set -uo pipefail

input=$(cat)

NOTE="This is a jujutsu (jj) repo; use jj, not git, for version control."

WORKSPACE="Isolate with 'jj workspace add <path>' instead (work there, then 'jj workspace forget \
<name>' and remove the dir when done). A git worktree isolates files but not jj's working copy: jj \
run from inside one still operates on the default workspace, so concurrent agents collide on one \
'@' and snapshots bleed between them."

# Enforce only inside a jj repo: walk up looking for a .jj directory.
in_jj_repo() {
  local dir=$1
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -d "$dir/.jj" ]; then
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# jq parses the payload, so without it this hook cannot tell a mutation from a read — and a guard
# that cannot tell refuses rather than waving everything through. Fail-open here is not a degraded
# guard, it is no guard, arrived at silently: the first sign would be the damage. It is also the
# whole harness's blind spot at once, since hooks are the only rule that reaches subagents.
#
# install.sh checks for jq too, but that is a different machine at a different time — the hook's
# runtime PATH is not the installer's, and a hook reaches machines that never ran the installer.
#
# Scoped to jj repos, the only place this hook has an opinion at all, so one absent binary cannot
# brick every session on the machine — including the `brew install jq` that would fix it. The cwd
# has to come from $PWD here, since reading it out of the payload is the thing that needs jq.
#
# The one response this hook builds without jq, because jq is what is missing. printf and not
# jq means the reason is escaped by hand, so it is a constant with no quote or backslash in it
# rather than an argument — deny() above stays the way every other message is built.
NO_JQ_REASON="$NOTE This hook needs jq to read the PreToolUse payload, and jq is not on PATH. It \
cannot tell a git mutation from a read, so it is refusing rather than letting one through unseen. \
Install jq (brew install jq, apt-get install jq) and retry."

if ! command -v jq >/dev/null 2>&1; then
  in_jj_repo "$PWD" || exit 0
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$NO_JQ_REASON"
  exit 0
fi

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$cwd" ] || cwd=$PWD

in_jj_repo "$cwd" || exit 0

# EnterWorktree: isolate with a jj workspace instead of a git worktree.
if [ "$tool" = "EnterWorktree" ]; then
  deny "$NOTE Don't make a git worktree. $WORKSPACE"
fi

# The Agent tool's `isolation` parameter makes a git worktree through neither Bash nor
# EnterWorktree, so a hook watching those two never sees it and an agent fanning out
# worktree-isolated subagents does exactly what the workspace rule forbids, silently.
if [ "$tool" = "Agent" ]; then
  isolation=$(printf '%s' "$input" | jq -r '.tool_input.isolation // empty' 2>/dev/null || true)
  if [ "$isolation" = "worktree" ]; then
    deny "$NOTE Don't spawn a worktree-isolated subagent. $WORKSPACE"
  fi
  exit 0
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$cmd" ] || exit 0

# A shell starts a command at the start of the text and after each of these separators, and nowhere
# else. Splitting on them puts every command at the start of its own segment, which is what lets the
# matcher below anchor and so tell an invocation from a mention. `$(` and a backtick open a command
# too, and each is split by a character of its own, so `"$(git push)"` still lands at a start.
#
# Everything a shell treats as data carries no separator, so the `git` inside it never reaches the
# start of a segment: a quoted body, a `#` comment, a `--body "..."` that quotes the very string it
# is reporting. That is the bug this replaced. The old matcher took `git` after any non-word
# character, so it denied `grep -rn 'git reset --hard' docs/`, denied the probe that found the Agent
# hole above, and denied the `gh issue edit` that filed the ticket for both, because the ticket text
# quotes the string. It could not tell an invocation from a mention.
#
# A newline is a separator too and is not in the set below, because grep already reads a line at a
# time: mapping it to itself would only look load-bearing. That is also the one shape data still
# reaches a start through — a line of a heredoc or a multi-line string that itself begins with
# `git <mutation>` — and it has to stay that way, since a multi-line Bash command is ordinary and
# its second line is a real command. Write such a body to a file and pass the path.
#
# jj's own subcommands need no special handling: `jj git push` starts with `jj`, so `git` is not at
# the start of the segment and never matches. The matcher this replaced needed a substitution to
# rewrite them out of the way first, which is the same thing it needed to tell prose from a command
# and never had.
segments=$(printf '%s' "$cmd" | tr ';&|(){}`' '\n')

# What a shell allows between a start and the command's own name, and nothing else. Two closed sets,
# both POSIX's rather than a list of things noticed one at a time:
#
#   - reserved words that introduce a command. `if [ -n "$x" ]; then git push; fi` and
#     `for f in a b; do git commit -m "$f"; done` are ordinary spellings, and a matcher that missed
#     them would be missing the shape an agent actually reaches for.
#   - variable assignments, whose value may be quoted: `GIT_SSH_COMMAND="ssh -i key" git push` is
#     the spelling that variable is normally given, and an unquoted-only rule would catch only the
#     one nobody types.
#
# What is deliberately not here: a command handed to *another command* as an argument
# (`sudo git push`, `xargs git commit`, `bash -c '...'`, `eval git push`). Interpreting another
# program's arguments has no closed set to it, and this hook guards the accident, not the
# adversary — `g=git; $g push` was always through too. The enforcement that matters is that the
# obvious spelling steers to jj.
KEYWORD='((!|then|else|elif|do|if|while|until)[[:space:]]+)*'
ASSIGN='([A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]*)[[:space:]]+)*'

# `git`, optionally with global flags, then the target subcommand.
GIT="^[[:space:]]*${KEYWORD}${ASSIGN}git([[:space:]]+(-[A-Za-z]+|--[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?|-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+))*[[:space:]]+"

if printf '%s' "$segments" | grep -Eq "${GIT}worktree[[:space:]]+add([[:space:]]|\$)"; then
  deny "$NOTE Don't make a git worktree. $WORKSPACE"
fi

if printf '%s' "$segments" | grep -Eq "${GIT}(commit|push|rebase|merge|reset|cherry-pick|revert|am)([[:space:]]|\$)"; then
  deny "$NOTE Use jj: jj describe / jj commit, jj git push, jj rebase, jj squash, jj new / jj edit, jj bookmark. Read-only git (status/log/diff/show) and gh stay allowed. If the user explicitly asked for git here, tell them it is blocked so they can lift it."
fi

if printf '%s' "$segments" | grep -Eq "${GIT}branch[[:space:]]+(-d|-D|-m|-M|--delete|--move)([[:space:]]|\$)"; then
  deny "$NOTE Use 'jj bookmark delete/move/set' instead of 'git branch -d/-D/-m'."
fi

exit 0
