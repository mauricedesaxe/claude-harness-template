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
CANARY=$(mktemp -d)
trap 'rm -rf -- "$TEST_HOME" "$CANARY"' EXIT

# A run that escapes the sandbox lands in these decoys instead of the real harness this shell
# is configured with.
export CLAUDE_CONFIG_DIR="$CANARY/claude-config-dir"
export XDG_CONFIG_HOME="$CANARY/xdg-config-home"

for decoy in "$CLAUDE_CONFIG_DIR" "$XDG_CONFIG_HOME/opencode"; do
  mkdir -p -- "$decoy/skills" "$decoy/agents"
  printf 'a live harness lives here\n' >"$decoy/CLAUDE.md"
done

canary_digest() {
  find "$CANARY" | sort
  find "$CANARY" -type f -exec cksum {} + | sort
}

canary_before=$(canary_digest)

# An allowlist, not a blocklist: only HOME and PATH reach the installer, so a redirect variable
# added to install.sh later is neutralised without this test having to learn its name.
run_installer() {
  local home=$1
  shift
  env -i PATH="$PATH" HOME="$home" "$@" "$HARNESS_SOURCE/install.sh"
}

run_installer "$TEST_HOME" >/dev/null || {
  echo "FAIL install.sh exited non-zero" >&2
  exit 1
}

claude="$TEST_HOME/.claude"
opencode="$TEST_HOME/.config/opencode"

assert_same_file "CLAUDE.md installs to Claude Code" \
  "$HARNESS_SOURCE/CLAUDE.md" "$claude/CLAUDE.md"
assert_same_file "CLAUDE.md installs to OpenCode as AGENTS.md" \
  "$HARNESS_SOURCE/CLAUDE.md" "$opencode/AGENTS.md"

# Adherence drops as the file grows, and the smart zone is not there to be spent on rules. The
# budget only holds while the file points at the philosophy and the router instead of restating them.
if [ "$(wc -l <"$claude/CLAUDE.md")" -lt 200 ]; then
  pass "the installed CLAUDE.md stays under 200 lines"
else
  fail "the installed CLAUDE.md stays under 200 lines: $(wc -l <"$claude/CLAUDE.md")"
fi

# The skeleton this file grew out of shipped its TODOs to every install, which is what made the
# installer unrunnable against a real harness.
if grep -q 'TODO' "$claude/CLAUDE.md"; then
  fail "the installed CLAUDE.md carries no unfilled TODO"
else
  pass "the installed CLAUDE.md carries no unfilled TODO"
fi

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

assert_same_file "lazar-standup installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-standup/SKILL.md" "$claude/skills/lazar-standup/SKILL.md"
assert_same_file "lazar-standup installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-standup/SKILL.md" "$opencode/skills/lazar-standup/SKILL.md"

assert_same_file "lazar-research installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-research/SKILL.md" "$claude/skills/lazar-research/SKILL.md"
assert_same_file "lazar-research installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-research/SKILL.md" "$opencode/skills/lazar-research/SKILL.md"

assert_same_file "lazar-review installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-review/SKILL.md" "$claude/skills/lazar-review/SKILL.md"
assert_same_file "lazar-review installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-review/SKILL.md" "$opencode/skills/lazar-review/SKILL.md"

# lazar-review names the global agents rather than globbing an agents dir, so that it always
# spawns them even where a repo ships none. That only holds while the names it spawns are the
# names the harness ships.
unnamed=""
for agent in "$HARNESS_SOURCE"/agents/*.md; do
  grep -qF -- "$(basename -- "$agent" .md)" "$claude/skills/lazar-review/SKILL.md" ||
    unnamed="$unnamed $(basename -- "$agent" .md)"
done

if [ -z "$unnamed" ]; then
  pass "lazar-review's roster names every agent the harness ships"
else
  fail "lazar-review's roster names every agent the harness ships:$unnamed"
fi

# Both runtimes read the same instructions byte for byte (asserted above), so pinning the note
# path once pins it for both. Read the root back out of what was installed rather than restating
# it here, or the assertion just agrees with itself.
note_path=$(grep -m1 -E '^~/\S+/repos/<host>/<owner>/<repo>\.md$' "$claude/CLAUDE.md" || true)

if [ -n "$note_path" ]; then
  pass "Claude Code is told where the machine-local note lives"
else
  fail "Claude Code is told where the machine-local note lives"
fi

# Under ~/.claude or ~/.config/opencode the note would be owned by one runtime and invisible to
# the other, which is the failure it exists to avoid.
case "${note_path#\~/}" in
'' | .claude/* | .config/*)
  fail "the note path sits outside any single runtime's home"
  ;;
*)
  pass "the note path sits outside any single runtime's home"
  ;;
esac

pinned=$(lockfile_skills)
if [ "$(printf '%s\n' "$pinned" | grep -c .)" -eq 23 ]; then
  pass "skills-lock.json pins Matt's 22 skills and tldraw-skill"
else
  fail "skills-lock.json pins Matt's 22 skills and tldraw-skill"
fi

# The reason lazar-tldraw is vendored rather than hand-kept: an upstream nobody pins is an
# upstream nobody can update with a command.
if grep -qF '"source": "Agents365-ai/tldraw-skill"' "$HARNESS_SOURCE/skills-lock.json"; then
  pass "lazar-tldraw's upstream is pinned rather than hand-synced"
else
  fail "lazar-tldraw's upstream is pinned rather than hand-synced"
fi

# Everything of Matt's, judged as Matt's. tldraw-skill is pinned in the same lockfile but
# installs under a lazar- name, so it is asserted separately.
matt_pinned=$(printf '%s\n' "$pinned" | grep -vx 'tldraw-skill')

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
done <<<"$matt_pinned"

# Same rule, other prefix: upstream calls it tldraw-skill, and that name must not reach a runtime
# either — lazar-tldraw is what the harness declares and what CLAUDE.md points at.
for root in "$claude" "$opencode"; do
  [ -e "$root/skills/tldraw-skill" ] && unprefixed="$unprefixed $root/skills/tldraw-skill"
done

if grep -qx "name: lazar-tldraw" "$claude/skills/lazar-tldraw/SKILL.md"; then
  pass "the installed tldraw skill declares its lazar- name"
else
  fail "the installed tldraw skill declares its lazar- name"
fi

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

assert_agent_installs() {
  local name=$1
  local source_agent="$HARNESS_SOURCE/agents/$name.md"
  local claude_agent="$claude/agents/$name.md"
  local opencode_agent="$opencode/agents/$name.md"

  if [ ! -f "$source_agent" ]; then
    fail "$name is authored at agents/$name.md"
    return
  fi

  assert_same_file "$name installs to Claude Code verbatim" "$source_agent" "$claude_agent"
  assert_contains "$name declares mode: subagent for OpenCode" \
    "mode: subagent" "$opencode_agent"
  assert_contains "$name denies edit for OpenCode" "edit: deny" "$opencode_agent"
  assert_contains "$name keeps the authored description in OpenCode" \
    "$(grep -m1 '^description:' "$source_agent")" "$opencode_agent"

  if frontmatter_of "$opencode_agent" | grep -q '^name:'; then
    fail "$name drops Claude Code's name key for OpenCode"
  else
    pass "$name drops Claude Code's name key for OpenCode"
  fi

  if diff -q <(body_of "$source_agent") <(body_of "$opencode_agent") >/dev/null; then
    pass "$name's transform rewrites frontmatter and leaves the prompt alone"
  else
    fail "$name's transform rewrites frontmatter and leaves the prompt alone"
  fi
}

# These reviewers judge a repo against that repo's standards, so a global copy would review
# every repo against opinions it never agreed to.
leaked=""
for agent in code-reviewer data-reviewer plan-reviewer security-reviewer test-reviewer; do
  for root in "$claude" "$opencode"; do
    [ -e "$root/agents/$agent.md" ] && leaked="$leaked $root/agents/$agent.md"
  done
done

if [ -z "${leaked// /}" ]; then
  pass "the per-repo reviewers install nowhere globally"
else
  fail "the per-repo reviewers install nowhere globally:$leaked"
fi

# Every skill deleted with the per-repo bootstrap was unprefixed, and every skill the harness
# still ships is `lazar-` (mine) or `matt-` (vendored). So the prefix rule is what keeps a
# deleted name from returning, and asserting the rule outlives asserting a list of dead names,
# which would need hand-editing at every future deletion and says nothing about the next one.
unprefixed_skill=""
for root in "$claude" "$opencode"; do
  for installed in "$root"/skills/*/; do
    case "$(basename -- "${installed%/}")" in
    lazar-* | matt-*) ;;
    *) unprefixed_skill="$unprefixed_skill ${installed%/}" ;;
    esac
  done
done

if [ -z "${unprefixed_skill// /}" ]; then
  pass "every installed skill is prefixed, so no deleted skill returns under its old name"
else
  fail "every installed skill is prefixed:$unprefixed_skill"
fi

touch "$claude/skills/lazar-tldraw/STALE.md"
touch "$claude/rules/packs/stale-pack.md"
jq '.model = "anthropic/claude-opus-4-5"
  | .instructions += ["~/notes/house-style.md", "~/.config/opencode/rules/OLD-SPINE.md"]' \
  "$opencode/opencode.json" >"$opencode/opencode.json.seeded"
mv "$opencode/opencode.json.seeded" "$opencode/opencode.json"

# An agent the harness used to ship is only really dropped once an upgrade takes it off the
# disk of someone who installed it back when it was global.
printf -- '---\nname: code-reviewer\n---\n' >"$claude/agents/code-reviewer.md"
printf -- '---\nmode: subagent\n---\n' >"$opencode/agents/code-reviewer.md"

run_installer "$TEST_HOME" >/dev/null || fail "installing twice is safe"

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

stale=""
for root in "$claude" "$opencode"; do
  [ -e "$root/agents/code-reviewer.md" ] && stale="$stale $root/agents/code-reviewer.md"
done

if [ -z "${stale// /}" ]; then
  pass "reinstalling purges an agent the harness no longer ships"
else
  fail "reinstalling purges an agent the harness no longer ships:$stale"
fi

for agent in git-hygiene-reviewer clarity-reviewer yagni-reviewer; do
  assert_agent_installs "$agent"
done

# A `§N` is the contract between a citation and the doctrine: an agent's finding cites the
# number, and the spine promises its own cross-references resolve through the index. Dropping or
# renumbering a cited section breaks both silently, since the citation still reads fine while
# pointing at nothing. Read from the installed tree, which is what a runtime actually loads.
installed_sections=$(grep -hoE '^## §[0-9]+\.' \
  "$claude/rules/PHILOSOPHY.md" "$claude"/rules/packs/*.md | tr -cd '0-9\n' | sort -u)
unresolved=""
for citer in "$claude"/agents/*.md "$claude/CLAUDE.md" \
  "$claude/rules/PHILOSOPHY.md" "$claude"/rules/packs/*.md; do
  for cited in $(grep -oE '§[0-9]+' "$citer" | tr -cd '0-9\n' | sort -u); do
    printf '%s\n' "$installed_sections" | grep -qx -- "$cited" ||
      unresolved="$unresolved $(basename -- "$citer")→§$cited"
  done
done

if [ -z "${unresolved// /}" ]; then
  pass "every § the installed harness cites resolves to a section of the philosophy"
else
  fail "every § the installed harness cites resolves to a section of the philosophy:$unresolved"
fi

REDIRECT_HOME=$(mktemp -d)
redirect_claude="$REDIRECT_HOME/claude-config-dir"
redirect_xdg="$REDIRECT_HOME/xdg-config-home"

run_installer "$REDIRECT_HOME" \
  CLAUDE_CONFIG_DIR="$redirect_claude" XDG_CONFIG_HOME="$redirect_xdg" >/dev/null ||
  fail "the installer runs against redirected config homes"

assert_same_file "CLAUDE.md installs where CLAUDE_CONFIG_DIR points" \
  "$HARNESS_SOURCE/CLAUDE.md" "$redirect_claude/CLAUDE.md"
assert_same_file "the spine installs where CLAUDE_CONFIG_DIR points" \
  "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$redirect_claude/rules/PHILOSOPHY.md"
assert_same_file "skills install where CLAUDE_CONFIG_DIR points" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/SKILL.md" "$redirect_claude/skills/lazar-tldraw/SKILL.md"
assert_same_file "agents install where CLAUDE_CONFIG_DIR points" \
  "$HARNESS_SOURCE/agents/yagni-reviewer.md" "$redirect_claude/agents/yagni-reviewer.md"

if [ -e "$REDIRECT_HOME/.claude" ]; then
  fail "CLAUDE_CONFIG_DIR wins over ~/.claude, which Claude Code would not read"
else
  pass "CLAUDE_CONFIG_DIR wins over ~/.claude, which Claude Code would not read"
fi

assert_same_file "AGENTS.md installs where XDG_CONFIG_HOME points" \
  "$HARNESS_SOURCE/CLAUDE.md" "$redirect_xdg/opencode/AGENTS.md"
assert_same_file "the spine installs where XDG_CONFIG_HOME points" \
  "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$redirect_xdg/opencode/rules/PHILOSOPHY.md"

if [ -e "$REDIRECT_HOME/.config/opencode" ]; then
  fail "XDG_CONFIG_HOME wins over ~/.config, which OpenCode would not read"
else
  pass "XDG_CONFIG_HOME wins over ~/.config, which OpenCode would not read"
fi

# Resolve the reference the way OpenCode would rather than pinning its spelling: `~` is correct
# only while it expands onto the rules that were just written, which a moved config home breaks.
spine_ref=$(jq -r '.instructions[] | select(endswith("PHILOSOPHY.md"))' \
  "$redirect_xdg/opencode/opencode.json")

if [ -f "${spine_ref/#\~/$REDIRECT_HOME}" ]; then
  pass "opencode.json points at the spine it actually installed"
else
  fail "opencode.json points at the spine it actually installed: $spine_ref resolves nowhere"
fi

rm -rf -- "$REDIRECT_HOME"

if [ "$(canary_digest)" = "$canary_before" ]; then
  pass "the installer writes nothing outside the home the test gave it"
else
  fail "the installer writes nothing outside the home the test gave it"
fi

if [ "$failures" -eq 0 ]; then
  echo "install-smoke: all assertions passed"
else
  printf 'install-smoke: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
