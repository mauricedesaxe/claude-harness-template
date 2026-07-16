#!/usr/bin/env bash
# Drives apply_local_patch over fixtures, offline. The load-bearing assertion is the second one:
# a vendoring run that meets drifted upstream must stop, because the alternative — vendoring
# upstream without the local patch — silently ships a skill whose layout fixes are gone.
set -uo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

. "$HARNESS_SOURCE/vendor-skills.sh"
set +e # the script it just sourced runs under `set -e`; this file collects failures instead

failures=0

pass() { printf 'ok   %s\n' "$1"; }

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# `die` exits, so each case runs in a subshell and is judged by its status and output.
apply_to() {
  (
    cd -- "$work" || exit 99
    apply_local_patch "$1" 2>&1
  )
}

# --- a patch applies to the upstream it was cut from ------------------------------------------

mkdir -p "$work/pristine"
cat >"$work/pristine/SKILL.md" <<'EOF'
---
name: tldraw-skill
---

## Layout Tips

Spacing scales with complexity.

## Export Commands

Run the CLI.
EOF

cp -r "$work/pristine" "$work/vendored"
cat >"$work/vendored/SKILL.md" <<'EOF'
---
name: lazar-tldraw
---

## Layout Tips

Spacing scales with complexity. Gaps are edge-to-edge, not a centre-to-centre pitch.

## Export Commands

Run the CLI.
EOF

TLDRAW_PATCH="$work/local.patch"
(cd "$work" && diff -u --label a/SKILL.md --label b/SKILL.md \
  pristine/SKILL.md vendored/SKILL.md >"$TLDRAW_PATCH")

mkdir -p "$work/case1"
cp "$work/pristine/SKILL.md" "$work/case1/"
if out=$(apply_to "$work/case1"); then
  pass "the patch applies to the upstream it was cut from"
else
  fail "the patch applies to the upstream it was cut from: $out"
fi

if cmp -s "$work/case1/SKILL.md" "$work/vendored/SKILL.md"; then
  pass "applying it reproduces the vendored skill byte for byte"
else
  fail "applying it reproduces the vendored skill byte for byte"
fi

# --- upstream drifts under a patched region ---------------------------------------------------

mkdir -p "$work/case2"
cat >"$work/case2/SKILL.md" <<'EOF'
---
name: tldraw-skill
---

## Layout Tips

Spacing is now rewritten upstream, in the very lines the local patch rewrites.

## Export Commands

Run the CLI.
EOF

if out=$(apply_to "$work/case2"); then
  fail "a re-vendor stops when upstream drifts under a patched region"
else
  pass "a re-vendor stops when upstream drifts under a patched region"
fi

case $out in
*"no longer applies"*)
  pass "the failure names the patch as the thing to reconcile"
  ;;
*)
  fail "the failure names the patch as the thing to reconcile: $out"
  ;;
esac

# The whole point: drifted upstream must not be left sitting there as a vendorable skill with the
# local changes quietly dropped.
if grep -qF 'edge-to-edge' "$work/case2/SKILL.md"; then
  fail "the rejected vendor left no half-patched skill behind"
elif grep -qF 'rewritten upstream' "$work/case2/SKILL.md"; then
  pass "the rejected vendor left no half-patched skill behind"
else
  fail "the rejected vendor left no half-patched skill behind"
fi

# --- the patch is missing ---------------------------------------------------------------------

TLDRAW_PATCH="$work/does-not-exist.patch"
mkdir -p "$work/case3"
cp "$work/pristine/SKILL.md" "$work/case3/"
if apply_to "$work/case3" >/dev/null; then
  fail "a missing patch stops the vendor rather than shipping bare upstream"
else
  pass "a missing patch stops the vendor rather than shipping bare upstream"
fi

if [ "$failures" -eq 0 ]; then
  echo "tldraw-patch: all assertions passed"
else
  printf 'tldraw-patch: %d assertion(s) failed\n' "$failures" >&2
  exit 1
fi
