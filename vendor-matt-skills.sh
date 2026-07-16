#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCKFILE="$HARNESS_SOURCE/skills-lock.json"
SKILLS_CLI="skills@1.5.15"
UPSTREAM="mattpocock/skills"
PREFIX="matt-"

# Upstream's engineering/ and productivity/ sets. Its in-progress/, personal/ and deprecated/
# skills are deliberately not vendored.
UPSTREAM_SKILLS=(
  ask-matt
  code-review
  codebase-design
  diagnosing-bugs
  domain-modeling
  grill-with-docs
  implement
  improve-codebase-architecture
  prototype
  research
  resolving-merge-conflicts
  setup-matt-pocock-skills
  tdd
  to-spec
  to-tickets
  triage
  wayfinder
  grill-me
  grilling
  handoff
  teach
  writing-great-skills
)

usage() {
  cat >&2 <<'EOF'
usage: vendor-matt-skills.sh [--update]

  (no flags)  Re-vendor the set pinned in skills-lock.json. Fails if upstream has moved
              away from the pinned content hashes.
  --update    Pull upstream's current content and repin skills-lock.json to it.
EOF
  exit 2
}

die() {
  printf 'vendor-matt-skills.sh: %s\n' "$1" >&2
  exit 1
}

fetch_upstream() {
  local into=$1 skill
  local args=()
  for skill in "${UPSTREAM_SKILLS[@]}"; do args+=(-s "$skill"); done
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$UPSTREAM" -a claude-code --copy -y "${args[@]}") >/dev/null ||
    die "the skills CLI failed to fetch $UPSTREAM"
}

# The prefix has to reach the frontmatter too: Claude Code invokes a skill by its declared
# `name`, not by its directory, so a directory rename alone would still register `/code-review`.
apply_prefix_to_frontmatter() {
  local skill_md=$1 name=$2
  awk -v want="name: $name" -v repl="name: $PREFIX$name" '
    NR == 1 { print; next }
    !closed && /^---$/ { closed = 1 }
    !closed && $0 == want { print repl; renamed = 1; next }
    { print }
    END { exit renamed ? 0 : 1 }
  ' "$skill_md" >"$skill_md.prefixed" ||
    die "$name: SKILL.md frontmatter declares no 'name: $name' to prefix"
  mv -- "$skill_md.prefixed" "$skill_md"
}

# The prefix has to reach the cross-references too: these skills dispatch to each other by slash
# name, so an unrewritten `/code-review` in a body reaches Claude Code's built-in rather than
# matt-code-review — the very collision the prefix exists to prevent. Only a reference is
# rewritten, never a path: the leading anchor skips `docs/agents/triage-labels.md`, the trailing
# one skips the route `/prototype/<name>`.
apply_prefix_to_references() {
  local skill_dir=$1 names
  names=$(
    IFS='|'
    printf '%s' "${UPSTREAM_SKILLS[*]}"
  )
  # shellcheck disable=SC2016 # $ENV{} is perl's, and must reach perl unexpanded
  find "$skill_dir" -type f -name '*.md' -exec \
    env NAMES="$names" PREFIX="$PREFIX" perl -pi \
    -e 's{(?<=[ `])/($ENV{NAMES})(?![\w/-])}{/$ENV{PREFIX}$1}g' {} + ||
    die "$skill_dir: rewriting cross-references failed"
}

lockfile_skills() {
  awk -F'"' '/^    "/ && /: \{$/ { print $2 }' "$1"
}

assert_pinned_set() {
  local fetched=$1 expected actual
  expected=$(printf '%s\n' "${UPSTREAM_SKILLS[@]}" | LC_ALL=C sort)
  actual=$(lockfile_skills "$fetched" | LC_ALL=C sort)
  [ "$expected" = "$actual" ] ||
    die "the skills CLI resolved a different set than this script asked for"
}

# Not local: the EXIT trap that cleans it up outlives main.
staging=""
trap 'rm -rf -- "$staging"' EXIT

main() {
  local update=false skill staged vendored

  case "${1-}" in
  "") ;;
  --update) update=true ;;
  *) usage ;;
  esac
  [ "$#" -le 1 ] || usage

  staging=$(mktemp -d)

  fetch_upstream "$staging"
  assert_pinned_set "$staging/skills-lock.json"

  if [ "$update" = false ]; then
    [ -f "$LOCKFILE" ] || die "no skills-lock.json to vendor from; run with --update to pin one"
    cmp -s -- "$LOCKFILE" "$staging/skills-lock.json" ||
      die "upstream has moved away from skills-lock.json; re-run with --update to repin"
  fi

  for skill in "${UPSTREAM_SKILLS[@]}"; do
    staged="$staging/.claude/skills/$skill"
    [ -d "$staged" ] || die "$skill: the skills CLI installed no such skill"
    apply_prefix_to_frontmatter "$staged/SKILL.md" "$skill"
    apply_prefix_to_references "$staged"
  done

  for vendored in "$HARNESS_SOURCE/skills/$PREFIX"*/; do
    if [ -d "$vendored" ]; then rm -rf -- "$vendored"; fi
  done

  for skill in "${UPSTREAM_SKILLS[@]}"; do
    mv -- "$staging/.claude/skills/$skill" "$HARNESS_SOURCE/skills/$PREFIX$skill"
  done

  cp -- "$staging/skills-lock.json" "$LOCKFILE"

  printf 'vendored %d skills from %s as %s*\n' "${#UPSTREAM_SKILLS[@]}" "$UPSTREAM" "$PREFIX"
}

# Sourceable so test/prefix-rewrite.sh can drive the transforms without going to the network.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
