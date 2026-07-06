#!/usr/bin/env bash
# collect-metrics.sh — deterministic codebase metrics collector for /codebase-report.
#
# Emits ONE JSON document to stdout. No judgement, no narration: it ships the raw
# file->lines table, window deltas, merged-PR list, an import-coupling tally, and
# test-health counts. The /codebase-report skill narrates over this output.
#
# Design notes (why it's built this way):
#   - File enumeration is a FILESYSTEM WALK rooted at this script's own location, NOT
#     `git ls-files`. The skill may run from an isolated workspace/worktree where the
#     git index is empty and `git rev-parse --show-toplevel` points at the wrong checkout.
#     Walking the real tree works identically from a workspace, the default checkout, or
#     a plain clone, and it sees uncommitted files (an honest "right now" snapshot).
#   - Git is used ONLY for history (`git log --numstat`), which does work from a workspace
#     because it reads the shared object store.
#   - All time windows are computed ONCE in UTC at start and stamped into `meta`, then fed
#     verbatim to both `git --since` and `gh --search` so the two never disagree at a
#     boundary.
#   - cloc is the one hard dependency (it handles binary detection + language tagging).
#
# Usage: collect-metrics.sh            # report on the tree this script lives in
#        collect-metrics.sh /some/root # report on an explicit root (used by tests)
set -euo pipefail

# --- locate the repo root (from the script, never from git) ------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -ge 1 && -n "${1:-}" ]]; then
  ROOT="$(cd "$1" && pwd -P)"
else
  # .claude/skills/codebase-report/collect-metrics.sh -> up 3 = repo root
  ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
fi

# --- hard dependency check ---------------------------------------------------
for dep in cloc fd; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "collect-metrics.sh: $dep not found. Install it (brew install $dep)." >&2
    exit 1
  fi
done

# --- single clock source (UTC), stamped into meta ----------------------------
# %s epoch is the canonical value; ISO strings are derived from it for git/gh.
NOW_EPOCH="$(date -u +%s)"
iso_days_ago() { # $1 = days back -> YYYY-MM-DD (UTC)
  local secs=$(( NOW_EPOCH - $1 * 86400 ))
  if date -u -r "$secs" +%Y-%m-%d >/dev/null 2>&1; then
    date -u -r "$secs" +%Y-%m-%d            # BSD/macOS
  else
    date -u -d "@$secs" +%Y-%m-%d           # GNU/Linux
  fi
}
NOW_ISO="$(date -u -r "$NOW_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$NOW_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"
WEEK_DATE="$(iso_days_ago 7)"
SIXWEEK_DATE="$(iso_days_ago 42)"
QUARTER_DATE="$(iso_days_ago 90)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- enumerate files, then cloc them -----------------------------------------
# fd drives enumeration (not git): it respects .gitignore — so genuine build/dep
# output (node_modules, build dirs) is dropped — while still listing committed
# files like generated bundles and lockfiles, which are tagged `generated` below
# so the report can show total-vs-real. This works identically from an isolated
# workspace, the default checkout, or a plain clone (git ls-files/ls-tree are
# empty in some workspaces). The explicit --exclude entries are
# belt-and-suspenders for trees whose .gitignore doesn't cover them.
fd --type f --hidden --absolute-path \
  --exclude .git --exclude .jj --exclude node_modules \
  --exclude .yarn --exclude dist --exclude build --exclude coverage \
  . "$ROOT" > "$TMP/filelist.txt" 2>/dev/null || true
if [[ ! -s "$TMP/filelist.txt" ]]; then
  echo "collect-metrics.sh: no files found under $ROOT" >&2
  exit 1
fi
cloc --quiet --by-file --json --list-file="$TMP/filelist.txt" \
  > "$TMP/cloc.json" 2>/dev/null || {
    echo "collect-metrics.sh: cloc produced no output for $ROOT" >&2
    exit 1
  }

# --- git history windows (widest window once; python buckets the rest) -------
# -M detects renames; --numstat gives added\tremoved\tpath. Binary files show `-`.
# Empty output (no commits in window) is a legitimate empty, not an error.
# TZ=UTC + explicit +0000 on --since + a UTC %cd date keep the git side on the
# SAME UTC clock the boundaries (and gh --search) use — otherwise a commit near
# midnight in a non-UTC offset buckets into the wrong window.
TZ=UTC git -C "$ROOT" log -M --numstat \
  --since="$QUARTER_DATE 00:00:00 +0000" \
  --date=format-local:'%Y-%m-%dT%H:%M:%SZ' \
  --pretty=tformat:'__COMMIT__%H %cd' > "$TMP/gitlog.txt" 2>/dev/null || true

# --- merged PRs (one call for the widest window; python buckets) -------------
# Distinguish gh-absent from gh-present-but-errored (token scope, rate limit, offline).
GH_STATE="ok"
GH_REASON=""
if ! command -v gh >/dev/null 2>&1; then
  GH_STATE="absent"
  GH_REASON="gh CLI not installed"
  echo "[]" > "$TMP/prs.json"
else
  # Run from $ROOT so gh resolves the repo at ROOT, not the caller's cwd.
  # env -u GITHUB_TOKEN: ambient token may have narrower scope than the gh keyring token.
  if ( cd "$ROOT" && env -u GITHUB_TOKEN gh pr list --state merged \
         --search "merged:>=$QUARTER_DATE" \
         --json number,title,mergedAt,url,author --limit 200 ) \
       > "$TMP/prs.json" 2>"$TMP/gh.err"; then
    :
  else
    GH_STATE="errored"
    GH_REASON="$(head -1 "$TMP/gh.err" 2>/dev/null || echo 'gh pr list failed')"
    echo "[]" > "$TMP/prs.json"
  fi
fi

# --- aggregate everything into the final JSON --------------------------------
ROOT="$ROOT" NOW_ISO="$NOW_ISO" NOW_EPOCH="$NOW_EPOCH" \
WEEK_DATE="$WEEK_DATE" SIXWEEK_DATE="$SIXWEEK_DATE" QUARTER_DATE="$QUARTER_DATE" \
GH_STATE="$GH_STATE" GH_REASON="$GH_REASON" TMP="$TMP" \
python3 <<'PY'
import json, os, re, sys
from collections import defaultdict

ROOT = os.environ["ROOT"]
TMP  = os.environ["TMP"]

def rel(p):
    p = os.path.abspath(p)
    return os.path.relpath(p, ROOT) if p.startswith(ROOT) else p

# ---- generated/vendored detection (committed-but-not-handwritten) ----------
GENERATED_RE = re.compile(
    r"(^|/)\.pnp\.(cjs|loader\.mjs)$"
    r"|(^|/)\.yarn/releases/"
    r"|(^|/)(yarn\.lock|pnpm-lock\.yaml|package-lock\.json|bun\.lockb)$"
    r"|(^|/)[\w.-]*-lock\.(yaml|json)$"
)
def is_generated(p):
    return bool(GENERATED_RE.search(p))

# ---- coarse, DETERMINISTIC bucket per file ---------------------------------
# The agent refines `source` into core-vs-app and resolves `unclassified` at
# narration time; everything else is mechanical so the split is reproducible.
TEST_RE   = re.compile(r"(^|/)(__tests__|__mocks__)/|\.(test|spec)\.[tj]sx?$")
def bucket(p):
    if is_generated(p):                                   return "generated"
    if TEST_RE.search(p):                                 return "test"
    if p.startswith(".claude/") or p == "AGENTS.md" \
       or p.startswith("docs/PHILOSOPHY") or p.startswith("docs/packs"):
        return "harness"
    if re.search(r"(^|/)scripts/", p) or p.endswith(".sh"):
        return "scripts"
    if p.endswith(".md"):                                 return "docs"
    if re.search(r"\.(json|ya?ml|toml)$", p) \
       or re.search(r"(^|/)[\w.-]*\.config\.[mc]?[tj]s$", p) \
       or re.search(r"(^|/)(tsconfig.*\.json|Dockerfile|\.gitignore|\.dockerignore)$", p) \
       or re.search(r"(^|/)(wrangler|eslint|jest|vite|astro|tailwind|drizzle)\.", p):
        return "config"
    if re.search(r"\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|astro|css|sql)$", p):
        return "source"      # agent splits core vs app
    return "unclassified"

# ---- top-level area attribution --------------------------------------------
# Derived purely from paths — no project/app names are hardcoded. Monorepo
# `apps/<x>` and `packages/<x>` collapse to their second segment; everything
# else buckets by its top-level directory (or "root" for a top-level file).
def area(p):
    if p.startswith("apps/"):
        seg = p.split("/")
        return "/".join(seg[:2]) if len(seg) >= 2 else "apps"
    if p.startswith("packages/"):
        seg = p.split("/"); return "/".join(seg[:2]) if len(seg) >= 2 else "packages"
    if p.startswith(".claude/"): return ".claude"
    if p.startswith("docs/"):    return "docs"
    return p.split("/")[0] if "/" in p else "root"

# ---- parse cloc --by-file --json -------------------------------------------
with open(f"{TMP}/cloc.json") as f:
    cloc = json.load(f)

files = []
for path, v in cloc.items():
    if path in ("header", "SUM"):
        continue
    if not isinstance(v, dict) or "code" not in v:
        continue
    rp = rel(path)
    code = int(v.get("code", 0))
    files.append({
        "path": rp,
        "code": code,
        "comment": int(v.get("comment", 0)),
        "blank": int(v.get("blank", 0)),
        "lang": v.get("language", "unknown"),
        "bucket": bucket(rp),
        "area": area(rp),
        "generated": is_generated(rp),
    })
files.sort(key=lambda x: x["path"])

# ---- bucket + area + language rollups --------------------------------------
def rollup(key):
    agg = defaultdict(lambda: {"files": 0, "code": 0})
    for fobj in files:
        a = agg[fobj[key]]; a["files"] += 1; a["code"] += fobj["code"]
    return dict(sorted(agg.items(), key=lambda kv: -kv[1]["code"]))

total_code = sum(f["code"] for f in files)
real_code  = sum(f["code"] for f in files if not f["generated"])

# ---- import-coupling graph (resolve relative specifiers properly) ----------
IMPORT_RE = re.compile(
    r"""(?:import|export)\s[^'"]*?\sfrom\s*['"]([^'"]+)['"]"""
    r"""|import\s*\(\s*['"]([^'"]+)['"]\s*\)"""
    r"""|require\s*\(\s*['"]([^'"]+)['"]\s*\)"""
)
SRC_EXTS = (".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs")
def resolve_rel(importer_rel, spec):
    base = os.path.dirname(importer_rel)
    target = os.path.normpath(os.path.join(base, spec))
    # strip a known extension so ./foo and ./foo.ts collapse to one module
    for e in SRC_EXTS:
        if target.endswith(e):
            return target[: -len(e)]
    return target  # ./foo (extensionless) or ./dir (-> dir/index, approximated)

fan_in_internal = defaultdict(set)   # module -> set of importer files
fan_in_external = defaultdict(set)   # bare specifier -> set of importer files
fan_out         = {}                 # file -> count of distinct resolved targets

for fobj in files:
    p = fobj["path"]
    if fobj["generated"] or fobj["bucket"] == "test":
        continue
    if not p.endswith((".ts", ".tsx", ".mts", ".cts")):
        continue
    try:
        with open(os.path.join(ROOT, p), encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
    except OSError:
        continue
    targets = set()
    for m in IMPORT_RE.finditer(text):
        spec = m.group(1) or m.group(2) or m.group(3)
        if not spec:
            continue
        if spec.startswith("."):
            tgt = resolve_rel(p, spec)
            fan_in_internal[tgt].add(p)
            targets.add(tgt)
        else:
            # bare specifier: external package or path alias
            fan_in_external[spec].add(p)
            targets.add("ext:" + spec)
    if targets:
        fan_out[p] = len(targets)

def top(d, n=15):
    return [{"module": k, "count": len(v)} for k, v in
            sorted(d.items(), key=lambda kv: -len(kv[1]))[:n]]

import_graph = {
    "top_internal_fan_in": top(fan_in_internal),   # internal complexity magnets
    "top_external_fan_in": top(fan_in_external),    # most-depended-on packages/aliases
    "top_fan_out": [{"module": k, "count": v} for k, v in
                    sorted(fan_out.items(), key=lambda kv: -kv[1])[:15]],
    "note": "rg/regex-level, not AST. relative specifiers resolved against importer dir; "
            "extensionless/dir imports approximated; side-effect imports (import './x' with "
            "no binding) are not counted. fan_out = distinct resolved targets.",
}

# ---- test health -----------------------------------------------------------
test_files    = [f for f in files if f["bucket"] == "test"]
# "non-test" = handwritten source the tests are supposed to cover
nontest_src   = [f for f in files if f["bucket"] == "source"]
test_code     = sum(f["code"] for f in test_files)
nontest_code  = sum(f["code"] for f in nontest_src)
test_health = {
    "test_files": len(test_files),
    "nontest_source_files": len(nontest_src),
    "tests_per_nontest_file": round(len(test_files) / len(nontest_src), 3) if nontest_src else None,
    "test_code": test_code,
    "nontest_source_code": nontest_code,
    "test_to_source_code_ratio": round(test_code / nontest_code, 3) if nontest_code else None,
    "sample_test_files": [f["path"] for f in
                          sorted(test_files, key=lambda x: -x["code"])[:12]],
    "note": "denominator is handwritten source files only (bucket=='source'); scripts/ and "
            ".claude harness files are excluded by design, so this is tests-per-source, not "
            "tests-per-every-file. behavior-vs-coverage quality is NOT inferable from counts — "
            "the skill samples test bodies at narration time. listed files are the largest tests.",
}

# ---- git-history windows (parse numstat, handle renames) -------------------
WEEK, SIXWEEK, QUARTER = (os.environ["WEEK_DATE"],
                          os.environ["SIXWEEK_DATE"],
                          os.environ["QUARTER_DATE"])
RENAME_BRACE = re.compile(r"\{.*? => (.*?)\}")
def dest_path(p):
    # numstat rename forms: "a/{b => c}/d.ts" and "a/b.ts => c/d.ts"
    if "=>" in p:
        if "{" in p:
            p = RENAME_BRACE.sub(r"\1", p)
            p = p.replace("//", "/")
        else:
            p = p.split("=>")[-1].strip()
    return p.strip()

# accumulate per-commit so we can bucket by date into the three windows
commits = []
cur = None
with open(f"{TMP}/gitlog.txt") as f:
    for line in f:
        line = line.rstrip("\n")
        if line.startswith("__COMMIT__"):
            if cur:
                commits.append(cur)
            _, date = line[len("__COMMIT__"):].split(" ", 1)
            cur = {"date": date, "rows": []}
        elif line.strip() and cur is not None:
            parts = line.split("\t")
            if len(parts) == 3:
                cur["rows"].append(parts)
    if cur:
        commits.append(cur)

def window(since_date):
    added = removed = 0
    changed = set()
    by_app = defaultdict(lambda: {"added": 0, "removed": 0})
    for c in commits:
        if c["date"][:10] < since_date:
            continue
        for a, r, path in c["rows"]:
            dp = dest_path(path)
            ai = int(a) if a.isdigit() else 0
            ri = int(r) if r.isdigit() else 0
            added += ai; removed += ri
            changed.add(dp)
            ap = area(dp)
            by_app[ap]["added"] += ai; by_app[ap]["removed"] += ri
    return {
        "since": since_date,
        "added": added, "removed": removed, "net": added - removed,
        "files_changed": len(changed),
        "by_app": dict(sorted(by_app.items(), key=lambda kv: -(kv[1]["added"] + kv[1]["removed"]))),
    }

windows = {"week": window(WEEK), "sixweek": window(SIXWEEK), "quarter": window(QUARTER)}

# ---- merged PRs, bucketed into the same windows ----------------------------
gh_state  = os.environ["GH_STATE"]
gh_reason = os.environ["GH_REASON"]
with open(f"{TMP}/prs.json") as f:
    raw_prs = json.load(f)

def pr_window(since_date):
    out = []
    for pr in raw_prs:
        merged = (pr.get("mergedAt") or "")[:10]
        if merged and merged >= since_date:
            out.append({
                "number": pr["number"], "title": pr["title"],
                "mergedAt": pr["mergedAt"], "url": pr["url"],
                "author": (pr.get("author") or {}).get("login", ""),
            })
    out.sort(key=lambda x: x["mergedAt"], reverse=True)
    return out

merged_prs = {
    "available": gh_state == "ok",
    "reason": gh_reason or None,
    "week":    pr_window(WEEK)    if gh_state == "ok" else [],
    "sixweek": pr_window(SIXWEEK) if gh_state == "ok" else [],
    "quarter": pr_window(QUARTER) if gh_state == "ok" else [],
}

# ---- assemble --------------------------------------------------------------
out = {
    "meta": {
        "generated_at": os.environ["NOW_ISO"],
        "root": ROOT,
        "windows": {"week": WEEK, "sixweek": SIXWEEK, "quarter": QUARTER},
        "tool": "collect-metrics.sh",
        "notes": "adds no runtime dependency on the project; read-only; computes nothing the "
                 "app imports. all window dates are UTC and shared by git + gh.",
    },
    "totals": {
        "files": len(files),
        "code": total_code,
        "real_code_excl_generated": real_code,
        "generated_code": total_code - real_code,
    },
    "by_bucket": rollup("bucket"),
    "by_area": rollup("area"),
    "by_lang": rollup("lang"),
    "files": files,
    "windows": windows,
    "merged_prs": merged_prs,
    "import_graph": import_graph,
    "test_health": test_health,
}
json.dump(out, sys.stdout, indent=2)
print()
PY
