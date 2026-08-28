#!/usr/bin/env bash
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$HARNESS_SOURCE/bin/comment-lint.mjs"
TMP=$(mktemp -d)
failures=0
trap 'rm -rf -- "$TMP"' EXIT

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }

command -v node >/dev/null 2>&1 || {
  printf 'no node; comment-lint fails open and there is nothing to drive\n' >&2
  exit 0
}

hook() {
  local name=$1 old=$2 new=$3
  node -e '
    const [name, oldText, newText] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({ tool_input: {
      file_path: name, old_content: oldText, content: newText,
    }}));
  ' "$name" "$old" "$new" | node "$CORE" claude-hook 2>&1
}

edit_hook() {
  local name=$1 old=$2 new=$3
  node -e '
    const [name, oldText, newText] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({ tool_input: {
      file_path: name, old_string: oldText, new_string: newText,
    }}));
  ' "$name" "$old" "$new" | node "$CORE" claude-hook 2>&1
}

current_hook() {
  local name=$1 new=$2
  node -e '
    const [name, newText] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({ tool_input: {
      file_path: name, content: newText,
    }}));
  ' "$name" "$new" | node "$CORE" claude-hook 2>&1
}

assert_hook() {
  local what=$1 want=$2 name=$3 old=$4 new=$5 out status
  out=$(hook "$name" "$old" "$new")
  status=$?
  if [ "$status" -eq "$want" ]; then
    pass "$what"
  else
    fail "$what (status=$status output='$out')"
  fi
}

assert_hook "a new doc comment is rejected" 2 doc.ts \
  'export const value = 1;' $'/** Explains the value. */\nexport const value = 1;'
assert_hook "a new trailing comment is rejected" 2 trailing.ts \
  'export const value = 1;' 'export const value = 1; // Explains the value.'
assert_hook "a new loose comment is rejected" 2 loose.py \
  'value = 1' $'# Explains the value.\nvalue = 1'

assert_hook "an unchanged surrounding comment passes" 0 unchanged.ts \
  $'// Existing explanation.\nexport const value = 1;' \
  $'// Existing explanation.\nexport const value = 2;'
assert_hook "normalized unchanged comment text passes" 0 normalized.ts \
  $'/** Existing explanation. */\nexport const value = 1;' \
  $'/**\n * Existing   explanation.\n */\nexport const value = 2;'
assert_hook "comment comparison preserves multiset counts" 2 duplicate.ts \
  $'// Existing explanation.\nexport const value = 1;' \
  $'// Existing explanation.\n// Existing explanation.\nexport const value = 1;'
assert_hook "slashes inside a regular expression are not comments" 0 regex.ts '' \
  'export const url = /^https?:\\/\\/example\\.com$/;'
assert_hook "comment-like text inside a template stays text" 0 template-text.ts '' \
  'export const value = `https://example.com/path`;'
assert_hook "a comment inside a template expression is rejected" 2 template-expression.ts '' \
  'export const value = `${/* Explain the value. */ source}`;'
assert_hook "a trailing comment after division is rejected" 2 division.ts '' \
  'export const average = total / count; // Explains the average.'

assert_hook "tooling directives are exempt" 0 directives.ts '' \
  $'// @ts-nocheck\n/* eslint-disable no-console */\nexport const value = 1;'
assert_hook "a shebang is exempt" 0 shebang.py '' \
  $'#!/usr/bin/env python3\nvalue = 1'
assert_hook "a leading license header is exempt" 0 license.ts '' \
  $'// Copyright 2026 Someone\n// SPDX-License-Identifier: MIT\nexport const value = 1;'
assert_hook "all lines in a leading license header are exempt" 0 license-full.ts '' \
  $'// Copyright 2026 Someone\n// Permission is hereby granted, free of charge.\n// SPDX-License-Identifier: MIT\nexport const value = 1;'

current="$TMP/current.ts"
printf '// Existing explanation.\nexport const value = 1;\n' >"$current"
out=$(current_hook "$current" $'// Existing explanation.\nexport const value = 2;'); status=$?
if [ "$status" -eq 0 ]; then
  pass "whole-file writes read the current file before mutation"
else
  fail "whole-file writes read the current file before mutation (status=$status output='$out')"
fi

out=$(edit_hook edit.ts '// Existing explanation.' '// Existing explanation.'); status=$?
if [ "$status" -eq 0 ]; then
  pass "edit payloads compare old and new text"
else
  fail "edit payloads compare old and new text (status=$status output='$out')"
fi

same_diff=$(printf '%s\n' \
  'diff --git a/file.ts b/file.ts' \
  '--- a/file.ts' \
  '+++ b/file.ts' \
  '@@ -1 +1 @@' \
  '-// Existing explanation.' \
  '+// Existing explanation.')
out=$(printf '%s' "$same_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then
  pass "diff mode subtracts removed comment tokens"
else
  fail "diff mode subtracts removed comment tokens (status=$status output='$out')"
fi

changed_diff=$(printf '%s\n' \
  'diff --git a/file.ts b/file.ts' \
  '--- a/file.ts' \
  '+++ b/file.ts' \
  '@@ -1 +1 @@' \
  '-// Existing explanation.' \
  '+// New explanation.')
out=$(printf '%s' "$changed_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then
  pass "diff mode rejects an added token after subtraction"
else
  fail "diff mode rejects an added token after subtraction (status=$status output='$out')"
fi

block_middle_diff=$(printf '%s\n' \
  'diff --git a/file.ts b/file.ts' \
  '--- a/file.ts' \
  '+++ b/file.ts' \
  '@@ -1,3 +1,3 @@' \
  ' /**' \
  '- * Existing explanation.' \
  '+ * New explanation.' \
  ' */')
out=$(printf '%s' "$block_middle_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then
  pass "diff mode rejects an edited block-comment continuation"
else
  fail "diff mode rejects an edited block-comment continuation (status=$status output='$out')"
fi

long_block="$TMP/long-block.ts"
printf '/**\n * First line.\n * Second line.\n * Third line.\n * New explanation.\n * Fifth line.\n * Sixth line.\n */\nexport const value = 1;\n' >"$long_block"
long_block_diff=$(printf '%s\n' \
  'diff --git a/'"$long_block"' b/'"$long_block" \
  '--- a/'"$long_block" \
  '+++ b/'"$long_block" \
  '@@ -4,3 +4,3 @@' \
  '  * Third line.' \
  '- * Existing explanation.' \
  '+ * New explanation.' \
  '  * Fifth line.')
out=$(printf '%s' "$long_block_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then
  pass "diff mode uses the full file for long block-comment edits"
else
  fail "diff mode uses the full file for long block-comment edits (status=$status output='$out')"
fi

reflow_diff=$(printf '%s\n' \
  'diff --git a/file.ts b/file.ts' \
  '--- a/file.ts' \
  '+++ b/file.ts' \
  '@@ -1 +1,3 @@' \
  '-/** Existing explanation. */' \
  '+/**' \
  '+ * Existing explanation.' \
  '+ */')
out=$(printf '%s' "$reflow_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then
  pass "diff mode allows an unchanged block comment to reflow"
else
  fail "diff mode allows an unchanged block comment to reflow (status=$status output='$out')"
fi

multiline_math_diff=$(printf '%s\n' \
  'diff --git a/file.ts b/file.ts' \
  '--- a/file.ts' \
  '+++ b/file.ts' \
  '@@ -2 +2 @@' \
  '-  * oldLeft * oldRight;' \
  '+  * newLeft * newRight;')
out=$(printf '%s' "$multiline_math_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then
  pass "diff mode does not treat multiline arithmetic as a block comment"
else
  fail "diff mode does not treat multiline arithmetic as a block comment (status=$status output='$out')"
fi

header_like_diff=$(printf '%s\n' \
  'diff --git a/file.ts b/file.ts' \
  '--- a/file.ts' \
  '+++ b/file.ts' \
  '@@ -1 +1,2 @@' \
  '+const next = ++value;' \
  '+++ value; // New explanation.')
out=$(printf '%s' "$header_like_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then
  pass "added code beginning with three pluses stays in the current file"
else
  fail "added code beginning with three pluses stays in the current file (status=$status output='$out')"
fi

if printf 'not json at all' | node "$CORE" claude-hook >/dev/null 2>&1; then
  pass "malformed input fails open"
else
  fail "malformed input fails open"
fi

if [ "$failures" -eq 0 ]; then
  printf '\nall comment-lint cases passed\n'
  exit 0
fi

printf '\n%d comment-lint case(s) failed\n' "$failures" >&2
exit 1
