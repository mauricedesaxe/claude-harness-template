#!/usr/bin/env bash
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$HARNESS_SOURCE/bin/comment-lint.mjs"
LINT="$HARNESS_SOURCE/bin/comment-lint"
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

assert_hook "a native block doc passes" 0 doc.ts \
  'export const value = 1;' $'/** Explains the value. */\nexport const value = 1;'
assert_hook "triple-slash symbol docs pass" 0 docs.ts '' \
  $'/// Public docs.\nexport const value = 1;'
assert_hook "JSDoc attached to a method passes" 0 method.ts '' \
  $'class Service {\n  /** Public method docs. */\n  run() {}\n}'
assert_hook "floating JSDoc fails" 2 floating.ts '' \
  $'/** Floating docs. */\nvalue();'
assert_hook "detached JSDoc fails" 2 detached.ts '' \
  $'/** Detached docs. */\n\nexport const value = 1;'
assert_hook "trailing JSDoc fails" 2 trailing-doc.ts '' \
  'export const value = 1; /** Trailing docs. */'
assert_hook "an explicit Why rationale passes" 0 why.ts '' \
  $'// Why: the upstream returns HTML for this status.\nexport const value = 1;'
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
assert_hook "a Go raw string can contain a URL" 0 raw.go '' \
  'var endpoint = `https://example.com/path`'
assert_hook "a Go raw string closes after a backslash" 2 raw-backslash.go '' \
  $'var path = `value\\`\n// Explain the next operation.\nvar next = 1'
assert_hook "a standalone Go symbol doc passes" 0 docs.go '' \
  $'// Endpoint returns the service URL.\n// It uses the configured host.\nfunc Endpoint() string { return "" }'
assert_hook "a generic Go comment still fails" 2 loose.go '' \
  $'// Explain the next operation.\nfunc Endpoint() string { return "" }'
assert_hook "a comment inside a template expression is rejected" 2 template-expression.ts '' \
  'export const value = `${/* Explain the value. */ source}`;'
assert_hook "a trailing comment after division is rejected" 2 division.ts '' \
  'export const average = total / count; // Explains the average.'

assert_hook "tooling directives are exempt" 0 directives.ts '' \
  $'// @ts-nocheck\n// #pragma once\n// pragma: no cover\n/* eslint-disable no-console */\nexport const value = 1;'
assert_hook "pragma text without directive syntax fails" 2 pragmatic.ts '' \
  $'// This pragmatic choice is temporary.\nexport const value = 1;'
assert_hook "pragma labels embedded in prose fail" 2 pragma-prose.ts '' \
  $'// This mentions pragma: but is prose.\nexport const value = 1;'
assert_hook "eslint directive text embedded in prose fails" 2 eslint-prose.ts '' \
  $'// This mentions eslint-disable but is prose.\nexport const value = 1;'
assert_hook "noqa text embedded in prose fails" 2 noqa-prose.py '' \
  $'# This mentions noqa but is prose.\nvalue = 1'
assert_hook "a shebang is exempt" 0 shebang.py '' \
  $'#!/usr/bin/env python3\nvalue = 1'
assert_hook "a leading license header is exempt" 0 license.ts '' \
  $'// Copyright 2026 Someone\n// SPDX-License-Identifier: MIT\nexport const value = 1;'
assert_hook "all lines in a leading license header are exempt" 0 license-full.ts '' \
  $'// Copyright 2026 Someone\n// Permission is hereby granted, free of charge.\n// SPDX-License-Identifier: MIT\nexport const value = 1;'
assert_hook "unsupported extensions fail open" 0 unsupported.rs '' \
  $'// Generic text that the reduced scanner does not judge.\nconst VALUE: i32 = 1;'

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

same_file="$TMP/same.ts"
printf '// Existing explanation.\n' >"$same_file"
same_diff=$(printf '%s\n' \
  'diff --git a/'"$same_file"' b/'"$same_file" \
  '--- a/'"$same_file" \
  '+++ b/'"$same_file" \
  '@@ -1 +1 @@' \
  '-// Existing explanation.' \
  '+// Existing explanation.')
out=$(printf '%s' "$same_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then
  pass "diff mode subtracts removed comment tokens"
else
  fail "diff mode subtracts removed comment tokens (status=$status output='$out')"
fi

changed_file="$TMP/changed.ts"
printf '// New explanation.\n' >"$changed_file"
changed_diff=$(printf '%s\n' \
  'diff --git a/'"$changed_file"' b/'"$changed_file" \
  '--- a/'"$changed_file" \
  '+++ b/'"$changed_file" \
  '@@ -1 +1 @@' \
  '-// Existing explanation.' \
  '+// New explanation.')
out=$(printf '%s' "$changed_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then
  pass "diff mode rejects an added token after subtraction"
else
  fail "diff mode rejects an added token after subtraction (status=$status output='$out')"
fi

block_middle_file="$TMP/block-middle.ts"
printf '/*\n * Existing explanation.\n */\n' >"$block_middle_file"
block_middle_diff=$(printf '%s\n' \
  'diff --git a/'"$block_middle_file"' b/'"$block_middle_file" \
  '--- a/'"$block_middle_file" \
  '+++ b/'"$block_middle_file" \
  '@@' \
  ' /*' \
  '- * Existing explanation.' \
  '+ * New explanation.' \
  '  */')
out=$(printf '%s' "$block_middle_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then
  pass "diff mode rejects an edited block-comment continuation"
else
  fail "diff mode rejects an edited block-comment continuation (status=$status output='$out')"
fi

long_block="$TMP/long-block.ts"
printf '/*\n * First line.\n * Second line.\n * Third line.\n * New explanation.\n * Fifth line.\n * Sixth line.\n */\nexport const value = 1;\n' >"$long_block"
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

reflow_file="$TMP/reflow.ts"
printf '/**\n * Existing explanation.\n */\n' >"$reflow_file"
reflow_diff=$(printf '%s\n' \
  'diff --git a/'"$reflow_file"' b/'"$reflow_file" \
  '--- a/'"$reflow_file" \
  '+++ b/'"$reflow_file" \
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

header_like_file="$TMP/header-like.ts"
printf 'const next = ++value;\n++ value; // New explanation.\n' >"$header_like_file"
header_like_diff=$(printf '%s\n' \
  'diff --git a/'"$header_like_file"' b/'"$header_like_file" \
  '--- a/'"$header_like_file" \
  '+++ b/'"$header_like_file" \
  '@@ -1,0 +1,2 @@' \
  '+const next = ++value;' \
  '+++ value; // New explanation.')
out=$(printf '%s' "$header_like_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then
  pass "added code beginning with three pluses stays in the current file"
else
  fail "added code beginning with three pluses stays in the current file (status=$status output='$out')"
fi

template_file="$TMP/template-hunk.ts"
printf 'export const endpoint = `\nhttps://new.example/path\n`;\n' >"$template_file"
template_diff=$(printf '%s\n' \
  'diff --git a/'"$template_file"' b/'"$template_file" \
  '--- a/'"$template_file" \
  '+++ b/'"$template_file" \
  '@@ -2 +2 @@' \
  '-https://old.example/path' \
  '+https://new.example/path')
out=$(printf '%s' "$template_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then pass "standard diffs use template context outside the hunk"; else fail "standard diffs use template context outside the hunk (status=$status output='$out')"; fi

multi_file="$TMP/multi.ts"
printf 'export const first = 2;\nexport const second = 2; // New explanation.\n' >"$multi_file"
multi_diff=$(printf '%s\n' \
  'diff --git a/'"$multi_file"' b/'"$multi_file" \
  '--- a/'"$multi_file" \
  '+++ b/'"$multi_file" \
  '@@ -1 +1 @@' \
  '-export const first = 1;' \
  '+export const first = 2;' \
  '@@ -2 +2 @@' \
  '-export const second = 1;' \
  '+export const second = 2; // New explanation.')
out=$(printf '%s' "$multi_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then pass "standard multi-hunk diffs reconstruct the old full file"; else fail "standard multi-hunk diffs reconstruct the old full file (status=$status output='$out')"; fi

mismatch_diff=$(printf '%s\n' \
  'diff --git a/'"$multi_file"' b/'"$multi_file" \
  '--- a/'"$multi_file" \
  '+++ b/'"$multi_file" \
  '@@ -1 +1 @@' \
  '-export const first = 1;' \
  '+export const first = 999; // Hidden by mismatch.')
out=$(printf '%s' "$mismatch_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then pass "standard diff reconstruction fails open on a mismatch"; else fail "standard diff reconstruction fails open on a mismatch (status=$status output='$out')"; fi

synthetic_diff=$(printf '%s\n' \
  'diff --git a/'"$TMP/synthetic.ts"' b/'"$TMP/synthetic.ts" \
  '+++ b/'"$TMP/synthetic.ts" \
  '@@' \
  ' export const value = 1;' \
  '+// Synthetic explanation.')
printf 'export const value = 1;\n' >"$TMP/synthetic.ts"
out=$(printf '%s' "$synthetic_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"Synthetic explanation"* ]]; then pass "bare synthetic hunks keep the fallback"; else fail "bare synthetic hunks keep the fallback (status=$status output='$out')"; fi

printf 'repeat();\nrepeat();\n' >"$TMP/ambiguous.ts"
ambiguous_diff=$(printf '%s\n' \
  'diff --git a/'"$TMP/ambiguous.ts"' b/'"$TMP/ambiguous.ts" \
  '+++ b/'"$TMP/ambiguous.ts" \
  '@@' \
  ' repeat();' \
  '+// Ambiguous explanation.')
out=$(printf '%s' "$ambiguous_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then pass "ambiguous synthetic hunks fail open"; else fail "ambiguous synthetic hunks fail open (status=$status output='$out')"; fi

missing_diff=$(printf '%s\n' \
  'diff --git a/'"$TMP/ambiguous.ts"' b/'"$TMP/ambiguous.ts" \
  '+++ b/'"$TMP/ambiguous.ts" \
  '@@' \
  ' missing();' \
  '+// Missing explanation.')
out=$(printf '%s' "$missing_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 0 ]; then pass "unmatched synthetic hunks fail open"; else fail "unmatched synthetic hunks fail open (status=$status output='$out')"; fi

quoted_file="$TMP/café.ts"
printf 'export const value = 2; // New explanation.\n' >"$quoted_file"
quoted_prefix=${quoted_file%é.ts}
quoted_diff=$(printf '%s\n' \
  'diff --git "a/'"$quoted_prefix"'\303\251.ts" "b/'"$quoted_prefix"'\303\251.ts"' \
  '--- "a/'"$quoted_prefix"'\303\251.ts"' \
  '+++ "b/'"$quoted_prefix"'\303\251.ts"' \
  '@@ -1 +1 @@' \
  '-export const value = 1;' \
  '+export const value = 2; // New explanation.')
out=$(printf '%s' "$quoted_diff" | node "$CORE" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then pass "quoted non-ASCII diff paths are decoded"; else fail "quoted non-ASCII diff paths are decoded (status=$status output='$out')"; fi

nested_repo="$TMP/nested-repo"
mkdir -p "$nested_repo/src"
git -C "$nested_repo" init -q
printf 'export const value = 2; // New explanation.\n' >"$nested_repo/src/value.ts"
nested_diff=$(printf '%s\n' \
  'diff --git a/src/value.ts b/src/value.ts' \
  '--- a/src/value.ts' \
  '+++ b/src/value.ts' \
  '@@ -1 +1 @@' \
  '-export const value = 1;' \
  '+export const value = 2; // New explanation.')
out=$(cd "$nested_repo/src" && printf '%s' "$nested_diff" | "$LINT" diff 2>&1); status=$?
if [ "$status" -eq 1 ] && [[ "$out" == *"New explanation"* ]]; then pass "the launcher resolves the repository root from a nested directory"; else fail "the launcher resolves the repository root from a nested directory (status=$status output='$out')"; fi

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
