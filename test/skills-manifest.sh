#!/usr/bin/env bash
# The committed skills-manifest.txt is the harness's declared skill footprint. install.sh reads it to
# know which skills it ships and writes it as the runtime record it purges against next time, so a
# skill directory the manifest omits would never install, and a manifest line with no directory would
# name a skill that is not there. The two must match exactly, and this fails the moment they drift,
# which is what makes adding or renaming a skill a change nobody makes by accident.
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'ok   %s\n' "$1"; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

manifest=$(LC_ALL=C sort -u -- "$HARNESS_SOURCE/skills-manifest.txt")
on_disk=$(find "$HARNESS_SOURCE/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; |
  LC_ALL=C sort)

if [ "$manifest" = "$on_disk" ]; then
  pass "skills-manifest.txt lists exactly the directories under skills/"
else
  fail "skills-manifest.txt drifted from skills/:$(
    diff <(printf '%s\n' "$manifest") <(printf '%s\n' "$on_disk") | tr '\n' ' '
  )"
fi

# No duplicate lines: a repeated name survives the sort -u set check above, but the footprint it
# seeds would carry it twice and read wrong in a purge diff.
dupes=$(LC_ALL=C sort -- "$HARNESS_SOURCE/skills-manifest.txt" | uniq -d)
if [ -z "$dupes" ]; then
  pass "skills-manifest.txt carries no duplicate lines"
else
  fail "skills-manifest.txt carries duplicate lines: $dupes"
fi

if [ "$failures" -eq 0 ]; then
  echo "skills-manifest: all assertions passed"
else
  printf 'skills-manifest: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
