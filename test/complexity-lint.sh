#!/usr/bin/env bash
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$HARNESS_SOURCE/bin/complexity-lint"
TMP=$(mktemp -d)
failures=0
trap 'rm -rf -- "$TMP"' EXIT

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }

make_tools() {
  local root=$1
  mkdir -p "$root/node_modules/.bin" "$root/.venv/bin"
  cat >"$root/node_modules/.bin/oxlint" <<'SCRIPT'
#!/usr/bin/env bash
file=""
for arg in "$@"; do
  case "$arg" in *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts) file=$arg ;; esac
done
[ -n "$file" ] || { printf '[]'; exit 0; }
args=$(printf '%s\n' "$@")
grep -qx -- '--disable-nested-config' <<<"$args" || exit 2
grep -qx -- '--no-ignore' <<<"$args" || exit 2
grep -qx -- '--format' <<<"$args" || exit 2
grep -qx -- 'json' <<<"$args" || exit 2
config=""
previous=""
for arg in "$@"; do
  [ "$previous" = "--config" ] && config=$arg
  previous=$arg
done
grep -q '"max":10' "$config" || exit 2
grep -q '"variant":"classic"' "$config" || exit 2
case "$(<"$file")" in
  *MALFORMED*) printf 'not-json'; exit 1 ;;
  *PROCESS_FAIL*) exit 2 ;;
  *RULE_UNAVAILABLE*) printf '{"diagnostics":[{"code":"eslint(other-rule)"}]}'; exit 1 ;;
esac
score=$(grep -Eo 'complexityScore = [0-9]+' "$file" | grep -Eo '[0-9]+' || true)
[ -n "$score" ] || { printf '[]'; exit 0; }
printf '{"diagnostics":[{"code":"eslint(complexity)","message":"Function foo has a complexity of %s. Maximum allowed is 10.","filename":"%s","labels":[{"span":{"line":3,"column":1}}]}]}' "$score" "$file"
exit 1
SCRIPT
  cat >"$root/.venv/bin/ruff" <<'SCRIPT'
#!/usr/bin/env bash
file=""
for arg in "$@"; do
  case "$arg" in *.py|*.pyi) file=$arg ;; esac
done
[ -n "$file" ] || { printf '[]'; exit 0; }
args=$(printf '%s\n' "$@")
for required in check --isolated --select C901 --output-format json --config \
  'lint.mccabe.max-complexity = 10'; do
  grep -qx -- "$required" <<<"$args" || exit 2
done
case "$(<"$file")" in *MALFORMED*) printf 'not-json'; exit 1 ;; esac
score=$(grep -Eo 'complexity_score = [0-9]+' "$file" | grep -Eo '[0-9]+' || true)
[ -n "$score" ] || { printf '[]'; exit 0; }
printf '[{"code":"C901","filename":"%s","location":{"row":4,"column":1},"message":"foo is too complex (%s > 10)"}]' "$file" "$score"
exit 1
SCRIPT
  chmod +x "$root/node_modules/.bin/oxlint" "$root/.venv/bin/ruff"
}

diff_for() {
  printf '%s\n' 'diff --git a/'"$1"' b/'"$1" '--- a/'"$1" '+++ b/'"$1" '@@ -0,0 +1 @@' '+changed'
}

run_lint() {
  local root=$1 diff=$2
  (cd "$root" && printf '%s' "$diff" | "$LINT") 2>&1
}

assert_status_and_text() {
  local what=$1 want_status=$2 needle=$3 root=$4 diff=$5 out status
  out=$(run_lint "$root" "$diff")
  status=$?
  if [ "$status" -eq "$want_status" ] && [[ "$out" == *"$needle"* ]]; then
    pass "$what"
  else
    fail "$what (status=$status output='$out')"
  fi
}

repo="$TMP/repo"
mkdir -p "$repo/src"
make_tools "$repo"

printf 'export const complexityScore = 11;\n' >"$repo/src/advisory.ts"
assert_status_and_text "Oxlint score 11 is advisory" 0 \
  "advisory: oxlint src/advisory.ts:3 score 11" "$repo" "$(diff_for src/advisory.ts)"

printf 'export const complexityScore = 20;\n' >"$repo/src/twenty.ts"
assert_status_and_text "Oxlint score 20 is advisory" 0 \
  "advisory: oxlint src/twenty.ts:3 score 20" "$repo" "$(diff_for src/twenty.ts)"

printf 'export const complexityScore = 21;\nexport const changed = true;\n' >"$repo/src/block.ts"
assert_status_and_text "Oxlint score 21 blocks from whole-file analysis" 1 \
  "error: oxlint src/block.ts:3 score 21" "$repo" "$(diff_for src/block.ts)"

header_like_diff="$(diff_for src/block.ts)$(printf '\n')+++ value;"
assert_status_and_text "added code beginning with three pluses keeps the selected file" 1 \
  "error: oxlint src/block.ts:3 score 21" "$repo" "$header_like_diff"

printf 'complexity_score = 11\n' >"$repo/src/advisory.py"
assert_status_and_text "Ruff score 11 is advisory" 0 \
  "advisory: ruff src/advisory.py:4 score 11" "$repo" "$(diff_for src/advisory.py)"

printf 'complexity_score = 21\n' >"$repo/src/block.py"
assert_status_and_text "Ruff score 21 blocks" 1 \
  "error: ruff src/block.py:4 score 21" "$repo" "$(diff_for src/block.py)"

mkdir -p "$repo/tests" "$repo/src/__tests__"
printf 'export const complexityScore = 21;\n' >"$repo/tests/a.ts"
printf 'export const complexityScore = 21;\n' >"$repo/src/a.test.ts"
printf 'complexity_score = 21\n' >"$repo/src/test_named.py"
excluded_diff="$(diff_for tests/a.ts)$(printf '\n')$(diff_for src/a.test.ts)$(printf '\n')$(diff_for src/test_named.py)"
out=$(run_lint "$repo" "$excluded_diff"); status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ]; then
  pass "test files are excluded"
else
  fail "test files are excluded (status=$status output='$out')"
fi

printf 'export const MALFORMED = true;\n' >"$repo/src/malformed.ts"
assert_status_and_text "malformed tool JSON fails open" 0 \
  "skip: oxlint: malformed JSON output" "$repo" "$(diff_for src/malformed.ts)"

printf 'export const PROCESS_FAIL = true;\n' >"$repo/src/process-fail.ts"
assert_status_and_text "tool process failures fail open" 0 \
  "skip: oxlint: tool process failed" "$repo" "$(diff_for src/process-fail.ts)"

printf 'export const RULE_UNAVAILABLE = true;\n' >"$repo/src/unavailable.ts"
assert_status_and_text "unavailable complexity rules fail open" 0 \
  "skip: oxlint: complexity rule unavailable" "$repo" "$(diff_for src/unavailable.ts)"

missing="$TMP/missing"
mkdir -p "$missing/src"
printf 'export const complexityScore = 21;\n' >"$missing/src/no-tool.ts"
assert_status_and_text "a missing local tool fails open" 0 \
  "skip: oxlint: no repository-local tool" "$missing" "$(diff_for src/no-tool.ts)"

outside="$TMP/outside.ts"
printf 'export const complexityScore = 21;\n' >"$outside"
out=$(run_lint "$repo" "$(diff_for ../outside.ts)"); status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ]; then
  pass "path traversal is ignored"
else
  fail "path traversal is ignored (status=$status output='$out')"
fi

ln -s "$outside" "$repo/src/outside-link.ts"
out=$(run_lint "$repo" "$(diff_for src/outside-link.ts)"); status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ]; then
  pass "symlink traversal is ignored"
else
  fail "symlink traversal is ignored (status=$status output='$out')"
fi

complexity_skills=$(grep -Rl 'complexity-lint' "$HARNESS_SOURCE/skills" | sort)
if [ "$complexity_skills" = "$HARNESS_SOURCE/skills/lazar-commit/SKILL.md" ]; then
  pass "only lazar-commit invokes complexity-lint"
else
  fail "only lazar-commit invokes complexity-lint (found '$complexity_skills')"
fi

if [ "$failures" -eq 0 ]; then
  printf '\nall complexity-lint cases passed\n'
  exit 0
fi

printf '\n%d complexity-lint case(s) failed\n' "$failures" >&2
exit 1
