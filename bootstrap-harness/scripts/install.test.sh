#!/usr/bin/env bash
# Smoke test for install.sh. No framework — run it directly:
#   bootstrap-harness/scripts/install.test.sh
# It creates throwaway git repos under a temp dir, runs the installer against them,
# and asserts the status strings, byte-for-byte file fidelity (cmp), idempotency,
# every AGENTS.md bridge path, and both fail-loud exits. Deterministic: no network,
# no clock, no randomness in the code under test.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer="$script_dir/install.sh"
template_root="$(cd "$script_dir/../.." && pwd)"
BEGIN='<!-- BEGIN CLAUDE HARNESS CODEX BRIDGE -->'

WORK="$(mktemp -d -t harness-test-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

assert_eq() { [[ "$1" == "$2" ]] && ok "$3" || bad "$3 (got '$1', want '$2')"; }
assert_contains() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing: $2)" ;; esac; }
assert_files_eq() { cmp -s "$1" "$2" && ok "$3" || bad "$3 (files differ)"; }
assert_grep() { grep -qF "$2" "$1" && ok "$3" || bad "$3 (not found in $1: $2)"; }
refute_grep() { grep -qF "$2" "$1" && bad "$3 (unexpectedly found: $2)" || ok "$3"; }

new_repo() {
  local d="$WORK/$1"
  mkdir -p "$d"
  git -C "$d" init -q
  printf '%s' "$d"
}

run() { # target -> sets OUT, RC (never aborts the test on a non-zero installer exit)
  set +e
  OUT="$(bash "$installer" "$1" 2>&1)"
  RC=$?
  set -e
}

echo "1. fresh repo"
r="$(new_repo fresh)"
run "$r"
assert_eq "$RC" "0" "fresh: exit 0"
assert_contains "$OUT" ".claude/skills/work/SKILL.md" "fresh: lists work skill"
assert_contains "$OUT" "(added)" "fresh: added status"
assert_contains "$OUT" "Docs (universal, overwritten):" "fresh: docs block header"
assert_contains "$OUT" "CLAUDE.md: added skeleton" "fresh: CLAUDE.md skeleton"
assert_contains "$OUT" "AGENTS.md: added skeleton" "fresh: AGENTS.md skeleton"
assert_files_eq "$r/.claude/skills/work/SKILL.md" \
  "$template_root/.claude/skills/work/SKILL.md" "fresh: work SKILL byte-equal"
assert_files_eq "$r/docs/PHILOSOPHY.md" \
  "$template_root/docs/PHILOSOPHY.md" "fresh: PHILOSOPHY (spine) byte-equal"
assert_files_eq "$r/docs/packs/web.md" \
  "$template_root/docs/packs/web.md" "fresh: web pack byte-equal"
assert_files_eq "$r/docs/packs/ai.md" \
  "$template_root/docs/packs/ai.md" "fresh: ai pack byte-equal"
assert_grep "$r/docs/packs/web.md" "Web / backend domain pack" "fresh: web pack has content"
assert_grep "$r/docs/packs/ai.md" "AI / LLM domain pack" "fresh: ai pack has content"
assert_grep "$r/.gitignore" ".jj/ws/" "fresh: .gitignore has .jj/ws/"

echo "2. idempotent re-run"
run "$r"
assert_eq "$RC" "0" "rerun: exit 0"
assert_contains "$OUT" "(updated)" "rerun: updated status"
assert_contains "$OUT" "CLAUDE.md: preserved existing" "rerun: CLAUDE.md preserved"
assert_contains "$OUT" "AGENTS.md: synced bridge" "rerun: bridge synced"
assert_eq "$(grep -cxF '.jj/ws/' "$r/.gitignore")" "1" "rerun: .jj/ws/ appears once"
assert_eq "$(grep -cF "$BEGIN" "$r/AGENTS.md")" "1" "rerun: one BEGIN marker"
assert_files_eq "$r/docs/packs/web.md" \
  "$template_root/docs/packs/web.md" "rerun: web pack overwritten byte-equal"

echo "3. bridge re-sync fidelity"
r3="$(new_repo resync)"
{
  printf '# AGENTS.md\n\nMy preamble keep-me.\n\n'
  printf '%s\n' "$BEGIN"
  printf 'STALE bridge content\n'
  printf '<!-- END CLAUDE HARNESS CODEX BRIDGE -->\n'
} >"$r3/AGENTS.md"
run "$r3"
assert_contains "$OUT" "AGENTS.md: synced bridge" "resync: synced"
assert_grep "$r3/AGENTS.md" "My preamble keep-me." "resync: preamble kept"
refute_grep "$r3/AGENTS.md" "STALE bridge content" "resync: stale content replaced"
awk '/BEGIN CLAUDE HARNESS/{f=1} f{print} /<!-- END CLAUDE HARNESS/{f=0}' \
  "$r3/AGENTS.md" >"$WORK/got.block"
awk '/BEGIN CLAUDE HARNESS/{f=1} f{print} /<!-- END CLAUDE HARNESS/{f=0}' \
  "$template_root/AGENTS.md" >"$WORK/want.block"
assert_files_eq "$WORK/got.block" "$WORK/want.block" "resync: block matches template"

echo "4. un-bridged AGENTS.md"
r4="$(new_repo unbridged)"
printf '# AGENTS.md\n\nOnly my own rules.\n' >"$r4/AGENTS.md"
run "$r4"
assert_contains "$OUT" "AGENTS.md: appended Codex bridge" "append: status"
assert_grep "$r4/AGENTS.md" "Only my own rules." "append: own rules kept"
assert_eq "$(grep -cF "$BEGIN" "$r4/AGENTS.md")" "1" "append: one BEGIN marker"

echo "5. legacy bridge left as-is"
r5="$(new_repo legacy)"
printf '# AGENTS.md\n\n## Claude Guidance Bridge\n\nlegacy stuff\n' >"$r5/AGENTS.md"
cp "$r5/AGENTS.md" "$WORK/legacy.pre"
run "$r5"
assert_contains "$OUT" "already bridged (legacy" "legacy: status"
assert_files_eq "$r5/AGENTS.md" "$WORK/legacy.pre" "legacy: file unchanged"

echo "6. preserve-detection"
r6="$(new_repo preserve)"
mkdir -p "$r6/.claude/skills/run-evals" "$r6/.claude/agents"
printf 'project skill\n' >"$r6/.claude/skills/run-evals/SKILL.md"
cp "$r6/.claude/skills/run-evals/SKILL.md" "$WORK/runevals.pre"
printf 'project agent\n' >"$r6/.claude/agents/payments-reviewer.md"
run "$r6"
assert_contains "$OUT" ".claude/skills/run-evals/" "preserve: lists run-evals"
assert_contains "$OUT" ".claude/agents/payments-reviewer.md" "preserve: lists payments-reviewer"
assert_files_eq "$r6/.claude/skills/run-evals/SKILL.md" \
  "$WORK/runevals.pre" "preserve: run-evals untouched"

echo "7. non-git target fails loud"
d7="$WORK/nogit"
mkdir -p "$d7"
run "$d7"
assert_eq "$RC" "1" "non-git: exit 1"
assert_contains "$OUT" "must be inside a git repo" "non-git: message"

echo "8. missing template source fails loud, no partial write"
fake="$WORK/faketemplate"
mkdir -p "$fake"
cp -R "$template_root/.claude" "$template_root/docs" "$template_root/bootstrap-harness" "$fake/"
cp "$template_root/CLAUDE.md" "$template_root/AGENTS.md" "$fake/"
rm "$fake/docs/packs/web.md"
r8="$(new_repo missingsrc)"
set +e
OUT="$(bash "$fake/bootstrap-harness/scripts/install.sh" "$r8" 2>&1)"
RC=$?
set -e
assert_eq "$RC" "1" "missing-source: exit 1"
assert_contains "$OUT" "template file missing: docs/packs/web.md" "missing-source: names the missing pack"
[[ ! -e "$r8/.claude" ]] && ok "missing-source: no partial write" || bad "missing-source: wrote files before failing"

echo "9. unbalanced bridge marker fails loud, content preserved"
r9="$(new_repo unbalanced)"
printf '# AGENTS.md\n\n%s\ncustom keep-me\n' "$BEGIN" >"$r9/AGENTS.md"
cp "$r9/AGENTS.md" "$WORK/unbal.pre"
run "$r9"
assert_eq "$RC" "1" "unbalanced: exit 1"
assert_contains "$OUT" "no END marker" "unbalanced: message"
assert_files_eq "$r9/AGENTS.md" "$WORK/unbal.pre" "unbalanced: AGENTS.md unchanged"

echo
printf 'install.test.sh: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
