#!/usr/bin/env bash
# PreToolUse guard: in jujutsu-colocated repos, steer agents off git mutations
# and git/EnterWorktree worktree creation toward jj equivalents. Read-only git,
# gh, and all git in non-jj repos pass through untouched.
#
# Wired in ~/.claude/settings.json as a PreToolUse hook on Bash|EnterWorktree.
set -uo pipefail

input=$(cat)

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$cwd" ] || cwd=$PWD

# Enforce only inside a jj repo: walk up from cwd looking for a .jj directory.
dir=$cwd
in_jj=0
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if [ -d "$dir/.jj" ]; then in_jj=1; break; fi
  dir=$(dirname "$dir")
done
[ "$in_jj" -eq 1 ] || exit 0

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

NOTE="This is a jujutsu (jj) repo; use jj, not git, for version control."

# EnterWorktree: isolate with a jj workspace instead of a git worktree.
if [ "$tool" = "EnterWorktree" ]; then
  deny "$NOTE Don't make a git worktree; isolate with 'jj workspace add <path>' (work there, then 'jj workspace forget <name>' and remove the dir when done). git worktrees do not isolate jj's working copy."
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -n "$cmd" ] || exit 0

# Neutralize jj's own subcommands ("jj git push/fetch/import/export/...") so the
# literal "git" inside them is not mistaken for a git invocation.
scan=$(printf '%s' "$cmd" | sed -E 's/(^|[^[:alnum:]_])jj[[:space:]]+git/\1jjgit/g')

# `git`, optionally with global flags, then the target subcommand.
GIT='(^|[^[:alnum:]_])git([[:space:]]+(-[A-Za-z]+|--[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?|-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+))*[[:space:]]+'

if printf '%s' "$scan" | grep -Eq "${GIT}worktree[[:space:]]+add([[:space:]]|\$)"; then
  deny "$NOTE Use 'jj workspace add <path>' instead of 'git worktree add' so the working copy is isolated for jj."
fi

if printf '%s' "$scan" | grep -Eq "${GIT}(commit|push|rebase|merge|reset|cherry-pick|revert|am)([[:space:]]|\$)"; then
  deny "$NOTE Use jj: jj describe / jj commit, jj git push, jj rebase, jj squash, jj new / jj edit, jj bookmark. Read-only git (status/log/diff/show) and gh stay allowed. If the user explicitly asked for git here, tell them it is blocked so they can lift it."
fi

if printf '%s' "$scan" | grep -Eq "${GIT}branch[[:space:]]+(-d|-D|-m|-M|--delete|--move)([[:space:]]|\$)"; then
  deny "$NOTE Use 'jj bookmark delete/move/set' instead of 'git branch -d/-D/-m'."
fi

exit 0
