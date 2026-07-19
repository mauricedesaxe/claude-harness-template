#!/usr/bin/env bash
# Upstream ships most of its skills with `disable-model-invocation: true`, which makes them
# reachable only by a hand-typed slash command. The vendor strips it so the agent can route from a
# spoken brain-dump. These assertions pin that the strip is precise: it takes the whole line, only
# inside the frontmatter, and touches nothing else.
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

. "$HARNESS_SOURCE/vendor-skills.sh"
set +e # the script it just sourced runs under `set -e`; this file collects failures instead

failures=0

pass() { printf 'ok   %s\n' "$1"; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

assert_absent() {
  if grep -qF -- "$2" "$fixture/SKILL.md"; then fail "$1"; else pass "$1"; fi
}

assert_contains() {
  if grep -qF -- "$2" "$fixture/SKILL.md"; then pass "$1"; else fail "$1"; fi
}

fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT

# --- the ordinary case: a locked skill, stripped -------------------------------------------

cat >"$fixture/SKILL.md" <<'EOF'
---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.
EOF

strip_model_invocation_lock "$fixture/SKILL.md"

assert_absent "the lock line is gone" "disable-model-invocation"
assert_contains "the name survives" "name: implement"
assert_contains "the description survives" 'description: "Implement a piece of work'
assert_contains "the body survives" "Implement the work described by the user"
if [ "$(head -1 "$fixture/SKILL.md")" = "---" ] &&
  [ "$(sed -n '4p' "$fixture/SKILL.md")" = "---" ]; then
  pass "the frontmatter still closes"
else
  fail "the frontmatter still closes"
fi

# --- an unlocked skill is left exactly as it was --------------------------------------------

cat >"$fixture/SKILL.md" <<'EOF'
---
name: tdd
description: Test-driven development.
---

Red, green, refactor.
EOF
cp -- "$fixture/SKILL.md" "$fixture/before"

strip_model_invocation_lock "$fixture/SKILL.md"

if cmp -s -- "$fixture/before" "$fixture/SKILL.md"; then
  pass "a skill without the lock is untouched"
else
  fail "a skill without the lock is untouched"
fi

# --- a body mentioning the key is not frontmatter, and must survive --------------------------
# The strip stops at the closing `---`, so a skill that documents the flag (writing-great-skills
# does exactly this) keeps its prose.

cat >"$fixture/SKILL.md" <<'EOF'
---
name: writing-great-skills
description: How to write a skill.
disable-model-invocation: true
---

Set `disable-model-invocation: true` when the skill should only run when asked for by name.
EOF

strip_model_invocation_lock "$fixture/SKILL.md"

assert_contains "prose documenting the flag survives" \
  'Set `disable-model-invocation: true` when the skill'
if [ "$(sed -n '/^---$/,/^---$/p' "$fixture/SKILL.md" | grep -c 'disable-model-invocation')" -eq 0 ]; then
  pass "the frontmatter copy is still gone"
else
  fail "the frontmatter copy is still gone"
fi

# --- a false value is left alone ------------------------------------------------------------
# Only `true` is a lock. Rewriting `false` would be an edit upstream did not ask for.

cat >"$fixture/SKILL.md" <<'EOF'
---
name: teach
disable-model-invocation: false
---

Body.
EOF

strip_model_invocation_lock "$fixture/SKILL.md"

assert_contains "an explicit false is preserved" "disable-model-invocation: false"

if [ "$failures" -eq 0 ]; then
  printf '\nall model-invocation assertions passed\n'
else
  printf '\n%d assertion(s) failed\n' "$failures" >&2
fi
exit $((failures > 0))
