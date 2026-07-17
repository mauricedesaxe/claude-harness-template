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
#
run_installer() {
  local home=$1
  shift
  env -i PATH="$PATH" HOME="$home" "$@" "$HARNESS_SOURCE/install.sh" --install
}

run_installer "$TEST_HOME" >/dev/null || {
  echo "FAIL install.sh exited non-zero" >&2
  exit 1
}

claude="$TEST_HOME/.claude"
opencode="$TEST_HOME/.config/opencode"
hooks="$TEST_HOME/.claude/hooks"
settings="$claude/settings.json"

# Read the wiring back out of settings.json rather than restating the path here: what has to hold
# is that the file Claude Code runs is the file the installer put there, and an assertion that
# spelled the path itself would go on agreeing with the installer through a rename of either.
#
# Named by event, never across all of them. enforce-jj.sh decides before a tool runs, and a
# PreToolUse guard wired to PostToolUse is asked after the worktree already exists — it would read
# correctly, install correctly, and be handed the call it exists to deny too late to deny it. An
# event-agnostic read cannot tell those apart.
wired_hooks() {
  jq -r --arg event "$1" '(.hooks[$event] // [])[] | .hooks[] | .command' "$settings"
}

# Same for the matcher: it is the hook's reach, and it is only true of what the hook decides on.
matcher_of() {
  jq -r --arg event "$1" --arg command "$2" \
    '(.hooks[$event] // [])[] | select(any(.hooks[]; .command == $command)) | .matcher // ""' \
    "$settings"
}

# Every hook wired anywhere, for the assertions about what an install must leave alone or take away.
all_wired_hooks() {
  jq -r '(.hooks // {}) | to_entries[] | .value[] | .hooks[] | .command' "$settings"
}

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

assert_same_file "enforce-jj.sh installs to the hooks dir" \
  "$HARNESS_SOURCE/hooks/enforce-jj.sh" "$hooks/enforce-jj.sh"

# Claude Code runs a hook as a command. A copy that arrived without its exec bit is installed,
# wired, reported, and dead — and it fails open, which is the direction that costs a working copy.
if [ -x "$hooks/enforce-jj.sh" ]; then
  pass "the installed hook is executable"
else
  fail "the installed hook is executable"
fi

installed_wiring=$(wired_hooks PreToolUse)

if [ "$installed_wiring" = "$hooks/enforce-jj.sh" ]; then
  pass "settings.json wires the hook, and only the hook, on PreToolUse at the installed path"
else
  fail "settings.json wires the hook, and only the hook, on PreToolUse at the installed path: got '$installed_wiring'"
fi

# A fresh install wires it once and nowhere else, so no other event fires it and no second entry
# runs it twice per call.
all_wiring=$(all_wired_hooks)

if [ "$all_wiring" = "$hooks/enforce-jj.sh" ]; then
  pass "a fresh install wires nothing but the hook, on no event but PreToolUse"
else
  fail "a fresh install wires nothing but the hook, on no event but PreToolUse: got '$all_wiring'"
fi

if [ -x "$installed_wiring" ]; then
  pass "the command settings.json names is a file that exists and runs"
else
  fail "the command settings.json names is a file that exists and runs"
fi

# A matcher is the hook's reach: Claude Code only hands it the calls the matcher names, so a tool
# missing here is a tool the hook is never asked about, and the hook's own logic for it is dead
# code that goes on reading correctly.
jj_matcher=$(matcher_of PreToolUse "$hooks/enforce-jj.sh")
for tool in Bash EnterWorktree; do
  case "|$jj_matcher|" in
  *"|$tool|"*)
    pass "the hook's matcher reaches $tool"
    ;;
  *)
    fail "the hook's matcher reaches $tool: got '$jj_matcher'"
    ;;
  esac
done

# OpenCode has no hook equivalent, so enforcement is Claude Code's alone and OpenCode keeps
# guidance. That asymmetry is chosen; a hooks dir sitting there unread would be it happening by
# accident, and would read to the next person as something that runs.
if [ -e "$opencode/hooks" ]; then
  fail "hooks install only where there is something to run them"
else
  pass "hooks install only where there is something to run them"
fi

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

assert_same_file "lazar-pr-status installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-pr-status/SKILL.md" "$claude/skills/lazar-pr-status/SKILL.md"
assert_same_file "lazar-pr-status installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-pr-status/SKILL.md" "$opencode/skills/lazar-pr-status/SKILL.md"

assert_same_file "lazar-commit installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-commit/SKILL.md" "$claude/skills/lazar-commit/SKILL.md"
assert_same_file "lazar-commit installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-commit/SKILL.md" "$opencode/skills/lazar-commit/SKILL.md"

assert_same_file "lazar-ship installs to Claude Code" \
  "$HARNESS_SOURCE/skills/lazar-ship/SKILL.md" "$claude/skills/lazar-ship/SKILL.md"
assert_same_file "lazar-ship installs to OpenCode" \
  "$HARNESS_SOURCE/skills/lazar-ship/SKILL.md" "$opencode/skills/lazar-ship/SKILL.md"

# Skills and agents reach skills by name: lazar-ship composes lazar-commit, and every reviewer
# tells a finding which skill to cite. A name the harness stopped shipping still reads fine and
# dispatches nowhere, which is how git-hygiene-reviewer went on citing `commit` and `ship` after
# both were renamed, and how the skills carried `work` long after it was deleted.
#
# A reference is recognised by its shape, never matched against a list of dead names a future
# rename would have to remember to extend. Either the name carries a harness prefix — asserted
# below, every installed skill is `lazar-` or `matt-`, so a prefixed token can only be meant as
# a skill — or the prose labels it one (`x` skill). Ordinary English carries neither marker,
# which is what keeps this off the words git-hygiene-reviewer is largely made of: it says
# "commit" constantly and correctly, and yagni-reviewer weighs unfelt "work".
#
# Only what this repo authors is walked. A vendored matt- skill's prose is upstream's to fix.
skill_refs() {
  grep -oE 'lazar-[a-z-]+' "$1"
  grep -oE '`[^`]+` +skills?([^A-Za-z]|$)' "$1" | sed -E 's/^`([^`]*)`.*/\1/'
}

dangling_refs=""
for authored_md in "$claude"/skills/lazar-*/SKILL.md "$claude"/agents/*.md; do
  for ref in $(skill_refs "$authored_md" | sort -u); do
    # The machine-local note lives under ~/.lazar-harness and is a path, not a skill.
    [ "$ref" = "lazar-harness" ] && continue
    [ -d "$claude/skills/$ref" ] ||
      dangling_refs="$dangling_refs ${authored_md#"$claude"/}->$ref"
  done
done

if [ -z "${dangling_refs// /}" ]; then
  pass "every skill and agent the harness authors names only skills it ships"
else
  fail "every skill and agent the harness authors names only skills it ships:$dangling_refs"
fi

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

# The hook this harness decided not to adopt, seeded exactly as it sits on the machine: a
# hand-written script in the hooks dir, wired to two events. The purge takes the script, and if the
# wiring outlived it every prompt and every stop would fire a file that is not there. So the merge
# has to drop an entry for a hook the harness no longer ships, the same way it drops an orphaned
# instructions entry, and drop the events left empty rather than keep their shells.
printf 'set the tab title\n' >"$claude/hooks/set-tab-title.sh"
chmod +x "$claude/hooks/set-tab-title.sh"

# settings.json is profile-specific and holds model choice, plugins and auth-adjacent config, so
# what is asserted is not only that the harness's own entry lands but that everything the user put
# there is still there afterwards — including a hook of their own, which is theirs because it lives
# outside the directory this installer owns rather than because of anything it is called.
jq --arg stale "$hooks/set-tab-title.sh" '
  .model = "opus[1m]"
  | .enabledPlugins = { "vercel@claude-plugins-official": true }
  | .permissions = { defaultMode: "auto" }
  | .hooks.UserPromptSubmit = [{ hooks: [{ type: "command", command: $stale }] }]
  | .hooks.Stop = [{ hooks: [{ type: "command", command: $stale }] }]
  | .hooks.PreToolUse += [{
      matcher: "Write",
      hooks: [{ type: "command", command: "~/bin/my-own-guard.sh" }]
    }]
' "$settings" >"$settings.seeded"
mv "$settings.seeded" "$settings"
jq '.model = "anthropic/claude-opus-4-5"
  | .instructions += ["~/notes/house-style.md", "~/.config/opencode/rules/OLD-SPINE.md"]' \
  "$opencode/opencode.json" >"$opencode/opencode.json.seeded"
mv "$opencode/opencode.json.seeded" "$opencode/opencode.json"

# An agent the harness used to ship is only really dropped once an upgrade takes it off the
# disk of someone who installed it back when it was global.
printf -- '---\nname: code-reviewer\n---\n' >"$claude/agents/code-reviewer.md"
printf -- '---\nmode: subagent\n---\n' >"$opencode/agents/code-reviewer.md"

# Same for a skill: deleting lazar-work from the repo does nothing for the disk of someone who
# installed it while the harness still shipped it, and it keeps loading until an install removes it.
for root in "$claude" "$opencode"; do
  mkdir -p -- "$root/skills/lazar-work/scripts"
  printf -- '---\nname: lazar-work\n---\n' >"$root/skills/lazar-work/SKILL.md"
  printf -- 'stale\n' >"$root/skills/lazar-work/scripts/run.sh"
done

reinstall_report=$(run_installer "$TEST_HOME") || fail "installing twice is safe"

# The run that applies it prints the same list as the run that only reports, which is the half a
# --install caller ever sees: the suite reaches this path without going through the bare form once,
# and so would anyone who read the README's second line first.
claude_real=$(cd -- "$claude" && pwd -P)

for reported in "skills/lazar-work" "agents/code-reviewer.md" "skills/lazar-tldraw/STALE.md" \
  "hooks/set-tab-title.sh"; do
  if printf '%s\n' "$reinstall_report" | grep -qF -- "delete  $claude_real/$reported"; then
    pass "the run that installs names $reported before purging it"
  else
    fail "the run that installs names $reported before purging it"
  fi
done

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

if [ -e "$hooks/set-tab-title.sh" ]; then
  fail "reinstalling purges a hook the harness no longer ships"
else
  pass "reinstalling purges a hook the harness no longer ships"
fi

# The half a purge on its own does not do. A wired command whose file is gone is not a no-op: it
# fires on every prompt of every session and fails there.
if all_wired_hooks | grep -qF -- 'set-tab-title.sh'; then
  fail "reinstalling drops the wiring of a hook it purged"
else
  pass "reinstalling drops the wiring of a hook it purged"
fi

# Not left as an event with an empty list of matchers, which is the shape a filter leaves behind
# and the shape that makes the file grow a shell of every hook ever shipped.
emptied=$(jq -r '[(.hooks // {}) | to_entries[] | select((.value | length) == 0) | .key] | join(" ")' \
  "$settings")

if [ -z "$emptied" ]; then
  pass "reinstalling leaves no hook event standing empty"
else
  fail "reinstalling leaves no hook event standing empty: $emptied"
fi

# The harness owns the hooks directory, not settings.json. A hook of the user's own, pointing
# anywhere else, is not the installer's to remove — and it has to still be wired to the event and
# the matcher they wired it to, which a grep of the whole file would not notice losing.
user_hook_matcher=$(matcher_of PreToolUse '~/bin/my-own-guard.sh')

if [ "$user_hook_matcher" = Write ]; then
  pass "reinstalling keeps a hook the user wired themselves, on its own event and matcher"
else
  fail "reinstalling keeps a hook the user wired themselves, on its own event and matcher: got '$user_hook_matcher'"
fi

# The reason this file is merged and not replaced: model choice and plugins are what differ between
# the profiles, and this is the file that carries them.
assert_contains "reinstalling keeps the model settings.json carries" 'opus[1m]' "$settings"
assert_contains "reinstalling keeps the plugins settings.json carries" \
  'vercel@claude-plugins-official' "$settings"
assert_contains "reinstalling keeps unrelated settings.json keys" 'defaultMode' "$settings"

jj_entries=$(jq --arg command "$hooks/enforce-jj.sh" \
  '[(.hooks // {}) | to_entries[] | .value[] | .hooks[] | select(.command == $command)] | length' \
  "$settings")

if [ "$jj_entries" -eq 1 ]; then
  pass "reinstalling wires the hook once rather than again"
else
  fail "reinstalling wires the hook once rather than again: got $jj_entries entries"
fi

# jq reads empty stdin as no input at all: it prints nothing and exits 0. So a merge that read an
# empty config would stage an empty file, pass its own `||` check, and move nothing over the config
# — leaving the hook installed, executable, reported, and wired to nothing at all, which is the same
# fail-open the exec-bit assertion exists to catch, one step later. Both merged configs are driven,
# because they read the file the same way.
for empty_config in "$settings" "$opencode/opencode.json"; do
  : >"$empty_config"
done

run_installer "$TEST_HOME" >/dev/null || fail "the installer runs against an empty config"

if [ "$(wired_hooks PreToolUse)" = "$hooks/enforce-jj.sh" ]; then
  pass "an empty settings.json is merged into rather than left empty"
else
  fail "an empty settings.json is merged into rather than left empty"
fi

assert_contains "an empty opencode.json is merged into rather than left empty" \
  '~/.config/opencode/rules/PHILOSOPHY.md' "$opencode/opencode.json"

# Whitespace-only reads to jq exactly like empty, and is what a file someone opened and saved looks
# like. Same path, and it is the one an eye would call non-empty.
printf '\n  \n' >"$settings"
run_installer "$TEST_HOME" >/dev/null || fail "the installer runs against a whitespace-only config"

if [ "$(wired_hooks PreToolUse)" = "$hooks/enforce-jj.sh" ]; then
  pass "a whitespace-only settings.json is merged into rather than left empty"
else
  fail "a whitespace-only settings.json is merged into rather than left empty"
fi

# A config that is not JSON is the other half: there is nothing to merge into and nothing safe to
# guess, so the run stops and leaves it alone rather than writing over what it could not read.
printf 'not json at all\n' >"$settings"
printf 'a hook of my own\n' >"$hooks/doomed-hook.sh"

if run_installer "$TEST_HOME" >/dev/null 2>&1; then
  fail "a settings.json that is not JSON stops the install"
else
  pass "a settings.json that is not JSON stops the install"
fi

assert_contains "a settings.json that is not JSON is left as it was" 'not json at all' "$settings"

# Ordering, and the reason for it. The merge is what can die, so it runs before the purge: a stopped
# run leaves a hooks dir the settings.json still describes, and re-reads and re-runs from there. The
# other order would purge first and then die, landing on exactly the state this pair exists to
# prevent — a hook off the disk with every profile still firing it on every prompt. Asserted on a
# hook the harness does not ship, because one it does ship survives either order and would agree
# with a purge that had already happened.
if [ -e "$hooks/doomed-hook.sh" ]; then
  pass "an install that stops on a bad settings.json has purged nothing yet"
else
  fail "an install that stops on a bad settings.json has purged nothing yet"
fi

printf '{}\n' >"$settings"
run_installer "$TEST_HOME" >/dev/null || fail "the installer recovers once settings.json is JSON"

stale_skill=""
for root in "$claude" "$opencode"; do
  [ -e "$root/skills/lazar-work" ] && stale_skill="$stale_skill $root/skills/lazar-work"
done

if [ -z "${stale_skill// /}" ]; then
  pass "reinstalling purges a skill the harness no longer ships"
else
  fail "reinstalling purges a skill the harness no longer ships:$stale_skill"
fi

# The purge is a whole-tree replace, so the same install that drops lazar-work must still land
# every skill the harness does ship, supporting files and all.
assert_same_file "reinstalling keeps a skill the harness still ships" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/SKILL.md" "$claude/skills/lazar-tldraw/SKILL.md"
assert_same_file "reinstalling keeps a still-shipped skill's supporting files" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/LICENSE" "$opencode/skills/lazar-tldraw/LICENSE"

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

# The surface is the environment, not the runtime, so it has to reach both runtimes' instructions.
# `§28` owns the principle either way; what is generated here is only which default follows from it.
SANDBOX_HOME=$(mktemp -d)

run_installer "$SANDBOX_HOME" HARNESS_SURFACE=sandbox >/dev/null ||
  fail "the installer runs for the sandbox surface"

for instructions in "$SANDBOX_HOME/.claude/CLAUDE.md" "$SANDBOX_HOME/.config/opencode/AGENTS.md"; do
  target=$(basename -- "$instructions")

  # Anchored on text only the generated block carries. `jj edit` also appears in the jj command
  # list above it, so asserting on that would pass on a transform that deleted the local block and
  # inserted nothing, which is the failure actually worth catching.
  assert_contains "the sandbox $target works the default workspace directly" \
    'The sandbox is the isolation' "$instructions"

  if grep -qF -- 'off fresh trunk' "$instructions"; then
    fail "the sandbox $target drops the local workspace-per-agent default"
  else
    pass "the sandbox $target drops the local workspace-per-agent default"
  fi

  if grep -q 'surface:local' "$instructions"; then
    fail "the sandbox $target carries no leftover surface marker"
  else
    pass "the sandbox $target carries no leftover surface marker"
  fi
done

assert_contains "the local CLAUDE.md cuts a workspace off fresh trunk" \
  'off fresh trunk' "$claude/CLAUDE.md"

if cmp -s -- "$claude/CLAUDE.md" "$SANDBOX_HOME/.claude/CLAUDE.md"; then
  fail "the two surfaces install different workspace defaults"
else
  pass "the two surfaces install different workspace defaults"
fi

# write_instructions treats every value that is not `local` as the sandbox, so a typo would install
# sandbox text on a laptop if this guard ever regressed.
BOGUS_HOME=$(mktemp -d)

if run_installer "$BOGUS_HOME" HARNESS_SURFACE=bogus >/dev/null 2>&1; then
  fail "an unknown HARNESS_SURFACE stops the install rather than picking a surface"
else
  pass "an unknown HARNESS_SURFACE stops the install rather than picking a surface"
fi

if [ -e "$BOGUS_HOME/.claude/CLAUDE.md" ]; then
  fail "an unknown HARNESS_SURFACE writes no instructions at all"
else
  pass "an unknown HARNESS_SURFACE writes no instructions at all"
fi

rm -rf -- "$BOGUS_HOME"
rm -rf -- "$SANDBOX_HOME"

# Hooks are the one target that does not resolve through the runtime's config home on a laptop:
# three Claude Code profiles here each have a config home of their own and all three point at one
# enforce-jj.sh, and settings.json names a hook by absolute path, so one copy serves all three.
# A sandbox has one config home and no profiles, so the exception has nothing to buy there and the
# hook resolves like every other target. Redirected on purpose: with CLAUDE_CONFIG_DIR unset the
# two branches resolve to the same path, so an unredirected run would pass either way.
SANDBOX_REDIRECT_HOME=$(mktemp -d)
sandbox_claude="$SANDBOX_REDIRECT_HOME/claude-config-dir"

run_installer "$SANDBOX_REDIRECT_HOME" HARNESS_SURFACE=sandbox \
  CLAUDE_CONFIG_DIR="$sandbox_claude" >/dev/null ||
  fail "the installer runs for the sandbox surface against a redirected config home"

assert_same_file "the sandbox hook installs under the config home it was given" \
  "$HARNESS_SOURCE/hooks/enforce-jj.sh" "$sandbox_claude/hooks/enforce-jj.sh"

if [ -e "$SANDBOX_REDIRECT_HOME/.claude" ]; then
  fail "the sandbox surface makes no shared hooks dir it has no second profile to share with"
else
  pass "the sandbox surface makes no shared hooks dir it has no second profile to share with"
fi

sandbox_wired=$(jq -r '.hooks.PreToolUse[].hooks[].command' "$sandbox_claude/settings.json")

if [ "$sandbox_wired" = "$sandbox_claude/hooks/enforce-jj.sh" ]; then
  pass "the sandbox settings.json wires the hook where the sandbox put it"
else
  fail "the sandbox settings.json wires the hook where the sandbox put it: got '$sandbox_wired'"
fi

rm -rf -- "$SANDBOX_REDIRECT_HOME"

# `~/.claude-personal/skills` is a symlink to `~/.claude/skills` on the machine this harness is
# being installed onto, so the skills dir the installer is handed genuinely resolves elsewhere.
# Replacing the link with a real directory would purge nothing: the tree the other path reads
# would keep every skill this install exists to take off the disk.
LINKED_HOME=$(mktemp -d)
linked_target="$LINKED_HOME/real-skills"

mkdir -p -- "$linked_target/lazar-work" "$LINKED_HOME/.claude"
printf -- '---\nname: lazar-work\n---\n' >"$linked_target/lazar-work/SKILL.md"
ln -s -- "$linked_target" "$LINKED_HOME/.claude/skills"

run_installer "$LINKED_HOME" >/dev/null || fail "the installer runs against a symlinked skills dir"

if [ -L "$LINKED_HOME/.claude/skills" ]; then
  pass "installing leaves a symlinked skills dir a symlink"
else
  fail "installing leaves a symlinked skills dir a symlink"
fi

assert_same_file "installing lands skills in the symlink's target" \
  "$HARNESS_SOURCE/skills/lazar-tldraw/SKILL.md" "$linked_target/lazar-tldraw/SKILL.md"

if [ -e "$linked_target/lazar-work" ]; then
  fail "installing purges a stale skill through a symlinked skills dir"
else
  pass "installing purges a stale skill through a symlinked skills dir"
fi

rm -rf -- "$LINKED_HOME"

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

# Anything that is loaded by virtue of sitting in a config home has to land in the config home
# Claude Code was pointed at, or it is not read at all. The hooks dir is the one thing under
# ~/.claude that is loaded by the absolute path in settings.json instead, so where it sits is not
# what makes it run, and it is asserted on its own terms below.
# Walked with find rather than a glob, which would skip a dotfile and so pass on anything the
# installer ever lands under a name starting with a dot.
stray=""
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  case "${entry##*/}" in
  hooks) ;;
  *) stray="$stray $entry" ;;
  esac
done < <(find "$REDIRECT_HOME/.claude" -mindepth 1 -maxdepth 1 2>/dev/null)

if [ -z "${stray// /}" ]; then
  pass "CLAUDE_CONFIG_DIR wins over ~/.claude for everything read out of a config home"
else
  fail "CLAUDE_CONFIG_DIR wins over ~/.claude for everything read out of a config home:$stray"
fi

# A profile install, which is what each of the three on this machine is. The hook lands in the
# shared dir rather than beside the profile's own settings.json, and that settings.json points at
# it, which is what makes one script serve three profiles instead of three copies drifting apart.
assert_same_file "a profile install lands the hook in the shared hooks dir" \
  "$HARNESS_SOURCE/hooks/enforce-jj.sh" "$REDIRECT_HOME/.claude/hooks/enforce-jj.sh"

if [ -e "$redirect_claude/hooks" ]; then
  fail "a profile install keeps no hooks dir of its own to drift"
else
  pass "a profile install keeps no hooks dir of its own to drift"
fi

redirect_wired=$(jq -r '.hooks.PreToolUse[].hooks[].command' "$redirect_claude/settings.json")

if [ "$redirect_wired" = "$REDIRECT_HOME/.claude/hooks/enforce-jj.sh" ] && [ -x "$redirect_wired" ]; then
  pass "the profile's settings.json wires the shared hook by the path it really sits at"
else
  fail "the profile's settings.json wires the shared hook by the path it really sits at: got '$redirect_wired'"
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

# The unsafe invocation, driven rather than described: no --install, with CLAUDE_CONFIG_DIR
# pointing at a live harness. install.sh carries why that shape cost someone their config.
#
# Deliberately not run_installer: that appends --install, and what is under test is the run that
# does not. The scrub is the same, because the hole was never the environment.
UNGUARDED_HOME=$(mktemp -d)
live_claude="$UNGUARDED_HOME/live-claude"
live_xdg="$UNGUARDED_HOME/live-xdg"
live_skills="$UNGUARDED_HOME/real-skills"

# Symlinked the way this machine really is, so the report has to resolve to say anything true: the
# path handed in names a link that survives, and the tree that loses the skill is the one behind it.
# Left unlinked, the resolution would only have teeth where /var happens to resolve to /private/var,
# which is the laptop and not the Linux sandbox this same suite runs in.
mkdir -p -- "$live_claude/agents" "$live_xdg/opencode" "$UNGUARDED_HOME/.claude/hooks" \
  "$live_skills/hand-written-skill" "$live_skills/lazar-tldraw"
ln -s -- "$live_skills" "$live_claude/skills"

# The hooks dir is shared rather than resolved through CLAUDE_CONFIG_DIR, so a run aimed at a live
# profile reaches a directory that is not under the config home it names — which is exactly why the
# report has to say so before anything is written. The hand-written hook here is the real one on
# this machine: it is not adopted, so an install takes it, and that has to be knowable first.
printf 'set the tab title\n' >"$UNGUARDED_HOME/.claude/hooks/set-tab-title.sh"

printf -- '---\nname: hand-written-skill\n---\n' >"$live_skills/hand-written-skill/SKILL.md"
printf -- '---\nname: lazar-tldraw\n---\n' >"$live_skills/lazar-tldraw/SKILL.md"
printf -- '---\nname: hand-written-agent\n---\n' >"$live_claude/agents/hand-written-agent.md"
printf 'a live harness lives here\n' >"$live_claude/CLAUDE.md"
printf '{"model":"opus[1m]"}\n' >"$live_claude/settings.json"

live_digest() {
  find "$UNGUARDED_HOME" | sort
  find "$UNGUARDED_HOME" -type f -exec cksum {} + | sort
}

live_before=$(live_digest)
unguarded_report=$(env -i PATH="$PATH" HOME="$UNGUARDED_HOME" \
  CLAUDE_CONFIG_DIR="$live_claude" XDG_CONFIG_HOME="$live_xdg" \
  "$HARNESS_SOURCE/install.sh" 2>&1)
unguarded_status=$?

if [ "$(live_digest)" = "$live_before" ]; then
  pass "an install.sh run with no --install writes nothing into a live config home"
else
  fail "an install.sh run with no --install writes nothing into a live config home"
fi

# Knowable before it is deleted. The entry is matched with its verb and its column, so a report
# that named it under some other heading does not pass, and the paths are the resolved ones because
# that is what replace_dir would delete.
live_real=$(cd -- "$live_claude" && pwd -P)
live_skills_real=$(cd -- "$live_skills" && pwd -P)
live_hooks_real=$(cd -- "$UNGUARDED_HOME/.claude/hooks" && pwd -P)

for doomed in "$live_skills_real/hand-written-skill" "$live_real/agents/hand-written-agent.md" \
  "$live_hooks_real/set-tab-title.sh"; do
  if printf '%s\n' "$unguarded_report" | grep -qF -- "delete  $doomed"; then
    pass "a run with no --install names ${doomed##*/} as a deletion"
  else
    fail "a run with no --install names ${doomed##*/} as a deletion"
  fi
done

# The hooks dir is not under the config home the run names, so a reader who only saw the `claude`
# line would not know which directory this is about to own. It is named whether or not anything in
# it is doomed, because an empty delete list is only reassuring once you know where it was read.
#
# Matched unresolved, the way the `claude` and `opencode` lines beside it are: the header names the
# directory it was pointed at, and the delete lines below resolve because they name what will
# actually be unlinked. On Linux the two spellings are one string and this reads as pedantry; on a
# Mac /var is /private/var, and asserting the resolved form here would fail on the machine the
# harness installs to while passing in the sandbox the same suite runs in.
if printf '%s\n' "$unguarded_report" | grep -qF -- "hooks     $UNGUARDED_HOME/.claude/hooks"; then
  pass "a run with no --install names the hooks dir it would own"
else
  fail "a run with no --install names the hooks dir it would own"
fi

# settings.json is merged rather than replaced, and it is still rewritten: the run that takes a hook
# off the disk takes its wiring out of this file, so it belongs in the list of what would be touched.
if printf '%s\n' "$unguarded_report" | grep -qF -- "merge   $live_real/settings.json"; then
  pass "a run with no --install names the settings.json it would merge"
else
  fail "a run with no --install names the settings.json it would merge"
fi

# The incident took three things and the third was a hand-written CLAUDE.md, which is replaced
# rather than deleted and so has to be named under its own verb or the report covers two thirds.
if printf '%s\n' "$unguarded_report" | grep -qF -- "replace $live_real/CLAUDE.md"; then
  pass "a run with no --install names the CLAUDE.md it would replace"
else
  fail "a run with no --install names the CLAUDE.md it would replace"
fi

# The other half of a true list: a report that condemned everything would satisfy every assertion
# above while telling the reader nothing. lazar-tldraw is shipped, so it survives, so it must not
# be named.
if printf '%s\n' "$unguarded_report" | grep -qF -- "delete  $live_skills_real/lazar-tldraw"; then
  fail "a run with no --install leaves a skill the harness ships out of the delete list"
else
  pass "a run with no --install leaves a skill the harness ships out of the delete list"
fi

# A refusal that exits non-zero reads as an invocation to fix, and the agent that fixes it is the
# agent this guard exists to stop. A report that exits 0 has already answered the question.
if [ "$unguarded_status" -eq 0 ]; then
  pass "a run with no --install exits 0 rather than inviting a retry"
else
  fail "a run with no --install exits 0 rather than inviting a retry: $unguarded_status"
fi

rm -rf -- "$UNGUARDED_HOME"

# --install is the only spelling that authorises a write, so a near miss has to land on the refusal
# and not on the install. A typo that fell through to APPLY=false would report and exit 0, which
# reads as success to whatever ran it.
BOGUS_ARG_HOME=$(mktemp -d)

for bogus in --install=true -install --INSTALL --force; do
  if env -i PATH="$PATH" HOME="$BOGUS_ARG_HOME" \
    "$HARNESS_SOURCE/install.sh" "$bogus" >/dev/null 2>&1; then
    fail "$bogus is refused rather than taken for --install"
  else
    pass "$bogus is refused rather than taken for --install"
  fi
done

if [ -e "$BOGUS_ARG_HOME/.claude" ]; then
  fail "an argument the installer does not take writes nothing at all"
else
  pass "an argument the installer does not take writes nothing at all"
fi

rm -rf -- "$BOGUS_ARG_HOME"

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
