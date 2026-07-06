#!/usr/bin/env bash
# test-collect.sh — behavior test for collect-metrics.sh.
#
# Pins the JSON contract the SKILL.md narration depends on AND the hazards a
# "keys exist" check sails past. Three fixtures:
#   A. synthetic tree, no git    — file walk, bucket classification, import
#                                   resolution, generated/vendored split, exact
#                                   ratios, gh present-but-errored (+ stub gh).
#   B. real git history          — window math, by_app attribution, files_changed
#                                   dedup, cross-app rename destination parsing.
#   C. the real repo             — proves the gh available:true pole.
# Exits non-zero on the first failed assertion.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$HERE/collect-metrics.sh"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

ROOT_TMP="$(mktemp -d)"
trap 'rm -rf "$ROOT_TMP"' EXIT

days_ago_iso() { # $1 = days back -> UTC ISO-8601
  local s=$(( $(date -u +%s) - $1 * 86400 ))
  date -u -r "$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ
}

# ============================================================================
# Fixture A — synthetic tree, no git
# ============================================================================
FIX="$ROOT_TMP/a"
mkdir -p "$FIX/app/src" "$FIX/app/node_modules/pkg" "$FIX/pkg" "$FIX/.claude"
# source (2 files -> the test-health denominator)
printf 'export const x = 1\nexport const y = 2\n'                 > "$FIX/app/src/util.ts"
printf "import { x } from './util'\nimport { z } from 'zod'\nexport const run = () => x\n" \
                                                                  > "$FIX/app/src/core.ts"
# test (imports ./core — must be EXCLUDED from the import graph)
printf "import { run } from './core'\ntest('runs', () => { expect(run()).toBe(1) })\n" \
                                                                  > "$FIX/app/src/core.test.ts"
# vendored: must be excluded entirely
printf 'module.exports = 1\n'                                     > "$FIX/app/node_modules/pkg/index.js"
# committed-but-generated: COUNTED and TAGGED, not dropped
printf 'a\nb\nc\nd\ne\n'                                          > "$FIX/app/.pnp.cjs"
printf 'lockfileVersion: 9\nx: y\n'                               > "$FIX/app/pnpm-lock.yaml"
# one file per remaining bucket (deterministic classifier coverage)
printf '#!/bin/sh\necho hi\n'                                     > "$FIX/pkg/run.sh"
printf '{ "compilerOptions": {} }\n'                              > "$FIX/app/tsconfig.json"
printf '# readme\nbody\n'                                         > "$FIX/README.md"
printf '# harness note\n'                                         > "$FIX/.claude/x.md"

OUT_A="$ROOT_TMP/a.json"
"$COLLECT" "$FIX" > "$OUT_A"

OUT_A="$OUT_A" python3 <<'PY'
import json, os, sys
d = json.load(open(os.environ["OUT_A"]))
fails = []
def check(c, m):
    if not c: fails.append(m)

# contract: every top-level key the SKILL.md reads
for k in ("meta","totals","by_bucket","by_area","by_lang","files",
          "windows","merged_prs","import_graph","test_health"):
    check(k in d, f"missing top-level key: {k}")
check(len(d["files"]) > 0, "files[] is empty")

by_path = {f["path"]: f for f in d["files"]}

# vendored fully excluded
check(not [p for p in by_path if "node_modules" in p],
      f"vendored path leaked: {[p for p in by_path if 'node_modules' in p]}")

# generated tagged + split out of real
gen = [p for p, f in by_path.items() if f["generated"]]
check(any(".pnp.cjs" in p for p in gen), "'.pnp.cjs' not tagged generated")
check(any("pnpm-lock.yaml" in p for p in gen), "lockfile not tagged generated")
t = d["totals"]
check(t["generated_code"] > 0, "generated_code is 0")
check(t["real_code_excl_generated"] < t["code"], "real_code not less than total")

# deterministic bucket classifier — one assertion per rule
want = {
    "app/src/util.ts":      "source",
    "app/src/core.test.ts": "test",
    "app/.pnp.cjs":         "generated",
    "pkg/run.sh":           "scripts",
    "app/tsconfig.json":    "config",
    "README.md":            "docs",
    ".claude/x.md":         "harness",
}
for p, b in want.items():
    got = by_path.get(p, {}).get("bucket")
    check(got == b, f"bucket({p}) = {got!r}, want {b!r}")

# exact test-health ratios (1 test file; util.ts+core.ts = 2 source; code 2 vs 2+3)
th = d["test_health"]
check(th["tests_per_nontest_file"] == 0.5,
      f"tests_per_nontest_file = {th['tests_per_nontest_file']}, want 0.5")
check(th["test_to_source_code_ratio"] == round(2/5, 3),
      f"test_to_source_code_ratio = {th['test_to_source_code_ratio']}, want {round(2/5,3)}")

# import graph: relative resolved into fan-in, bare specifier external,
# fan-out counts distinct targets, test importer excluded
fin = {x["module"]: x["count"] for x in d["import_graph"]["top_internal_fan_in"]}
check(any(m.endswith("app/src/util") for m in fin),
      f"'./util' not resolved into internal fan-in: {fin}")
check(not any(m.endswith("app/src/core") for m in fin),
      f"app/src/core has fan-in — core.test.ts was NOT excluded: {fin}")
fext = {x["module"] for x in d["import_graph"]["top_external_fan_in"]}
check("zod" in fext, f"bare 'zod' not tallied external: {fext}")
fout = {x["module"]: x["count"] for x in d["import_graph"]["top_fan_out"]}
core_fo = next((c for m, c in fout.items() if m.endswith("app/src/core.ts")), None)
check(core_fo == 2, f"core.ts fan-out = {core_fo}, want 2 (./util + ext:zod)")

# gh present (real binary) but ROOT is not a git/GitHub repo -> errored, NOT absent
mp = d["merged_prs"]
check(mp["available"] is False, "gh should be unavailable in a non-repo fixture")
check(bool(mp["reason"]), "unavailable merged_prs must carry a reason")
check(mp["reason"] != "gh CLI not installed",
      "non-repo fixture should hit the ERRORED branch, not the absent branch")

if fails:
    print("FIXTURE A FAILED:"); [print("  -", m) for m in fails]; sys.exit(1)
print(f"fixture A passed: {len(d['files'])} files, real={t['real_code_excl_generated']} "
      f"total={t['code']} generated={t['generated_code']}")
PY

# --- Fixture A, second run: stub gh that errors with a known marker ---------
STUBBIN="$ROOT_TMP/stubbin"
mkdir -p "$STUBBIN"
printf '#!/bin/sh\necho "STUB_GH_BOOM token scope" >&2\nexit 1\n' > "$STUBBIN/gh"
chmod +x "$STUBBIN/gh"
OUT_A2="$ROOT_TMP/a2.json"
PATH="$STUBBIN:$PATH" "$COLLECT" "$FIX" > "$OUT_A2"
OUT_A2="$OUT_A2" python3 <<'PY'
import json, os, sys
d = json.load(open(os.environ["OUT_A2"]))
mp = d["merged_prs"]
fails = []
if mp["available"] is not False:
    fails.append("stubbed failing gh should yield available:false")
if "STUB_GH_BOOM" not in (mp["reason"] or ""):
    fails.append(f"errored reason must carry gh stderr, got: {mp['reason']!r}")
if fails:
    print("FIXTURE A (stub gh) FAILED:"); [print("  -", m) for m in fails]; sys.exit(1)
print("fixture A (stub gh errored) passed: reason carries gh stderr")
PY

# ============================================================================
# Fixture B — real git history: windows, by_app, files_changed, rename dest
# ============================================================================
GB="$ROOT_TMP/b"
mkdir -p "$GB/apps/alpha" "$GB/apps/beta" "$GB/.claude"
git -C "$GB" init -q
git -C "$GB" config user.email t@t.t
git -C "$GB" config user.name test
git -C "$GB" config commit.gpgsign false

D_OLD="$(days_ago_iso 50)"   # in quarter, outside the 6-week + week windows
D_NEW="$(days_ago_iso 2)"    # inside every window
commit_at() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "$GB" commit -qm "$2"; }

# commit 1 (50d ago): 4-line file under apps/alpha -> quarter-only
printf 'a\nb\nc\nd\n' > "$GB/apps/alpha/a.ts"
git -C "$GB" add -A; commit_at "$D_OLD" "add alpha/a.ts"

# commit 2 (2d ago): 3-line harness file -> week window, second app area
printf 'h1\nh2\nh3\n' > "$GB/.claude/b.md"
git -C "$GB" add -A; commit_at "$D_NEW" "add harness note"

# commit 3 (2d ago): CROSS-APP rename-WITH-EDIT alpha/a.ts -> beta/c.ts (+1 line).
# The edit makes the dest's `added` non-zero, so attributing the rename to the
# source app (a regression) would change week.by_app — the assertion has teeth.
git -C "$GB" mv apps/alpha/a.ts apps/beta/c.ts
printf 'a\nb\nc\nd\ne\n' > "$GB/apps/beta/c.ts"
git -C "$GB" add -A; commit_at "$D_NEW" "move a.ts across apps, +1 line"

# commit 4 (2d ago): WITHIN-PREFIX rename -> git emits the BRACE form
# `apps/beta/{ => sub}/c.ts`, exercising RENAME_BRACE + the //->/ collapse
# that the cross-app rename above (brace-less form) never hits.
mkdir -p "$GB/apps/beta/sub"
git -C "$GB" mv apps/beta/c.ts apps/beta/sub/c.ts
git -C "$GB" add -A; commit_at "$D_NEW" "nest c.ts under sub/ (brace-form rename)"

OUT_B="$ROOT_TMP/b.json"
"$COLLECT" "$GB" > "$OUT_B"
OUT_B="$OUT_B" python3 <<'PY'
import json, os, sys
d = json.load(open(os.environ["OUT_B"]))
w = d["windows"]
fails = []
def check(c, m):
    if not c: fails.append(m)

# window line math (numstat, UTC-bucketed): week = harness add (3) + rename-with-edit
# (1); the pure brace-form rename adds 0. quarter additionally sees the 4-line old file.
check(w["week"]["added"] == 4,    f"week.added = {w['week']['added']}, want 4 (3+1)")
check(w["quarter"]["added"] == 8, f"quarter.added = {w['quarter']['added']}, want 8 (4+3+1)")
check(w["quarter"]["added"] > w["week"]["added"], "quarter should exceed week")

wk = w["week"]["by_app"]
check(wk.get(".claude", {}).get("added") == 3, f".claude week added = {wk.get('.claude')}, want 3")
# DEST attribution is load-bearing: the rename's +1 line must land on the DEST app...
check(wk.get("apps/beta", {}).get("added") == 1,
      f"rename dest apps/beta added = {wk.get('apps/beta')}, want 1")
# ...and NOT on the source app (it should not appear at all).
check("apps/alpha" not in wk,
      f"rename source apps/alpha must not be attributed in week: {wk.get('apps/alpha')}")
# both rename forms parsed: no brace/arrow syntax leaks into the keys.
check(all("{" not in k and "=>" not in k for k in wk),
      f"unparsed rename syntax leaked into by_app keys: {list(wk)}")

# files_changed dedup: .claude/b.md + the two rename DEST paths
# (beta/c.ts, beta/sub/c.ts) = 3 distinct.
check(w["week"]["files_changed"] == 3,
      f"week.files_changed = {w['week']['files_changed']}, want 3")

if fails:
    print("FIXTURE B FAILED:"); [print("  -", m) for m in fails]; sys.exit(1)
print(f"fixture B passed: week +{w['week']['added']} quarter +{w['quarter']['added']}, "
      f"dest-attributed + both rename forms parsed: {list(wk)}")
PY

# ============================================================================
# Fixture C — real repo: the gh available:true pole + non-empty real numbers
# ============================================================================
OUT_C="$ROOT_TMP/c.json"
"$COLLECT" "$REPO_ROOT" > "$OUT_C"
OUT_C="$OUT_C" python3 <<'PY'
import json, os, sys
d = json.load(open(os.environ["OUT_C"]))
fails = []
def check(c, m):
    if not c: fails.append(m)
check(len(d["files"]) > 50, "real repo should have many files")
check(d["totals"]["real_code_excl_generated"] > 0, "real repo real_code is 0")
mp = d["merged_prs"]
if mp["available"]:
    check(isinstance(mp["quarter"], list), "quarter PRs not a list when available")
else:
    check(bool(mp["reason"]), "unavailable real-repo merged_prs must carry a reason")
if fails:
    print("FIXTURE C FAILED:"); [print("  -", m) for m in fails]; sys.exit(1)
print(f"fixture C passed: available={mp['available']}, files={len(d['files'])}")
PY

echo "ALL TESTS PASSED"
