#!/usr/bin/env bash
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'ok   %s\n' "$1"; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_same_file() {
  if cmp -s -- "$2" "$3"; then pass "$1"; else fail "$1"; fi
}

assert_contains() {
  if grep -qF -- "$2" "$3"; then pass "$1"; else fail "$1"; fi
}

frontmatter_of() {
  awk 'NR > 1 && /^---$/ { exit } NR > 1' "$1"
}

body_of() {
  awk 'past { print } !past && NR > 1 && /^---$/ { past = 1 }' "$1"
}

TEST_HOME=$(mktemp -d)
trap 'rm -rf -- "$TEST_HOME"' EXIT

HOME="$TEST_HOME" "$HARNESS_SOURCE/install.sh" >/dev/null || {
  echo "FAIL install.sh exited non-zero" >&2
  exit 1
}

claude="$TEST_HOME/.claude"
opencode="$TEST_HOME/.config/opencode"

assert_same_file "CLAUDE.md installs to Claude Code" \
  "$HARNESS_SOURCE/CLAUDE.md" "$claude/CLAUDE.md"
assert_same_file "CLAUDE.md installs to OpenCode as AGENTS.md" \
  "$HARNESS_SOURCE/CLAUDE.md" "$opencode/AGENTS.md"

assert_same_file "lazar-tldraw installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/SKILL.md" "$claude/skills/lazar-tldraw/SKILL.md"
assert_same_file "lazar-tldraw installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/SKILL.md" "$opencode/skills/lazar-tldraw/SKILL.md"
assert_same_file "a skill's supporting files travel with it" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/LICENSE" "$claude/skills/lazar-tldraw/LICENSE"

source_agent="$HARNESS_SOURCE/agents/clarity-reviewer.md"
claude_agent="$claude/agents/clarity-reviewer.md"
opencode_agent="$opencode/agents/clarity-reviewer.md"

assert_same_file "clarity-reviewer installs to Claude Code verbatim" \
  "$source_agent" "$claude_agent"

assert_contains "OpenCode agent declares mode: subagent" \
  "mode: subagent" "$opencode_agent"
assert_contains "OpenCode agent denies edit" "edit: deny" "$opencode_agent"
assert_contains "OpenCode agent keeps the authored description" \
  "$(grep -m1 '^description:' "$source_agent")" "$opencode_agent"
if frontmatter_of "$opencode_agent" | grep -q '^name:'; then
  fail "OpenCode agent drops Claude Code's name key"
else
  pass "OpenCode agent drops Claude Code's name key"
fi

if diff -q <(body_of "$source_agent") <(body_of "$opencode_agent") >/dev/null; then
  pass "the transform rewrites frontmatter and leaves the prompt alone"
else
  fail "the transform rewrites frontmatter and leaves the prompt alone"
fi

touch "$claude/skills/lazar-tldraw/STALE.md"
HOME="$TEST_HOME" "$HARNESS_SOURCE/install.sh" >/dev/null || fail "installing twice is safe"

if [ -e "$claude/skills/lazar-tldraw/STALE.md" ]; then
  fail "reinstalling purges a file the source no longer carries"
else
  pass "reinstalling purges a file the source no longer carries"
fi

if [ "$failures" -eq 0 ]; then
  echo "install-smoke: all assertions passed"
else
  printf 'install-smoke: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
