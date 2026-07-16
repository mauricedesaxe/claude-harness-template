#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCKFILE="$HARNESS_SOURCE/skills-lock.json"
SKILLS_CLI="skills@1.5.15"
UPSTREAM="mattpocock/skills"
PREFIX="matt-"

# The second upstream. It is vendored as `lazar-` rather than `agents365-` because it does not
# ship as-is: `patches/lazar-tldraw.patch` re-applies local divergence on top of it (see
# `apply_local_patch`).
TLDRAW_UPSTREAM="Agents365-ai/tldraw-skill"
TLDRAW_SKILL="tldraw-skill"
TLDRAW_VENDORED="lazar-tldraw"
TLDRAW_PATCH="$HARNESS_SOURCE/patches/lazar-tldraw.patch"
# The skills CLI installs SKILL.md alone, so the MIT licence the vendored text is used under does
# not come with it. Fetching it here keeps it beside the code it licenses.
TLDRAW_LICENSE_URL="https://raw.githubusercontent.com/$TLDRAW_UPSTREAM/HEAD/LICENSE"

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
usage: vendor-skills.sh [--update | --regen-patch]

  (no flags)      Re-vendor the set pinned in skills-lock.json. Fails if upstream has moved
                  away from the pinned content hashes.
  --update        Pull upstream's current content and repin skills-lock.json to it.
  --regen-patch   Rebuild patches/lazar-tldraw.patch from the difference between pristine
                  upstream and the vendored skills/lazar-tldraw/SKILL.md. Run this after
                  editing that file to keep a local change across the next re-vendor.
EOF
  exit 2
}

die() {
  printf 'vendor-skills.sh: %s\n' "$1" >&2
  exit 1
}

# Both upstreams are fetched into one staging dir so the CLI merges them into a single lockfile.
fetch_upstream() {
  local into=$1 skill
  local args=()
  for skill in "${UPSTREAM_SKILLS[@]}"; do args+=(-s "$skill"); done
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$UPSTREAM" -a claude-code --copy -y "${args[@]}") >/dev/null ||
    die "the skills CLI failed to fetch $UPSTREAM"
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$TLDRAW_UPSTREAM" -a claude-code --copy -y -s "$TLDRAW_SKILL") >/dev/null ||
    die "the skills CLI failed to fetch $TLDRAW_UPSTREAM"
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

# Unlike Matt's set, this skill's divergence from upstream is prose — new presets, wider triggers,
# and the sizing/spacing rules that keep diagrams readable. None of it is derivable by a rewrite
# rule, so it lives in a patch that is re-applied here on every run. `git apply` matches context
# exactly and refuses to fuzz, so an upstream edit that touches a patched region stops the vendor
# with a conflict rather than quietly dropping the local change on the floor.
apply_local_patch() {
  local skill_dir=$1
  [ -f "$TLDRAW_PATCH" ] || die "$TLDRAW_PATCH: no local patch to apply"
  (cd -- "$skill_dir" && git apply -p1 -- "$TLDRAW_PATCH") ||
    die "$TLDRAW_PATCH no longer applies to $TLDRAW_UPSTREAM. Upstream has changed under a
patched region. Reconcile the patch by hand against the new upstream, then re-run.
Nothing has been written, so skills/$TLDRAW_VENDORED still holds the last good vendor."
}

fetch_license() {
  local into=$1
  curl -fsSL -o "$into/LICENSE" -- "$TLDRAW_LICENSE_URL" ||
    die "could not fetch $TLDRAW_UPSTREAM's LICENSE from $TLDRAW_LICENSE_URL"
  [ -s "$into/LICENSE" ] || die "$TLDRAW_UPSTREAM's LICENSE came back empty"
}

lockfile_skills() {
  awk -F'"' '/^    "/ && /: \{$/ { print $2 }' "$1"
}

assert_pinned_set() {
  local fetched=$1 expected actual
  expected=$(printf '%s\n%s\n' "${UPSTREAM_SKILLS[*]}" "$TLDRAW_SKILL" | tr ' ' '\n' | LC_ALL=C sort)
  actual=$(lockfile_skills "$fetched" | LC_ALL=C sort)
  [ "$expected" = "$actual" ] ||
    die "the skills CLI resolved a different set than this script asked for"
}

# Not local: the EXIT trap that cleans it up outlives main.
staging=""
trap 'rm -rf -- "$staging"' EXIT

# The vendored file is generated, so the patch is what has to carry a local change for it to
# survive the next run. Deriving the patch from an edited vendored file, rather than asking anyone
# to write patch hunks by hand, is what keeps that affordable.
regen_patch() {
  local pristine=$1 vendored="$HARNESS_SOURCE/skills/$TLDRAW_VENDORED/SKILL.md" work status=0
  [ -f "$vendored" ] || die "$vendored: nothing vendored to regenerate a patch from"
  work=$(mktemp -d)
  mkdir -p -- "$work/a" "$work/b"
  cp -- "$pristine" "$work/a/SKILL.md"
  cp -- "$vendored" "$work/b/SKILL.md"
  # diff exits 1 for "files differ", which is the whole point here, and 2 for a real error. Only
  # the latter is a failure, so its status is taken by hand rather than left to `set -e`.
  (cd -- "$work" && diff -u --label a/SKILL.md --label b/SKILL.md a/SKILL.md b/SKILL.md) \
    >"$work/local.patch" || status=$?
  [ "$status" -le 1 ] || die "diffing $TLDRAW_VENDORED against upstream failed"
  [ -s "$work/local.patch" ] ||
    die "$TLDRAW_VENDORED is identical to upstream, so there is no local patch to keep"
  mv -- "$work/local.patch" "$TLDRAW_PATCH"
  rm -rf -- "$work"
  printf 'regenerated %s\n' "${TLDRAW_PATCH#"$HARNESS_SOURCE"/}"
}

main() {
  local update=false regen=false skill staged vendored tldraw_staged

  case "${1-}" in
  "") ;;
  --update) update=true ;;
  --regen-patch) regen=true ;;
  *) usage ;;
  esac
  [ "$#" -le 1 ] || usage

  staging=$(mktemp -d)

  fetch_upstream "$staging"
  assert_pinned_set "$staging/skills-lock.json"

  tldraw_staged="$staging/.claude/skills/$TLDRAW_SKILL"
  [ -d "$tldraw_staged" ] || die "$TLDRAW_SKILL: the skills CLI installed no such skill"

  if [ "$regen" = true ]; then
    regen_patch "$tldraw_staged/SKILL.md"
    return 0
  fi

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

  # Before anything is removed, so a rejected patch leaves the last good vendor in place.
  apply_local_patch "$tldraw_staged"
  fetch_license "$tldraw_staged"

  for vendored in "$HARNESS_SOURCE/skills/$PREFIX"*/; do
    if [ -d "$vendored" ]; then rm -rf -- "$vendored"; fi
  done
  rm -rf -- "$HARNESS_SOURCE/skills/$TLDRAW_VENDORED"

  for skill in "${UPSTREAM_SKILLS[@]}"; do
    mv -- "$staging/.claude/skills/$skill" "$HARNESS_SOURCE/skills/$PREFIX$skill"
  done
  mv -- "$tldraw_staged" "$HARNESS_SOURCE/skills/$TLDRAW_VENDORED"

  cp -- "$staging/skills-lock.json" "$LOCKFILE"

  printf 'vendored %d skills from %s as %s*, and %s from %s\n' \
    "${#UPSTREAM_SKILLS[@]}" "$UPSTREAM" "$PREFIX" "$TLDRAW_VENDORED" "$TLDRAW_UPSTREAM"
}

# Sourceable so the tests can drive the transforms without going to the network.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
