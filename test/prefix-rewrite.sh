#!/usr/bin/env bash
# shellcheck disable=SC2016 # the fixture and its assertions are markdown, backticks and all
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

. "$HARNESS_SOURCE/vendor-matt-skills.sh"
set +e # the script it just sourced runs under `set -e`; this file collects failures instead

failures=0

pass() { printf 'ok   %s\n' "$1"; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_contains() {
  if grep -qF -- "$2" "$fixture/SKILL.md"; then pass "$1"; else fail "$1"; fi
}

fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

cat >"$fixture/SKILL.md" <<'EOF'
---
name: implement
description: Build a thing. Hand off to /code-review when done.
---

Use `/tdd` where possible, then use /code-review to review the work.
Run `/compact` when the context fills up.
Route each issue through `/triage` first.
The handler lives in src/triage/handler.ts, per `docs/agents/triage-labels.md`.
The throwaway route under `/prototype/<name>` mounts the same switcher.
EOF

apply_prefix_to_references "$fixture"

assert_contains "a backticked reference is prefixed" '`/matt-tdd`'
assert_contains "a bare reference is prefixed" 'use /matt-code-review to review'
assert_contains "a reference in the frontmatter description is prefixed" \
  'Hand off to /matt-code-review when done'
assert_contains "a reference whose name also appears in paths is prefixed" '`/matt-triage` first'

assert_contains "a built-in Claude Code command is left alone" 'Run `/compact` when'
assert_contains "a path ending in a skill name is left alone" 'src/triage/handler.ts'
assert_contains "a backticked path is left alone" '`docs/agents/triage-labels.md`'
assert_contains "a route starting with a skill name is left alone" '`/prototype/<name>`'

if [ "$failures" -eq 0 ]; then
  echo "prefix-rewrite: all assertions passed"
else
  printf 'prefix-rewrite: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
