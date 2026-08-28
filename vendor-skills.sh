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

# The third upstream, and the one that keeps its upstream name. `railway skills install` writes
# `use-railway` into ~/.agents/skills and every tool dir it detects, ~/.claude/skills included, so
# the name is an interop surface with another installer rather than a label this harness chooses.
# Vendor it as `railway-use-railway` and the CLI goes on writing plain `use-railway` for the
# harness to purge: the ping-pong survives and there are now two skills. See README's
# "use-railway, the skill that cannot take a prefix".
#
# Not a special case in the rewrite so much as absent from the set it runs over: the prefix loop
# walks UPSTREAM_SKILLS, and this skill is not in it. test/prefix-rewrite.sh pins that rather than
# trusting it.
RAILWAY_UPSTREAM="railwayapp/railway-skills"
RAILWAY_SKILL="use-railway"
RAILWAY_LICENSE_URL="https://raw.githubusercontent.com/$RAILWAY_UPSTREAM/HEAD/LICENSE"

# Plannotator's installer writes these names into roots the harness purges. Vendor the complete
# published set so a harness install remains authoritative instead of deleting the integration.
PLANNOTATOR_UPSTREAM="backnotprop/plannotator"
PLANNOTATOR_CORE_SOURCE="https://github.com/$PLANNOTATOR_UPSTREAM/tree/main/apps/skills/core"
PLANNOTATOR_EXTRA_SOURCE="https://github.com/$PLANNOTATOR_UPSTREAM/tree/main/apps/skills/extra"
PLANNOTATOR_LICENSE_URL="https://raw.githubusercontent.com/$PLANNOTATOR_UPSTREAM/HEAD/LICENSE-MIT"
PLANNOTATOR_SKILLS=(
  plannotator-annotate
  plannotator-last
  plannotator-review
  plannotator-compound
  plannotator-setup-goal
  plannotator-visual-explainer
)

# plannotator-visual-explainer delegates general-purpose output to this upstream skill.
VISUAL_EXPLAINER_UPSTREAM="nicobailon/visual-explainer"
VISUAL_EXPLAINER_SKILL="visual-explainer"
VISUAL_EXPLAINER_LICENSE_URL="https://raw.githubusercontent.com/$VISUAL_EXPLAINER_UPSTREAM/HEAD/LICENSE"

# pstack (Lauren Tan's, MIT) is a hand-maintained fork, not a CLI-fetched vendor. Its Cursor coupling
# is translated by hand for the harness runtimes, so a re-vendor cannot re-derive it the way the
# matt- prefix rewrite re-derives Matt's set. The skills CLI never touches it. What the lockfile
# carries for pstack is a pristine-upstream content hash per skill, so `--check-pstack-drift` can
# flag when upstream has moved and the fork needs a manual reconcile. Every other path preserves
# the pstack pins already in skills-lock.json rather than recomputing or dropping them.
PSTACK_UPSTREAM="cursor/plugins"

# The four Matt skills the harness still vendors after the pstack migration. pstack-poteto-mode is
# the router and its playbooks and pstack-principle-* leaves cover the flow Matt's other skills used
# to, so the rest are retired. `code-review` stays as the standards and spec review;
# `codebase-design` for its deep-module vocabulary; `diagnosing-bugs` for reproduce-before-you-touch;
# `handoff` for compaction.
UPSTREAM_SKILLS=(
  code-review
  codebase-design
  diagnosing-bugs
  handoff
)

usage() {
  cat >&2 <<'EOF'
usage: vendor-skills.sh [--update | --update-plannotator | --regen-patch | --check-pstack-drift]

  (no flags)            Re-vendor the set pinned in skills-lock.json. Fails if upstream has moved
                        away from the pinned content hashes. Carries the pstack pins through
                        unchanged; the skills CLI does not fetch pstack.
  --update              Pull every CLI-fetched upstream's current content and repin
                        skills-lock.json to it. Preserves the hand-maintained pstack pins.
  --update-plannotator  Pull Plannotator and visual-explainer without changing the other pins.
  --regen-patch         Rebuild patches/lazar-tldraw.patch from the difference between pristine
                        upstream and the vendored skills/lazar-tldraw/SKILL.md. Run this after
                        editing that file to keep a local change across the next re-vendor.
  --check-pstack-drift  Fetch each pinned pstack skill's pristine upstream and compare its hash to
                        skills-lock.json. Reports which skills upstream has changed under the fork,
                        so the divergence is reconciled by hand rather than discovered by accident.
EOF
  exit 2
}

die() {
  printf 'vendor-skills.sh: %s\n' "$1" >&2
  exit 1
}

fetch_plannotator_upstreams() {
  local into=$1 skill visual_into
  local plannotator_core_args=() plannotator_extra_args=()

  for skill in "${PLANNOTATOR_SKILLS[@]:0:3}"; do plannotator_core_args+=(-s "$skill"); done
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$PLANNOTATOR_CORE_SOURCE" -a claude-code --copy -y "${plannotator_core_args[@]}") >/dev/null ||
    die "the skills CLI failed to fetch Plannotator's core skills"
  for skill in "${PLANNOTATOR_SKILLS[@]:3}"; do plannotator_extra_args+=(-s "$skill"); done
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$PLANNOTATOR_EXTRA_SOURCE" -a claude-code --copy -y "${plannotator_extra_args[@]}") >/dev/null ||
    die "the skills CLI failed to fetch Plannotator's extra skills"

  visual_into="$into/visual-explainer-upstream"
  mkdir -p -- "$visual_into"
  (cd -- "$visual_into" && npx -y "$SKILLS_CLI" add "$VISUAL_EXPLAINER_UPSTREAM" -a claude-code --copy -y -s "$VISUAL_EXPLAINER_SKILL") >/dev/null ||
    die "the skills CLI failed to fetch $VISUAL_EXPLAINER_UPSTREAM"
  jq -s '.[0].skills += .[1].skills | .[0]' \
    "$into/skills-lock.json" "$visual_into/skills-lock.json" >"$into/skills-lock.merged.json" ||
    die "merging $VISUAL_EXPLAINER_SKILL into skills-lock.json failed"
  mv -- "$into/skills-lock.merged.json" "$into/skills-lock.json"
  mv -- "$visual_into/.claude/skills/$VISUAL_EXPLAINER_SKILL" "$into/.claude/skills/"
  rm -rf -- "$visual_into"
}

# Every upstream contributes to one final lockfile. The larger optional sets are fetched in an
# independent directory because skills@1.5.15 silently drops existing lock entries when too many
# independent upstreams are merged in one working directory.
fetch_upstream() {
  local into=$1 skill plannotator_into
  local args=()
  for skill in "${UPSTREAM_SKILLS[@]}"; do args+=(-s "$skill"); done
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$UPSTREAM" -a claude-code --copy -y "${args[@]}") >/dev/null ||
    die "the skills CLI failed to fetch $UPSTREAM"
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$TLDRAW_UPSTREAM" -a claude-code --copy -y -s "$TLDRAW_SKILL") >/dev/null ||
    die "the skills CLI failed to fetch $TLDRAW_UPSTREAM"
  (cd -- "$into" && npx -y "$SKILLS_CLI" add "$RAILWAY_UPSTREAM" -a claude-code --copy -y -s "$RAILWAY_SKILL") >/dev/null ||
    die "the skills CLI failed to fetch $RAILWAY_UPSTREAM"

  plannotator_into="$into/plannotator-upstream"
  mkdir -p -- "$plannotator_into"
  fetch_plannotator_upstreams "$plannotator_into"
  jq -s '.[0].skills += .[1].skills | .[0]' \
    "$into/skills-lock.json" "$plannotator_into/skills-lock.json" \
    >"$into/skills-lock.merged.json" ||
    die "merging Plannotator into skills-lock.json failed"
  mv -- "$into/skills-lock.merged.json" "$into/skills-lock.json"
  for skill in "${PLANNOTATOR_SKILLS[@]}" "$VISUAL_EXPLAINER_SKILL"; do
    mv -- "$plannotator_into/.claude/skills/$skill" "$into/.claude/skills/"
  done
  rm -rf -- "$plannotator_into"
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

# Upstream locks most of its skills to hand-typed invocation with `disable-model-invocation: true`.
# That guards against an agent spontaneously firing an expensive workflow, but it also makes the
# skills unreachable from a spoken brain-dump: the agent can name the slash command it would have
# run and nothing more. The four Matt skills the harness keeps are reached from the flow rather than
# hand-typed, so the strip lets `pstack-poteto-mode` route to them without the human typing a slash.
#
# Stripping the line here rather than in a patch keeps it stable across upstream edits near the
# frontmatter, which the patch tool would refuse to fuzz through.
strip_model_invocation_lock() {
  local skill_md=$1
  awk '
    NR == 1 { print; next }
    !closed && /^---$/ { closed = 1 }
    !closed && /^disable-model-invocation:[[:space:]]*true[[:space:]]*$/ { next }
    { print }
  ' "$skill_md" >"$skill_md.unlocked" ||
    die "$skill_md: stripping disable-model-invocation failed"
  mv -- "$skill_md.unlocked" "$skill_md"
}

# The prefix has to reach the cross-references too: these skills dispatch to each other by slash
# name, so an unrewritten `/code-review` in a body reaches Claude Code's built-in rather than
# matt-code-review — the very collision the prefix exists to prevent. Only a reference is
# rewritten, never a path: the leading anchor skips `docs/agents/handoff-labels.md`, the trailing
# one skips the route `/code-review/<name>`.
#
# Every file, not just markdown: a skill that ships a `template.sh` naming a slash command needs it
# too, and `test/install-smoke.sh` pins that no installed skill dispatches to an unprefixed name.
apply_prefix_to_references() {
  local skill_dir=$1 names
  names=$(
    IFS='|'
    printf '%s' "${UPSTREAM_SKILLS[*]}"
  )
  # shellcheck disable=SC2016 # $ENV{} is perl's, and must reach perl unexpanded
  find "$skill_dir" -type f -exec \
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
  local into=$1 url=$2 upstream=$3
  curl -fsSL -o "$into/LICENSE" -- "$url" ||
    die "could not fetch $upstream's LICENSE from $url"
  [ -s "$into/LICENSE" ] || die "$upstream's LICENSE came back empty"
}

lockfile_skills() {
  awk -F'"' '/^    "/ && /: \{$/ { print $2 }' "$1"
}

assert_pinned_set() {
  local fetched=$1 expected actual
  expected=$(printf '%s\n%s\n%s\n%s\n%s\n' "${UPSTREAM_SKILLS[*]}" "$TLDRAW_SKILL" \
    "$RAILWAY_SKILL" "${PLANNOTATOR_SKILLS[*]}" "$VISUAL_EXPLAINER_SKILL" |
    tr ' ' '\n' | LC_ALL=C sort)
  actual=$(lockfile_skills "$fetched" | LC_ALL=C sort)
  [ "$expected" = "$actual" ] ||
    die "the skills CLI resolved a different set than this script asked for
expected:
$expected
actual:
$actual"
}

assert_plannotator_pinned_set() {
  local fetched=$1 expected actual
  expected=$(printf '%s\n%s\n' "${PLANNOTATOR_SKILLS[*]}" "$VISUAL_EXPLAINER_SKILL" |
    tr ' ' '\n' | LC_ALL=C sort)
  actual=$(lockfile_skills "$fetched" | LC_ALL=C sort)
  [ "$expected" = "$actual" ] ||
    die "the skills CLI resolved a different Plannotator set than this script asked for"
}

stage_plannotator_licenses() {
  local into=$1 skill first_staged
  first_staged="$into/.claude/skills/${PLANNOTATOR_SKILLS[0]}"
  fetch_license "$first_staged" "$PLANNOTATOR_LICENSE_URL" "$PLANNOTATOR_UPSTREAM"
  for skill in "${PLANNOTATOR_SKILLS[@]:1}"; do
    cp -- "$first_staged/LICENSE" "$into/.claude/skills/$skill/LICENSE"
  done
  fetch_license "$into/.claude/skills/$VISUAL_EXPLAINER_SKILL" \
    "$VISUAL_EXPLAINER_LICENSE_URL" "$VISUAL_EXPLAINER_UPSTREAM"
}

install_plannotator_skills() {
  local from=$1 skill
  for skill in "${PLANNOTATOR_SKILLS[@]}" "$VISUAL_EXPLAINER_SKILL"; do
    rm -rf -- "$HARNESS_SOURCE/skills/$skill"
    mv -- "$from/.claude/skills/$skill" "$HARNESS_SOURCE/skills/$skill"
  done
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

# pstack is hand-maintained, so drift is a fetch-and-compare against the stored pristine hash rather
# than something a re-vendor would surface. A mismatch means upstream moved under the fork and the
# translation has to be reconciled by hand; it never rewrites the vendored skills.
check_pstack_drift() {
  [ -f "$LOCKFILE" ] || die "no skills-lock.json to check pstack drift against"
  local drift=0 key path stored fresh
  while IFS=$'\t' read -r key path stored; do
    fresh=$(curl -fsSL "https://raw.githubusercontent.com/$PSTACK_UPSTREAM/HEAD/$path" |
      shasum -a 256 | awk '{print $1}') ||
      { printf 'pstack: could not fetch %s\n' "$path" >&2; drift=1; continue; }
    if [ "$fresh" = "$stored" ]; then
      printf 'ok    %s\n' "$key"
    else
      printf 'DRIFT %s  (%s changed upstream; reconcile the fork by hand)\n' "$key" "$path"
      drift=1
    fi
  done < <(jq -r '.skills | to_entries[]
    | select(.value.source == "cursor/plugins")
    | [.key, .value.skillPath, .value.computedHash] | @tsv' "$LOCKFILE")
  [ "$drift" -eq 0 ] &&
    printf 'pstack: no drift, the fork is current with upstream\n' ||
    die "pstack: upstream drift detected above"
}

main() {
  local update=false update_plannotator=false regen=false check_drift=false skill staged vendored
  local tldraw_staged railway_staged visual_explainer_staged

  case "${1-}" in
  "") ;;
  --update) update=true ;;
  --update-plannotator) update_plannotator=true ;;
  --regen-patch) regen=true ;;
  --check-pstack-drift) check_drift=true ;;
  *) usage ;;
  esac
  [ "$#" -le 1 ] || usage

  if [ "$check_drift" = true ]; then
    check_pstack_drift
    return 0
  fi

  staging=$(mktemp -d)

  if [ "$update_plannotator" = true ]; then
    fetch_plannotator_upstreams "$staging"
    assert_plannotator_pinned_set "$staging/skills-lock.json"
    stage_plannotator_licenses "$staging"
    jq --slurpfile updated "$staging/skills-lock.json" '
      .skills |= with_entries(select(
        .value.source != "backnotprop/plannotator" and
        .value.source != "nicobailon/visual-explainer"
      )) |
      .skills += $updated[0].skills
    ' "$LOCKFILE" >"$staging/skills-lock.combined.json" ||
      die "merging Plannotator pins into $LOCKFILE failed"
    install_plannotator_skills "$staging"
    mv -- "$staging/skills-lock.combined.json" "$LOCKFILE"
    printf 'vendored %d skills from %s and %s from %s\n' \
      "${#PLANNOTATOR_SKILLS[@]}" "$PLANNOTATOR_UPSTREAM" \
      "$VISUAL_EXPLAINER_SKILL" "$VISUAL_EXPLAINER_UPSTREAM"
    return 0
  fi

  fetch_upstream "$staging"
  assert_pinned_set "$staging/skills-lock.json"

  # The skills CLI does not fetch pstack, so its staged lock has none of the cursor/plugins pins.
  # Carry them across from the committed lock so the cmp gate below matches and the final write
  # keeps them. Without this, every re-vendor would drop the whole pstack pin set on the floor.
  if [ -f "$LOCKFILE" ]; then
    jq --slurpfile lock "$LOCKFILE" '
      .skills += ($lock[0].skills | with_entries(select(.value.source == "cursor/plugins")))
    ' "$staging/skills-lock.json" >"$staging/skills-lock.pstack.json" ||
      die "carrying the pstack pins into the staged lock failed"
    mv -- "$staging/skills-lock.pstack.json" "$staging/skills-lock.json"
  fi

  tldraw_staged="$staging/.claude/skills/$TLDRAW_SKILL"
  [ -d "$tldraw_staged" ] || die "$TLDRAW_SKILL: the skills CLI installed no such skill"

  railway_staged="$staging/.claude/skills/$RAILWAY_SKILL"
  [ -d "$railway_staged" ] || die "$RAILWAY_SKILL: the skills CLI installed no such skill"

  for skill in "${PLANNOTATOR_SKILLS[@]}"; do
    [ -d "$staging/.claude/skills/$skill" ] ||
      die "$skill: the skills CLI installed no such skill"
  done

  visual_explainer_staged="$staging/.claude/skills/$VISUAL_EXPLAINER_SKILL"
  [ -d "$visual_explainer_staged" ] ||
    die "$VISUAL_EXPLAINER_SKILL: the skills CLI installed no such skill"

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
    strip_model_invocation_lock "$staged/SKILL.md"
    apply_prefix_to_references "$staged"
  done

  # Before anything is removed, so a rejected patch leaves the last good vendor in place.
  apply_local_patch "$tldraw_staged"
  fetch_license "$tldraw_staged" "$TLDRAW_LICENSE_URL" "$TLDRAW_UPSTREAM"
  fetch_license "$railway_staged" "$RAILWAY_LICENSE_URL" "$RAILWAY_UPSTREAM"
  stage_plannotator_licenses "$staging"

  for vendored in "$HARNESS_SOURCE/skills/$PREFIX"*/; do
    if [ -d "$vendored" ]; then rm -rf -- "$vendored"; fi
  done
  rm -rf -- "$HARNESS_SOURCE/skills/$TLDRAW_VENDORED" "$HARNESS_SOURCE/skills/$RAILWAY_SKILL" \
    "$HARNESS_SOURCE/skills/$VISUAL_EXPLAINER_SKILL"

  for skill in "${UPSTREAM_SKILLS[@]}"; do
    mv -- "$staging/.claude/skills/$skill" "$HARNESS_SOURCE/skills/$PREFIX$skill"
  done
  mv -- "$tldraw_staged" "$HARNESS_SOURCE/skills/$TLDRAW_VENDORED"
  mv -- "$railway_staged" "$HARNESS_SOURCE/skills/$RAILWAY_SKILL"
  install_plannotator_skills "$staging"

  cp -- "$staging/skills-lock.json" "$LOCKFILE"

  printf 'vendored %d skills from %s as %s*, %s from %s, %s from %s, %d from %s, and %s from %s\n' \
    "${#UPSTREAM_SKILLS[@]}" "$UPSTREAM" "$PREFIX" "$TLDRAW_VENDORED" "$TLDRAW_UPSTREAM" \
    "$RAILWAY_SKILL" "$RAILWAY_UPSTREAM" "${#PLANNOTATOR_SKILLS[@]}" \
    "$PLANNOTATOR_UPSTREAM" "$VISUAL_EXPLAINER_SKILL" "$VISUAL_EXPLAINER_UPSTREAM"
}

# Sourceable so the tests can drive the transforms without going to the network.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
