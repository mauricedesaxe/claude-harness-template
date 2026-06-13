#!/usr/bin/env bash
# Installs the universal claude-harness files into a target repo. The bootstrap-harness
# SKILL.md runs this from a freshly cloned template so Claude Code and Codex write the
# exact same files; this script is the single source of truth for those writes.
set -euo pipefail

usage() {
  printf 'Usage: %s [target-repo]\n' "$(basename "$0")" >&2
}

fail() {
  printf 'bootstrap-harness: %s\n' "$1" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template_root="$(cd "$script_dir/../.." && pwd)"
target_input="${1:-$PWD}"

repo_root="$(git -C "$target_input" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "target must be inside a git repo: $target_input"

# Single manifest. Both the install loop and the preserve-detection below derive from
# these arrays, so a universal file can never be installed and then also reported as
# project-specific.
universal_skills=(work research commit review capture ship setup neobrutalist-pop)
universal_agents=(code-reviewer test-reviewer plan-reviewer data-reviewer security-reviewer)
# Extra universal files keyed as "relative/path" — copied verbatim alongside the skills.
universal_extras=(
  ".claude/skills/neobrutalist-pop/assets/brutpop.css"
  "docs/PHILOSOPHY.md"
  "docs/packs/web.md"
  "docs/packs/ai.md"
)

is_universal_skill() {
  local name="$1" s
  for s in "${universal_skills[@]}"; do [[ "$s" == "$name" ]] && return 0; done
  return 1
}

is_universal_agent() {
  local name="$1" a
  for a in "${universal_agents[@]}"; do [[ "$a" == "$name" ]] && return 0; done
  return 1
}

# Every relative path this run reads from the template. Pre-validated before any write so
# a missing source aborts the whole install instead of leaving a half-written .claude/.
template_sources=()
for skill in "${universal_skills[@]}"; do
  template_sources+=(".claude/skills/$skill/SKILL.md")
done
for agent in "${universal_agents[@]}"; do
  template_sources+=(".claude/agents/$agent.md")
done
template_sources+=("${universal_extras[@]}")
template_sources+=("CLAUDE.md" "AGENTS.md")

for rel in "${template_sources[@]}"; do
  [[ -f "$template_root/$rel" ]] || fail "template file missing: $rel"
done

copy_file() {
  local src="$1" dest="$2" status
  if [[ -e "$dest" ]]; then status="updated"; else status="added"; fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  printf '%s' "$status"
}

append_line_if_missing() {
  local file="$1" line="$2"
  if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
    printf 'already present'
    return
  fi
  if [[ -f "$file" ]] && [[ -s "$file" ]] && [[ -n "$(tail -c 1 "$file")" ]]; then
    printf '\n' >>"$file"
  fi
  printf '%s\n' "$line" >>"$file"
  printf 'added'
}

format_summary_line() {
  printf '    %-56s (%s)\n' "$1" "$2"
}

mkdir -p "$repo_root/.claude/skills" "$repo_root/.claude/agents" "$repo_root/docs"

skill_summary=""
for skill in "${universal_skills[@]}"; do
  status="$(copy_file \
    "$template_root/.claude/skills/$skill/SKILL.md" \
    "$repo_root/.claude/skills/$skill/SKILL.md")"
  skill_summary+="$(format_summary_line ".claude/skills/$skill/SKILL.md" "$status")"$'\n'
done
docs_summary=""
for rel in "${universal_extras[@]}"; do
  status="$(copy_file "$template_root/$rel" "$repo_root/$rel")"
  line="$(format_summary_line "$rel" "$status")"$'\n'
  case "$rel" in
    docs/*) docs_summary+="$line" ;;
    *) skill_summary+="$line" ;;
  esac
done

agent_summary=""
for agent in "${universal_agents[@]}"; do
  status="$(copy_file \
    "$template_root/.claude/agents/$agent.md" \
    "$repo_root/.claude/agents/$agent.md")"
  agent_summary+="$(format_summary_line ".claude/agents/$agent.md" "$status")"$'\n'
done

gitignore_status="$(append_line_if_missing "$repo_root/.gitignore" ".jj/ws/")"

if [[ -f "$repo_root/CLAUDE.md" ]]; then
  claude_status="preserved existing"
else
  copy_file "$template_root/CLAUDE.md" "$repo_root/CLAUDE.md" >/dev/null
  claude_status="added skeleton"
fi

# AGENTS.md is overwritten in place between the bridge markers so the Codex bridge stays
# in sync with the template on every run — same contract as the universal skills. Only a
# legacy bridge (pre-markers) or a brand-new file take the copy/append paths.
agents_file="$repo_root/AGENTS.md"
begin_marker='<!-- BEGIN CLAUDE HARNESS CODEX BRIDGE -->'
end_marker='<!-- END CLAUDE HARNESS CODEX BRIDGE -->'
# The block file is read with awk getline rather than passed via -v: BSD awk (macOS)
# rejects a multi-line value in -v ("newline in string").
block_file="$(mktemp)"
trap 'rm -f "$block_file" "${tmp:-}"' EXIT
awk -v b="$begin_marker" -v e="$end_marker" '
  index($0, b) { f = 1 } f { print } index($0, e) { f = 0 }
' "$template_root/AGENTS.md" >"$block_file"
[[ -s "$block_file" ]] || fail "template AGENTS.md bridge block missing"

if [[ ! -f "$agents_file" ]]; then
  copy_file "$template_root/AGENTS.md" "$agents_file" >/dev/null
  agents_status="added skeleton"
elif grep -qF "$begin_marker" "$agents_file"; then
  grep -qF "$end_marker" "$agents_file" ||
    fail "AGENTS.md has a BEGIN bridge marker but no END marker; fix it by hand before re-running"
  tmp="$(mktemp)"
  awk -v b="$begin_marker" -v e="$end_marker" -v blockfile="$block_file" '
    index($0, b) { skip = 1; while ((getline line < blockfile) > 0) print line; close(blockfile); next }
    index($0, e) { skip = 0; next }
    !skip { print }
  ' "$agents_file" >"$tmp"
  mv "$tmp" "$agents_file"
  agents_status="synced bridge"
elif grep -Eq 'Claude Guidance Bridge|Claude Mirror' "$agents_file"; then
  agents_status="already bridged (legacy, left as-is)"
else
  { printf '\n'; cat "$block_file"; } >>"$agents_file"
  agents_status="appended Codex bridge"
fi

preserved_summary=""
if [[ -d "$repo_root/.claude/skills" ]]; then
  while IFS= read -r path; do
    name="$(basename "$path")"
    is_universal_skill "$name" || preserved_summary+="    .claude/skills/$name/"$'\n'
  done < <(find "$repo_root/.claude/skills" -mindepth 1 -maxdepth 1 -type d | sort)
fi
if [[ -d "$repo_root/.claude/agents" ]]; then
  while IFS= read -r path; do
    name="$(basename "$path")"; name="${name%.md}"
    is_universal_agent "$name" || preserved_summary+="    .claude/agents/$(basename "$path")"$'\n'
  done < <(find "$repo_root/.claude/agents" -mindepth 1 -maxdepth 1 -type f -name '*.md' | sort)
fi
[[ -n "$preserved_summary" ]] || preserved_summary="    (none)"$'\n'

cat <<EOF
Installed claude-harness from claude-harness-template into $repo_root

  Skills (universal, overwritten):
${skill_summary}  Agents (universal, overwritten):
${agent_summary}  Docs (universal, overwritten):
${docs_summary}  .gitignore: .jj/ws/ ($gitignore_status)

  CLAUDE.md: $claude_status
  AGENTS.md: $agents_status

  Preserved (project-specific, untouched):
${preserved_summary}
Next:
  - Fill the TODO markers in CLAUDE.md if a skeleton was added.
  - Codex reads AGENTS.md, which delegates back to CLAUDE.md and the .claude workflows.
  - Keep durable rules in CLAUDE.md, not AGENTS.md.
EOF
