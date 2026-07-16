#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
OPENCODE_HOME="$HOME/.config/opencode"

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

install_skills() {
  local skill name
  for skill in "$HARNESS_SOURCE"/skills/*/; do
    skill=${skill%/}
    name=$(basename -- "$skill")
    replace_dir "$CLAUDE_HOME/skills/$name" "$skill"
    replace_dir "$OPENCODE_HOME/skills/$name" "$skill"
  done
}

install_agents() {
  local agent name
  mkdir -p -- "$CLAUDE_HOME/agents" "$OPENCODE_HOME/agents"
  for agent in "$HARNESS_SOURCE"/agents/*.md; do
    name=$(basename -- "$agent")
    cp -- "$agent" "$CLAUDE_HOME/agents/$name"
    write_opencode_agent "$agent" "$OPENCODE_HOME/agents/$name"
  done
}

install_instructions
install_skills
install_agents

printf 'lazar-harness installed to %s and %s\n' "$CLAUDE_HOME" "$OPENCODE_HOME"
