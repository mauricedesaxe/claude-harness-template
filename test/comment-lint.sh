#!/usr/bin/env bash
# Drives bin/comment-lint over synthetic files, one per rule it decides. Synthetic because a
# fixture drawn from the repo pins whatever that file happens to contain today, and the thing
# under test is the policy, not a file. Every case names the measure it exercises, so a
# constant moved in the core fails the case that constant exists to serve.
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$HARNESS_SOURCE/bin/comment-lint.mjs"
failures=0

pass() { printf 'ok   %s\n' "$1"; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

command -v node >/dev/null 2>&1 || {
  printf 'no node; comment-lint fails open and there is nothing to drive\n' >&2
  exit 0
}

# The core reads a Claude Code PostToolUse payload, so the file name has to ride along with the
# content: language is chosen by extension, and a payload without one lints nothing at all.
lint() {
  local name=$1 body=$2
  node -e '
    const [name, body] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({ tool_input: { file_path: name, content: body } }));
  ' "$name" "$body" | node "$CORE" claude-hook 2>&1
}

# Asserts on the reported measure, never on the exit code alone. A case that trips the wrong
# measure is a case that would keep passing through the exact regression it guards against:
# both walls exit 2, and only the message says which rule caught it.
assert_lint() {
  local what=$1 want=$2 name=$3 body=$4 out
  out=$(lint "$name" "$body")

  local got="clean"
  case "$out" in
  *"floating comment"*) got="loose" ;;
  esac
  case "$out" in
  *"% of the text is comment"*) got="char" ;;
  *"% of the lines are comment"*) got="line" ;;
  esac

  if [ "$got" = "$want" ]; then
    pass "$what"
  else
    fail "$what (wanted $want, got $got)"
  fi
}

# A paragraph of prose long enough to be a wall on its own, held on one physical line. The old
# check counted comment lines only, so this exact shape scored 1 line and passed clean.
WALL='This function resolves a payment intent against the ledger, and it first checks whether the intent has already been settled because the upstream redelivers webhooks and a double settle would double-charge the customer, and it then loads the ledger row, applies the delta, and writes it back under an optimistic version check so two concurrent deliveries cannot both win, and if that check fails it does not retry here because the caller decides.'

CODE=$(printf '  const step%d = compute(a, b);\n' 1 2 3 4 5 6 7 8 9 10 11 12 13 14)

# The regression this file exists for: a wall wrapped long is a few lines and most of the text.
assert_lint "a long-wrapped prose wall trips the character measure" char wall.ts \
  "$(printf '/**\n * %s\n */\nexport function settle(a, b) {\n%s\n  return a + b;\n}\n' "$WALL" "$CODE")"

# The same wall on a single physical line. No line count can reach this one: it is one comment
# line, under any floor expressed in lines, and still most of the file's text.
assert_lint "a wall held on one physical line trips the character measure" char oneline.ts \
  "$(printf '/** %s */\nexport function settle(a, b) {\n%s\n  return a + b;\n}\n' "$WALL" "$CODE")"

# The other wall, which the character measure cannot see: a comment beside every line of code
# is most of the lines and almost none of the text. Dropping the line measure regresses this.
assert_lint "a comment beside every line trips the line measure" line perline.ts \
  "$(printf 'export function settle(a, b) {\n%s}\n' \
    "$(printf '  const step%d = computeTheNextPartOfTheLedgerDelta(a, b); // step\n' 1 2 3 4 5 6 7 8)")"

# The floors, from the other side. A genuine short why on a symbol is what §21's own fix menu
# tells the agent to write, so the check that enforces §21 must not bounce it.
assert_lint "a one-line doc comment on a symbol stays clean" clean doc.ts \
  "$(printf '/** Minor units throughout, never a float: the upstream rounds halves up. */\nexport function settle(a, b) {\n%s\n  return a + b;\n}\n' "$CODE")"

assert_lint "a three-line doc comment on a symbol stays clean" clean doc3.ts \
  "$(printf '/**\n * Minor units throughout, never a float, because the upstream rounds\n * halves up and a cent of drift compounds across a settlement run.\n */\nexport function settle(a, b) {\n%s\n  return a + b;\n}\n' "$CODE")"

# Reflow invariance is the property the character measure is built on, and the reason it counts
# non-whitespace only. Re-wrapping prose changes its line count and must not change the verdict.
NARROW=$(printf '/**\n * Minor units throughout,\n * never a float, because\n * the upstream rounds\n * halves up.\n */\nexport function settle(a, b) {\n%s\n  return a + b;\n}\n' "$CODE")
WIDE=$(printf '/**\n * Minor units throughout, never a float, because the upstream rounds halves up.\n */\nexport function settle(a, b) {\n%s\n  return a + b;\n}\n' "$CODE")
narrow_out=$(lint narrow.ts "$NARROW")
wide_out=$(lint wide.ts "$WIDE")
if [ -z "$narrow_out" ] && [ -z "$wide_out" ]; then
  pass "the same why wrapped narrow and wide gets the same verdict"
else
  fail "the same why wrapped narrow and wide gets the same verdict (narrow='$narrow_out' wide='$wide_out')"
fi

# The exemptions the density measures must not count, or every generated and licensed file in
# the repo becomes unwritable. Each one is a whole file of nothing but exempt comment lines.
assert_lint "tooling directives never count toward density" clean directives.ts \
  "$(printf '/* eslint-disable no-console */\n// @ts-nocheck\n// prettier-ignore\n// biome-ignore lint: upstream\nexport const x = 1;\n')"

assert_lint "a license header never counts toward density" clean license.ts \
  "$(printf '// Copyright 2026 Someone\n// SPDX-License-Identifier: MIT\n// All rights reserved.\n// Licence terms above.\nexport const x = 1;\n')"

assert_lint "a shebang never counts toward density" clean shebang.py \
  "$(printf '#!/usr/bin/env python3\nx = 1\n')"

# Python runs the other scanner, so every measure needs its own case here: a shared bug in the
# density maths would show in both, but a scanner that mis-weighs `#` text shows only in this one.
assert_lint "a long-wrapped prose wall trips the character measure in python" char wall.py \
  "$(printf '# %s\ndef settle(a, b):\n%s\n    return a + b\n' "$WALL" \
    "$(printf '    step%d = compute(a, b)\n' 1 2 3 4 5 6 7 8 9 10 11 12 13 14)")"

# A `#` inside a string is not a comment, and a scanner that thinks it is would weigh the whole
# string as comment text and fail a file that has no comments in it at all.
assert_lint "a hash inside a string is not comment text" clean strings.py \
  "$(printf 'colours = ["#ffffff", "#000000", "#abcdef", "#123456", "#fedcba", "#0f0f0f"]\nheader = "# not a comment, and long enough that counting it would trip the ratio"\n')"

# Fail-open is the whole safety story: comment-lint guards style, so a core that errors on a file
# it cannot parse would brick every write in the session rather than let a comment through.
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
