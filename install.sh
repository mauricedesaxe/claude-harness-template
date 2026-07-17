#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Which environment the installed instructions are for, not which runtime reads them: Claude Code
# and OpenCode both run on a laptop and both run inside a sandbox, and it is the environment that
# decides whether the working copy is shared. A sandbox image build passes `sandbox` when it
# invokes this script; everything else gets the laptop default.
HARNESS_SURFACE="${HARNESS_SURFACE:-local}"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_RULES="$CLAUDE_HOME/rules"
OPENCODE_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_RULES="$OPENCODE_HOME/rules"

# The instructions merge drops its own previous entries by matching this prefix, so changing the
# spelling orphans an existing install's rather than replacing them. `~` is what OpenCode expands
# and what is already on disk; only rules landing outside $HOME need the absolute form.
case "$OPENCODE_RULES" in
"$HOME"/*) OPENCODE_RULES_REF="~/${OPENCODE_RULES#"$HOME"/}" ;;
*) OPENCODE_RULES_REF="$OPENCODE_RULES" ;;
esac

die() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

APPLY=false

# `rm -rf` unlinks a symlink rather than following it, so a destination that is one has to be
# resolved before it is replaced, and named as what it resolves to before it is reported: on this
# machine ~/.claude-personal/skills is a link to ~/.claude/skills, and both the deletion and the
# report are only true of the target. CDPATH would print the directory it matched on a relative
# path, and this is a command substitution, so it would land in the caller's variable.
resolve_dir() {
  CDPATH='' cd -- "$1" && pwd -P
}

# A destination is replaced wholesale, so whatever is in it that the source has no name for is
# what an install costs, and it is the same list either way: the run that applies it prints it too.
# Recursive, because the replace reaches all the way down and a report that stopped at the top
# would keep quiet about a file hand-edited inside a directory the harness does still ship. It
# prunes at the shallowest name that goes, so an orphan skill is one line rather than its whole
# tree, and it never reads the report out of a directory it could not read.
report_replace() {
  local dest=$1 source=$2 entries entry name
  [ -d "$dest" ] || return 0
  dest=$(resolve_dir "$dest")
  entries=$(find "$dest" -mindepth 1 -maxdepth 1 2>/dev/null | sort || true)
  [ -n "$entries" ] || return 0
  while IFS= read -r entry; do
    name=${entry##*/}
    if [ ! -e "$source/$name" ]; then
      printf '  %-7s %s\n' delete "$entry"
    elif [ -d "$entry" ] && [ -d "$source/$name" ]; then
      report_replace "$entry" "$source/$name"
    fi
  done <<<"$entries"
}

# Resolved through its parent for the same reason report_replace resolves: one report naming the
# same directory two ways is a report the reader has to check rather than read.
report_write() {
  local dest=$1 verb=${2:-replace}
  if [ -e "$dest" ]; then
    printf '  %-7s %s/%s\n' "$verb" "$(resolve_dir "$(dirname -- "$dest")")" "${dest##*/}"
  fi
}

report_plan() {
  printf 'install.sh: %s\n' "$1"
  printf '  claude    %s\n' "$CLAUDE_HOME"
  printf '  opencode  %s\n' "$OPENCODE_HOME"
  # Named on its own line because it is the one target that is not under either home above, and a
  # purge list is only knowable in advance if the reader knows which directory it is about to read.
  printf '  hooks     %s\n' "$CLAUDE_HOOKS"
  printf '  surface   %s\n' "$HARNESS_SURFACE"
  report_write "$CLAUDE_HOME/CLAUDE.md"
  report_write "$OPENCODE_HOME/AGENTS.md"
  report_write "$CLAUDE_RULES/PHILOSOPHY.md"
  report_write "$OPENCODE_RULES/PHILOSOPHY.md"
  report_write "$OPENCODE_HOME/opencode.json" merge
  report_write "$CLAUDE_HOME/settings.json" merge
  report_replace "$CLAUDE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  report_replace "$OPENCODE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  report_replace "$CLAUDE_HOME/skills" "$HARNESS_SOURCE/skills"
  report_replace "$OPENCODE_HOME/skills" "$HARNESS_SOURCE/skills"
  report_replace "$CLAUDE_HOME/agents" "$HARNESS_SOURCE/agents"
  report_replace "$OPENCODE_HOME/agents" "$HARNESS_SOURCE/agents"
  report_replace "$CLAUDE_HOOKS" "$HARNESS_SOURCE/hooks"
}

# Stage the copy before deleting anything: a destination that resolves back into the source
# (a symlinked ~/.claude/skills, say) would otherwise have the payload deleted out from under it.
# Dropping a real directory over a link would leave the tree it pointed at untouched, and a tree
# replaced wholesale that way purges nothing a runtime reading the other path still loads.
replace_dir() {
  local dest=$1 source=$2 staged
  [ -d "$dest" ] && dest=$(resolve_dir "$dest")
  mkdir -p -- "$(dirname -- "$dest")"
  staged=$(mktemp -d -- "$(dirname -- "$dest")/.install-XXXXXX")
  cp -R -- "$source" "$staged/payload"
  rm -rf -- "$dest"
  mv -- "$staged/payload" "$dest"
  rmdir -- "$staged"
}

# OpenCode rejects an agent without `mode`. Every agent this harness ships is a reviewer,
# so it gets the reviewer's permissions: no edit tool, and the bash it needs to read a diff.
write_opencode_agent() {
  local source=$1 dest=$2

  [ "$(head -n 1 -- "$source")" = "---" ] || die "$source has no frontmatter"

  awk '
    NR == 1 { print; next }
    !past_frontmatter && /^---$/ {
      print "mode: subagent"
      print "permission:"
      print "  edit: deny"
      print "  bash: allow"
      print "  webfetch: allow"
      print
      past_frontmatter = 1
      next
    }
    !past_frontmatter && /^name:/ { next }
    { print }
  ' "$source" >"$dest"

  grep -q '^mode: subagent$' "$dest" ||
    die "$source: frontmatter never closes, so no OpenCode mode was generated"
}

# `§28` states the isolation principle for every surface; only the default action differs, and a
# sandbox is a checkout of its own, so the workspace-per-agent rule that keeps concurrent local
# agents off a shared `@` buys nothing there.
# Reaches awk through the environment because `awk -v` runs escape processing over its value and
# the one-true-awk rejects a literal newline in it outright.
SANDBOX_WORKSPACE_DEFAULT=$(
  cat <<'MD'
**Work the default workspace directly with `jj edit`.** The sandbox is the isolation: this checkout
is mine alone, and a workspace inside it would buy nothing. Reach for `jj workspace add` only when
fanning out concurrent subagents that edit at once, which is the one case where a shared `@` still
collides (`§28`).
MD
)

# CLAUDE.md is authored for the local surface the way agents/ is authored for Claude Code: whichever
# target needs the other dialect has it generated, so no second copy is hand-kept.
write_instructions() {
  local dest=$1 source="$HARNESS_SOURCE/CLAUDE.md" staged

  if [ "$HARNESS_SURFACE" = local ]; then
    cp -- "$source" "$dest"
    return
  fi

  # An unclosed block leaves awk skipping to EOF, which truncates the file rather than failing.
  grep -qxF -- '<!-- /surface:local -->' "$source" ||
    die "CLAUDE.md's surface:local block never closes, so $dest would be truncated at the marker"

  # Staged like every other write here, so a failed transform leaves the previous install in place
  # rather than a half-generated file. Substituting anything but exactly once means the markers
  # moved, and the alternative to failing on that is silently shipping a sandbox the local default.
  staged=$(mktemp -- "$dest.XXXXXX")
  SANDBOX_WORKSPACE_DEFAULT="$SANDBOX_WORKSPACE_DEFAULT" awk '
    BEGIN { block = ENVIRON["SANDBOX_WORKSPACE_DEFAULT"] }
    /^<!-- surface:local\./ { print block; substituted++; skipping = 1; next }
    $0 == "<!-- /surface:local -->" { skipping = 0; next }
    !skipping
    END { exit substituted == 1 ? 0 : 1 }
  ' "$source" >"$staged" || {
    rm -f -- "$staged"
    die "CLAUDE.md has no single surface:local block, so no $HARNESS_SURFACE default was generated"
  }

  mv -- "$staged" "$dest"
}

install_instructions() {
  mkdir -p -- "$CLAUDE_HOME" "$OPENCODE_HOME"
  write_instructions "$CLAUDE_HOME/CLAUDE.md"
  write_instructions "$OPENCODE_HOME/AGENTS.md"
}

# A config the harness merges into rather than owns has to survive being absent and being empty. jq
# reads empty stdin as no input at all: it prints nothing and exits 0, so a merge of an empty file
# would stage an empty file, report success, and replace a config that carries someone's model
# choice with nothing. Whitespace-only reads the same way.
read_json_object() {
  local existing=''
  [ -f "$1" ] && existing=$(<"$1")
  [ -n "${existing//[[:space:]]/}" ] || existing='{}'
  printf '%s' "$existing"
}

# Belt to read_json_object's braces: jq can also stop after writing nothing for a reason neither of
# them saw coming, and every one of those ends the same way — an empty file moved over a real one.
commit_merge() {
  local staged=$1 config=$2
  [ -s "$staged" ] || {
    rm -f -- "$staged"
    die "merging $config produced an empty file, so $config was left alone"
  }
  mv -- "$staged" "$config"
}

# OpenCode has no equivalent of `paths:`, so every instructions entry loads in every session and
# the packs cannot scope themselves there.
write_opencode_instructions() {
  local config="$OPENCODE_HOME/opencode.json" existing staged

  existing=$(read_json_object "$config")

  staged=$(mktemp -- "$config.XXXXXX")
  printf '%s' "$existing" | jq \
    --arg schema https://opencode.ai/config.json \
    --arg prefix "$OPENCODE_RULES_REF/" \
    --arg spine "$OPENCODE_RULES_REF/PHILOSOPHY.md" \
    --arg packs "$OPENCODE_RULES_REF/packs/*.md" '
      ."$schema" //= $schema
      | .instructions = (
          [(.instructions // [])[] | select(startswith($prefix) | not)] + [$spine, $packs]
        )
    ' >"$staged" || {
    rm -f -- "$staged"
    die "could not merge $config"
  }
  commit_merge "$staged" "$config"
}

# Claude Code reads every .md under its rules dir. A rule with no `paths:` frontmatter loads in
# every session; one with `paths:` loads only when the agent touches a file that matches. That is
# what carries the spine into every repo with no per-repo setup while each pack applies itself by
# paradigm. Spine and packs keep their source layout so the relative links between them resolve.
install_philosophy() {
  mkdir -p -- "$CLAUDE_RULES" "$OPENCODE_RULES"
  cp -- "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$CLAUDE_RULES/PHILOSOPHY.md"
  cp -- "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$OPENCODE_RULES/PHILOSOPHY.md"
  replace_dir "$CLAUDE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  replace_dir "$OPENCODE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  write_opencode_instructions
}

# A skill the harness stops shipping has to stop loading, so the whole tree is replaced rather
# than each shipped name in turn, which never touches a destination the source has no name for.
install_skills() {
  replace_dir "$CLAUDE_HOME/skills" "$HARNESS_SOURCE/skills"
  replace_dir "$OPENCODE_HOME/skills" "$HARNESS_SOURCE/skills"
}

# The tools enforce-jj.sh decides on. Claude Code only hands a hook the calls its matcher names, so
# a tool missing here is a tool the hook never sees: `Agent` is on the list because `isolation:
# "worktree"` cuts a git worktree through neither `Bash` nor `EnterWorktree`, which is how it walked
# past the hand-wired matcher this replaces for as long as that matcher was hand-wired.
JJ_HOOK_MATCHER='Bash|EnterWorktree'

# A hook is the only rule the harness enforces rather than asks for: CLAUDE.md and the rules dir
# are not inherited by subagents, so a rule written there reaches a main loop and dies at the first
# delegation boundary, while a PreToolUse hook fires for every agent at every depth. That is not
# theoretical — an agent told not to run this file complied, and the subagent it spawned ran it.
#
# OpenCode gets none of this. It has no hook equivalent, so it keeps guidance alone. Enforcement
# where it is available beats enforcement nowhere, and that asymmetry is chosen, not overlooked.
#
# A hook the harness stops shipping has to stop firing, so the tree is replaced whole the way
# skills and agents are. Taking the script off the disk is only half of it: write_claude_settings
# takes the wiring with it, or every prompt would fire a file that is no longer there.
install_hooks() {
  replace_dir "$CLAUDE_HOOKS" "$HARNESS_SOURCE/hooks"
}

# settings.json is the profile's own file — model choice, enabledPlugins, extraKnownMarketplaces,
# auth-adjacent config — and it is the file that genuinely differs between the profiles here, so it
# is merged and never replaced. Same shape as write_opencode_instructions: drop what a previous run
# of this installer wrote, recognised by the hooks directory it points into, then add back what the
# harness ships now. A matcher group left with no hooks, and an event left with no groups, go too,
# or the file grows an empty shell of every hook ever shipped.
write_claude_settings() {
  local config="$CLAUDE_HOME/settings.json" existing staged

  existing=$(read_json_object "$config")

  staged=$(mktemp -- "$config.XXXXXX")
  printf '%s' "$existing" | jq \
    --arg prefix "$CLAUDE_HOOKS/" \
    --arg matcher "$JJ_HOOK_MATCHER" \
    --arg command "$CLAUDE_HOOKS/enforce-jj.sh" '
      def without_harness_hooks:
        [ .[] | .hooks = [ (.hooks // [])[] | select((.command // "") | startswith($prefix) | not) ]
              | select((.hooks | length) > 0) ];
      .hooks = ((.hooks // {}) | with_entries(.value |= without_harness_hooks))
      | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{
          matcher: $matcher,
          hooks: [{ type: "command", command: $command }]
        }])
      | .hooks |= with_entries(select((.value | length) > 0))
    ' >"$staged" || {
    rm -f -- "$staged"
    die "could not merge $config"
  }
  commit_merge "$staged" "$config"
}

# An agent the harness stops shipping has to stop reviewing, so each directory is replaced
# rather than copied into.
install_agents() {
  local built agent name
  built=$(mktemp -d)
  mkdir -p -- "$built/claude" "$built/opencode"

  for agent in "$HARNESS_SOURCE"/agents/*.md; do
    name=$(basename -- "$agent")
    cp -- "$agent" "$built/claude/$name"
    write_opencode_agent "$agent" "$built/opencode/$name"
  done

  replace_dir "$CLAUDE_HOME/agents" "$built/claude"
  replace_dir "$OPENCODE_HOME/agents" "$built/opencode"
  rm -rf -- "$built"
}

# Writing is opt-in because not writing has to be what a script nobody has read does. A
# code-reviewer subagent ran this file with no argument while CLAUDE_CONFIG_DIR pointed at a live
# harness, and the purge wiped it: 12 skills, 5 agents and a hand-written CLAUDE.md, off the
# machine it was reviewing on. It had been told not to; the brief reached the agent that spawned it
# and stopped there, which is the whole reason this is a line of code and not a line of prose.
#
# The flag rides argv rather than the environment on purpose. The test scrubs with `env -i` and
# passes it alongside, so the one thing that authorises a write is the one thing that cannot arrive
# by inheritance from the shell an agent happens to be standing in. A `HARNESS_INSTALL=1` would
# read the same and hand that back.
for arg in "$@"; do
  case "$arg" in
  --install) APPLY=true ;;
  *) die "$arg is not an argument this takes; it takes --install and nothing else" ;;
  esac
done

# Every other target resolves through the runtime's own config home, which is what lets one
# installer serve the three Claude Code profiles on this laptop. Hooks are the deliberate exception,
# and they can be: settings.json names a hook by absolute path rather than discovering it under a
# config home, so one script serves every profile that points at it and three copies would only give
# three things to drift. That is also why this is a plain shared path and not the symlink the skills
# dir uses — a symlink is there to make a directory appear under a home that globs it, and nothing
# globs this one, so the link would be indirection bought for a lookup that never happens.
#
# The exception is the topology's, not the harness's: a sandbox has one config home and no profiles,
# so there is nothing to share with and it resolves like everything else.
#
# The cost of sharing, stated because it is real. This run purges a directory every profile reads
# but only rewrites the settings.json of the profile it was pointed at, because that is the only one
# it can see: nothing tells it the other two exist. So a run that drops a hook leaves the profiles it
# was not run for wiring a file that is gone, until they are installed too. Every other target has
# the same shape — a profile has last release's CLAUDE.md until its own run — but for those the
# stale profile is merely behind, and for this one it fires a missing file on every prompt. Install
# every profile in one go, and read the plan before the first, not between the second and the third.
case "$HARNESS_SURFACE" in
local) CLAUDE_HOOKS="$HOME/.claude/hooks" ;;
sandbox) CLAUDE_HOOKS="$CLAUDE_HOME/hooks" ;;
*) die "HARNESS_SURFACE is $HARNESS_SURFACE; it takes local or sandbox" ;;
esac

# Only the merges need it, so a run that reports and stops is not the place to insist on it.
[ "$APPLY" = false ] ||
  command -v jq >/dev/null ||
  die "jq is needed to merge OpenCode's instructions array and Claude Code's hooks"

if [ "$APPLY" = false ]; then
  report_plan "this is what installing would do to this machine"
  printf 'install.sh: nothing was written. Re-run with --install to apply it.\n'
  exit 0
fi

report_plan "installing"

install_instructions
install_philosophy
install_skills
install_agents

# The wiring before the disk. A merge that dies takes the whole run with it, and the order decides
# which side of the purge it dies on: this way settings.json still names a hook that is still there,
# and the run can be re-read and re-run. The other way round leaves the state this pair exists to
# prevent — a hook purged off the disk and every profile still firing it on every prompt.
write_claude_settings
install_hooks

printf 'lazar-harness installed to %s and %s for the %s surface, with hooks in %s\n' \
  "$CLAUDE_HOME" "$OPENCODE_HOME" "$HARNESS_SURFACE" "$CLAUDE_HOOKS"
