#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
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

# Stage the copy before deleting anything: a destination that resolves back into the source
# (a symlinked ~/.claude/skills, say) would otherwise have the payload deleted out from under it.
replace_dir() {
  local dest=$1 source=$2 staged
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

install_instructions() {
  mkdir -p -- "$CLAUDE_HOME" "$OPENCODE_HOME"
  cp -- "$HARNESS_SOURCE/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
  cp -- "$HARNESS_SOURCE/CLAUDE.md" "$OPENCODE_HOME/AGENTS.md"
}

# OpenCode has no equivalent of `paths:`, so every instructions entry loads in every session and
# the packs cannot scope themselves there.
write_opencode_instructions() {
  local config="$OPENCODE_HOME/opencode.json" existing='{}' staged

  [ -f "$config" ] && existing=$(<"$config")

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
  mv -- "$staged" "$config"
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

install_skills() {
  local skill name
  for skill in "$HARNESS_SOURCE"/skills/*/; do
    skill=${skill%/}
    name=$(basename -- "$skill")
    replace_dir "$CLAUDE_HOME/skills/$name" "$skill"
    replace_dir "$OPENCODE_HOME/skills/$name" "$skill"
  done
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

command -v jq >/dev/null || die "jq is needed to merge OpenCode's instructions array"

install_instructions
install_philosophy
install_skills
install_agents

printf 'lazar-harness installed to %s and %s\n' "$CLAUDE_HOME" "$OPENCODE_HOME"
