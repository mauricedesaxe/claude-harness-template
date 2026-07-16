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

lockfile_skills() {
  awk -F'"' '/^    "/ && /: \{$/ { print $2 }' "$HARNESS_SOURCE/skills-lock.json"
}

frontmatter_of() {
  awk 'NR > 1 && /^---$/ { exit } NR > 1' "$1"
}

body_of() {
  awk 'past { print } !past && NR > 1 && /^---$/ { past = 1 }' "$1"
}

# Empty for a rule Claude Code loads unconditionally, non-empty for one that scopes itself.
rule_paths() {
  [ "$(head -n 1 -- "$1")" = "---" ] || return 0
  frontmatter_of "$1" | grep '^paths:'
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

assert_same_file "the spine installs as a Claude Code rule" \
  "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$claude/rules/PHILOSOPHY.md"
assert_same_file "the spine installs as an OpenCode rule" \
  "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$opencode/rules/PHILOSOPHY.md"

if [ -n "$(rule_paths "$claude/rules/PHILOSOPHY.md")" ]; then
  fail "the spine carries no paths:, so it loads in every repo"
else
  pass "the spine carries no paths:, so it loads in every repo"
fi

missing_packs=""
unscoped_packs=""
for pack in "$HARNESS_SOURCE"/docs/packs/*.md; do
  pack_name=$(basename -- "$pack")
  for root in "$claude" "$opencode"; do
    installed="$root/rules/packs/$pack_name"
    if [ -f "$installed" ]; then
      cmp -s -- "$pack" "$installed" || missing_packs="$missing_packs $installed(differs)"
    else
      missing_packs="$missing_packs $installed"
    fi
  done
  [ -n "$(rule_paths "$claude/rules/packs/$pack_name")" ] ||
    unscoped_packs="$unscoped_packs $pack_name"
done

if [ -z "$missing_packs" ]; then
  pass "every pack installs to both runtimes"
else
  fail "every pack installs to both runtimes:$missing_packs"
fi

# Only Claude Code acts on `paths:`; OpenCode gets the same bytes and loads them unconditionally.
if [ -z "$unscoped_packs" ]; then
  pass "every pack carries paths:, so Claude Code applies it by paradigm"
else
  fail "every pack carries paths:, so Claude Code applies it by paradigm:$unscoped_packs"
fi

assert_contains "opencode.json instructions point at the spine" \
  '~/.config/opencode/rules/PHILOSOPHY.md' "$opencode/opencode.json"
assert_contains "opencode.json instructions point at the packs" \
  '~/.config/opencode/rules/packs/*.md' "$opencode/opencode.json"

assert_same_file "lazar-tldraw installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/SKILL.md" "$claude/skills/lazar-tldraw/SKILL.md"
assert_same_file "lazar-tldraw installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/SKILL.md" "$opencode/skills/lazar-tldraw/SKILL.md"
assert_same_file "a skill's supporting files travel with it" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/LICENSE" "$claude/skills/lazar-tldraw/LICENSE"

pinned=$(lockfile_skills)
if [ "$(printf '%s\n' "$pinned" | grep -c .)" -eq 22 ]; then
  pass "skills-lock.json pins Matt's 22 skills"
else
  fail "skills-lock.json pins Matt's 22 skills"
fi

missing=""
misnamed=""
unprefixed=""
while IFS= read -r name; do
  for root in "$claude" "$opencode"; do
    skill_md="$root/skills/matt-$name/SKILL.md"
    if [ -f "$skill_md" ]; then
      grep -qx "name: matt-$name" "$skill_md" || misnamed="$misnamed $skill_md"
    else
      missing="$missing $skill_md"
    fi
    [ -e "$root/skills/$name" ] && unprefixed="$unprefixed $root/skills/$name"
  done
done <<<"$pinned"

if [ -z "$missing" ]; then
  pass "every pinned Matt skill installs to both runtimes"
else
  fail "every pinned Matt skill installs to both runtimes:$missing"
fi

if [ -z "$misnamed" ]; then
  pass "every installed Matt skill declares its matt- name"
else
  fail "every installed Matt skill declares its matt- name:$misnamed"
fi

if [ -z "$unprefixed" ]; then
  pass "no Matt skill installs under its upstream name, which would eat a built-in"
else
  fail "no Matt skill installs under its upstream name:$unprefixed"
fi

# A body that still says `/code-review` dispatches to Claude Code's built-in, so the prefix has
# to hold across the cross-references too, not just the directory and the frontmatter.
reference='[ `]/('"$(printf '%s' "$pinned" | paste -sd '|' -)"')([^A-Za-z0-9/-]|$)'
dangling=""
for root in "$claude" "$opencode"; do
  dangling="$dangling $(grep -rlE "$reference" "$root/skills"/matt-*/)"
done

if [ -z "${dangling// /}" ]; then
  pass "no installed Matt skill dispatches to an unprefixed name"
else
  fail "no installed Matt skill dispatches to an unprefixed name:$dangling"
fi

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
touch "$claude/rules/packs/stale-pack.md"
jq '.model = "anthropic/claude-opus-4-5"
  | .instructions += ["~/notes/house-style.md", "~/.config/opencode/rules/OLD-SPINE.md"]' \
  "$opencode/opencode.json" >"$opencode/opencode.json.seeded"
mv "$opencode/opencode.json.seeded" "$opencode/opencode.json"

HOME="$TEST_HOME" "$HARNESS_SOURCE/install.sh" >/dev/null || fail "installing twice is safe"

if [ -e "$claude/skills/lazar-tldraw/STALE.md" ]; then
  fail "reinstalling purges a file the source no longer carries"
else
  pass "reinstalling purges a file the source no longer carries"
fi

if [ -e "$claude/rules/packs/stale-pack.md" ]; then
  fail "reinstalling purges a pack the source no longer carries"
else
  pass "reinstalling purges a pack the source no longer carries"
fi

harness_entries=$(jq '[.instructions[] | select(startswith("~/.config/opencode/rules/"))] | length' \
  "$opencode/opencode.json")
if [ "$harness_entries" -eq 2 ]; then
  pass "reinstalling does not duplicate the harness instructions"
else
  fail "reinstalling does not duplicate the harness instructions: got $harness_entries entries"
fi

if grep -qF -- '~/.config/opencode/rules/OLD-SPINE.md' "$opencode/opencode.json"; then
  fail "reinstalling drops a harness instructions entry the source no longer carries"
else
  pass "reinstalling drops a harness instructions entry the source no longer carries"
fi

assert_contains "reinstalling keeps an instructions entry the user added" \
  '~/notes/house-style.md' "$opencode/opencode.json"
assert_contains "reinstalling keeps unrelated opencode.json keys" \
  'anthropic/claude-opus-4-5' "$opencode/opencode.json"

if [ "$failures" -eq 0 ]; then
  echo "install-smoke: all assertions passed"
else
  printf 'install-smoke: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
