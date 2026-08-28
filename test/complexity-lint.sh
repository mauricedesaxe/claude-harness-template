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
args=$(printf '%s\n' "$@")
for required in --disable-nested-config --no-ignore --format json; do
  grep -qx -- "$required" <<<"$args" || exit 2
done

config=""; previous=""
files=()
for arg in "$@"; do
  [ "$previous" = "--config" ] && config=$arg
  case "$arg" in *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts) files+=("$arg") ;; esac
  previous=$arg
done
node -e '
const fs = require("fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
if (!same(c.plugins, ["import"])) process.exit(2);
if (!same(c.rules.complexity, ["error", {max:10, variant:"classic"}])) process.exit(2);
if (!same(c.rules["max-depth"], ["error", 4])) process.exit(2);
if (c.rules["import/no-cycle"] !== "error") process.exit(2);
if (!same(c.rules["max-lines"], ["error", {max:500, skipBlankLines:false, skipComments:false}])) process.exit(2);
if (!same(c.rules["max-lines-per-function"], ["error", {max:100, skipBlankLines:false, skipComments:false, IIFEs:false}])) process.exit(2);
' "$config" || exit $?
for file in "${files[@]}"; do
  content=$(<"$file")
  [[ "$content" == *OX_PROCESS_FAIL* ]] && exit 2
  [[ "$content" == *OX_MALFORMED* ]] && { printf 'not-json'; exit 1; }
done
node - "$PWD" "${files[@]}" <<'NODE'
const fs = require("fs");
const diagnostics = [];
for (const file of process.argv.slice(3)) {
  const text = fs.readFileSync(file, "utf8");
  const diagnosticPath = text.match(/diagnostic_path=([^\s]+)/)?.[1] ?? file;
  const add = (code, message) => diagnostics.push({code:`eslint(${code})`, message, filename:diagnosticPath, labels:[{span:{line:3}}]});
  const value = (name) => Number(text.match(new RegExp(`${name}=(\\d+)`))?.[1]);
  if (value("complexity") > 10) add("complexity", `Function foo has a complexity of ${value("complexity")}. Maximum allowed is 10.`);
  if (value("depth") > 4) add("max-depth", `Blocks are nested too deeply (${value("depth")}). Maximum allowed is 4.`);
  if (value("module_lines") > 500) add("max-lines", `File has too many lines (${value("module_lines")}). Maximum allowed is 500.`);
  if (value("function_lines") > 100) add("max-lines-per-function", `Function has too many lines (${value("function_lines")}). Maximum allowed is 100.`);
  if (text.includes("cycle=true")) diagnostics.push({code:"import(no-cycle)", message:"Dependency cycle detected.", filename:file, labels:[{span:{line:3}}]});
  if (text.includes("OX_RULE_UNAVAILABLE")) add("other-rule", "Rule unavailable.");
  if (text.includes("OX_PARTIAL")) diagnostics.push({code:"eslint(complexity)", message:"missing score", filename:file});
}
process.stdout.write(JSON.stringify({diagnostics}));
process.exit(diagnostics.length ? 1 : 0);
NODE
SCRIPT
  cat >"$root/.venv/bin/ruff" <<'SCRIPT'
#!/usr/bin/env bash
set -u
args=$(printf '%s\n' "$@")
for required in check --isolated --select C901 --output-format json --config 'lint.mccabe.max-complexity = 10'; do
  grep -qx -- "$required" <<<"$args" || exit 2
done
files=()
for arg in "$@"; do case "$arg" in *.py|*.pyi) files+=("$arg") ;; esac; done
for file in "${files[@]}"; do
  content=$(<"$file")
  [[ "$content" == *RUFF_PROCESS_FAIL* ]] && exit 2
  [[ "$content" == *RUFF_MALFORMED* ]] && { printf 'not-json'; exit 1; }
done
node - "${files[@]}" <<'NODE'
const fs = require("fs");
const diagnostics = [];
for (const file of process.argv.slice(2)) {
  const text = fs.readFileSync(file, "utf8");
  const value = Number(text.match(/complexity=(\d+)/)?.[1]);
  if (value) diagnostics.push({code:"C901", filename:file, location:{row:4}, message:`foo is too complex (${value} > 10)`});
  if (text.includes("RUFF_PARTIAL")) diagnostics.push({code:"C901", filename:file, location:{row:5}, message:"missing score"});
}
process.stdout.write(JSON.stringify(diagnostics));
process.exit(diagnostics.length ? 1 : 0);
NODE
SCRIPT
  cat >"$root/.venv/bin/pylint" <<'SCRIPT'
#!/usr/bin/env bash
set -u
args=$(printf '%s\n' "$@")
for required in --output-format=json --disable=all --enable=R1702,C0302 --reports=no --score=no --persistent=no --max-nested-blocks=4 --max-module-lines=500; do
  grep -qx -- "$required" <<<"$args" || exit 2
done
files=()
for arg in "$@"; do case "$arg" in *.py|*.pyi) files+=("$arg") ;; esac; done
for file in "${files[@]}"; do
  content=$(<"$file")
  [[ "$content" == *PYLINT_PROCESS_FAIL* ]] && exit 2
  [[ "$content" == *PYLINT_MALFORMED* ]] && { printf 'not-json'; exit 8; }
done
node - "${files[@]}" <<'NODE'
const fs = require("fs");
const diagnostics = [];
let status = 0;
for (const file of process.argv.slice(2)) {
  const text = fs.readFileSync(file, "utf8");
  const add = (messageId, message) => diagnostics.push({"message-id":messageId, path:file, line:5, message});
  const depth = Number(text.match(/depth=(\d+)/)?.[1]);
  const lines = Number(text.match(/module_lines=(\d+)/)?.[1]);
  if (depth > 4) { add("R1702", `Too many nested blocks (${depth}/4)`); status |= 8; }
  if (lines > 500) { add("C0302", `Too many lines in module (${lines}/500)`); status |= 16; }
  if (text.includes("PYLINT_PARTIAL")) { add("R1702", "missing ratio"); status |= 8; }
}
process.stdout.write(JSON.stringify(diagnostics));
process.exit(status);
NODE
SCRIPT
  cat >"$root/node_modules/.bin/jscpd" <<'SCRIPT'
#!/usr/bin/env bash
set -u
config=""; previous=""; files=()
for arg in "$@"; do
  [ "$previous" = "--config" ] && config=$arg
  case "$arg" in *.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts|*.py|*.pyi) files+=("$arg") ;; esac
  previous=$arg
done
output=$(node -e '
const fs=require("fs"); const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
if (c.threshold!==100 || c.minLines!==5 || c.minTokens!==50 || c.mode!=="mild" || c.reporters?.length!==1 || c.reporters[0]!=="json") process.exit(2);
console.log(c.output);
' "$config") || exit 2
for file in "${files[@]}"; do
  content=$(<"$file")
  [[ "$content" == *JSCPD_PROCESS_FAIL* ]] && exit 2
  [[ "$content" == *JSCPD_MISSING* ]] && exit 0
done
mkdir -p "$output"
for file in "${files[@]}"; do
  content=$(<"$file")
  [[ "$content" == *JSCPD_MALFORMED* ]] && { printf 'not-json' >"$output/jscpd-report.json"; exit 0; }
done
node - "$output/jscpd-report.json" "${files[@]}" <<'NODE'
const fs=require("fs");
const [report,...files]=process.argv.slice(2);
const duplicates=[];
for (const file of files) {
  const text=fs.readFileSync(file,"utf8");
  const match=text.match(/duplicate=(\d+):([^\s]+)/);
  if (match) duplicates.push({lines:Number(match[1]), firstFile:{name:file,start:7}, secondFile:{name:match[2],start:9}});
  if (text.includes("JSCPD_PARTIAL")) duplicates.push({lines:"bad", firstFile:{name:file,start:7}, secondFile:{name:file,start:9}});
}
fs.writeFileSync(report, JSON.stringify({duplicates}));
NODE
SCRIPT
  chmod +x "$root/node_modules/.bin/oxlint" "$root/node_modules/.bin/jscpd" \
    "$root/.venv/bin/ruff" "$root/.venv/bin/pylint"
}

diff_for() {
  printf '%s\n' 'diff --git a/'"$1"' b/'"$1" '--- a/'"$1" '+++ b/'"$1" '@@ -0,0 +1 @@' '+changed'
}

run_lint() {
  local root=$1 diff=$2
  (cd "$root" && printf '%s' "$diff" | "$LINT") 2>&1
}

assert_result() {
  local what=$1 want_status=$2 needle=$3 root=$4 diff=$5 out status
  out=$(run_lint "$root" "$diff"); status=$?
  if [ "$status" -eq "$want_status" ] && [[ "$out" == *"$needle"* ]]; then
    pass "$what"
  else
    fail "$what (status=$status output='$out')"
  fi
}

assert_clean() {
  local what=$1 root=$2 diff=$3 out status
  out=$(run_lint "$root" "$diff"); status=$?
  if [ "$status" -eq 0 ] && [ -z "$out" ]; then pass "$what"; else fail "$what (status=$status output='$out')"; fi
}

repo="$TMP/repo"
mkdir -p "$repo/src"
make_tools "$repo"

for spec in \
  'complexity:10:0:' 'complexity:11:0:advisory' 'complexity:20:0:advisory' 'complexity:21:1:error' \
  'depth:4:0:' 'depth:5:0:advisory' 'depth:8:0:advisory' 'depth:9:1:error' \
  'module_lines:500:0:' 'module_lines:501:0:advisory' 'module_lines:1000:0:advisory' 'module_lines:1001:1:error' \
  'function_lines:100:0:' 'function_lines:101:0:advisory' 'function_lines:200:0:advisory' 'function_lines:201:1:error'; do
  IFS=: read -r metric value status severity <<<"$spec"
  file="src/ox-${metric}-${value}.ts"
  printf '%s=%s\n' "$metric" "$value" >"$repo/$file"
  if [ -n "$severity" ]; then
    assert_result "Oxlint $metric $value is $severity" "$status" "$severity: oxlint" "$repo" "$(diff_for "$file")"
  else
    assert_clean "Oxlint $metric $value is below the limit" "$repo" "$(diff_for "$file")"
  fi
done

printf 'cycle=true\n' >"$repo/src/cycle.ts"
assert_result "Oxlint import cycles block" 1 "error: oxlint import/no-cycle src/cycle.ts:3" "$repo" "$(diff_for src/cycle.ts)"

printf 'complexity=11\ndepth=5\nmodule_lines=501\n' >"$repo/src/python.py"
out=$(run_lint "$repo" "$(diff_for src/python.py)"); status=$?
if [ "$status" -eq 0 ] && [[ "$out" == *"advisory: ruff C901"* ]] && \
  [[ "$out" == *"advisory: pylint too-many-nested-blocks"* ]] && [[ "$out" == *"advisory: pylint too-many-lines"* ]]; then
  pass "Python runs Ruff and Pylint for one file"
else
  fail "Python runs Ruff and Pylint for one file (status=$status output='$out')"
fi

for spec in '4:0:' '5:0:advisory' '8:0:advisory' '9:1:error'; do
  IFS=: read -r value status severity <<<"$spec"
  file="src/py-depth-$value.py"; printf 'depth=%s\n' "$value" >"$repo/$file"
  if [ -n "$severity" ]; then assert_result "Pylint depth $value is $severity" "$status" "$severity: pylint" "$repo" "$(diff_for "$file")"; else assert_clean "Pylint depth $value is below the limit" "$repo" "$(diff_for "$file")"; fi
done

for spec in '500:0:' '501:0:advisory' '1000:0:advisory' '1001:1:error'; do
  IFS=: read -r value status severity <<<"$spec"
  file="src/py-lines-$value.py"; printf 'module_lines=%s\n' "$value" >"$repo/$file"
  if [ -n "$severity" ]; then assert_result "Pylint module lines $value is $severity" "$status" "$severity: pylint" "$repo" "$(diff_for "$file")"; else assert_clean "Pylint module lines $value is below the limit" "$repo" "$(diff_for "$file")"; fi
done

printf 'depth=5\nmodule_lines=501\n' >"$repo/src/pylint-status.py"
assert_result "Pylint accepts status bits 8 and 16 together" 0 "advisory: pylint" "$repo" "$(diff_for src/pylint-status.py)"

printf 'complexity=21\n' >"$repo/src/ruff-block.py"
assert_result "Ruff complexity 21 blocks" 1 "error: ruff C901 src/ruff-block.py:4 complexity 21" "$repo" "$(diff_for src/ruff-block.py)"

for spec in '5:0:advisory' '20:0:advisory' '21:1:error'; do
  IFS=: read -r value status severity <<<"$spec"
  first="src/duplicate-$value.ts"; second="src/duplicate-target-$value.ts"
  printf 'target=true\n' >"$repo/$second"
  printf 'duplicate=%s:%s\n' "$value" "$repo/$second" >"$repo/$first"
  diff="$(diff_for "$first")"$'\n'"$(diff_for "$second")"
  assert_result "jscpd duplicate $value is $severity" "$status" "$severity: jscpd duplicate-code $first:7 duplicate-lines $value" "$repo" "$diff"
done

printf 'OX_PROCESS_FAIL\nduplicate=5:%s/src/independent-target.ts\n' "$repo" >"$repo/src/independent.ts"
printf 'target=true\n' >"$repo/src/independent-target.ts"
diff="$(diff_for src/independent.ts)"$'\n'"$(diff_for src/independent-target.ts)"
out=$(run_lint "$repo" "$diff"); status=$?
if [ "$status" -eq 0 ] && [[ "$out" == *"skip: oxlint: tool process failed"* ]] && [[ "$out" == *"advisory: jscpd"* ]]; then pass "tool failures are independent"; else fail "tool failures are independent (status=$status output='$out')"; fi

printf 'RUFF_PROCESS_FAIL\ndepth=5\n' >"$repo/src/ruff-fail.py"
out=$(run_lint "$repo" "$(diff_for src/ruff-fail.py)"); status=$?
if [ "$status" -eq 0 ] && [[ "$out" == *"skip: ruff: tool process failed"* ]] && [[ "$out" == *"advisory: pylint"* ]]; then pass "Ruff failure does not suppress Pylint"; else fail "Ruff failure does not suppress Pylint (status=$status output='$out')"; fi

printf 'PYLINT_PROCESS_FAIL\ncomplexity=11\n' >"$repo/src/pylint-fail.py"
out=$(run_lint "$repo" "$(diff_for src/pylint-fail.py)"); status=$?
if [ "$status" -eq 0 ] && [[ "$out" == *"skip: pylint: tool process failed"* ]] && [[ "$out" == *"advisory: ruff"* ]]; then pass "Pylint failure does not suppress Ruff"; else fail "Pylint failure does not suppress Ruff (status=$status output='$out')"; fi

for marker in OX_MALFORMED RUFF_MALFORMED PYLINT_MALFORMED JSCPD_MALFORMED JSCPD_MISSING JSCPD_PROCESS_FAIL; do
  extension=ts; [[ "$marker" == RUFF_* || "$marker" == PYLINT_* ]] && extension=py
  file="src/${marker,,}.$extension"; printf '%s\n' "$marker" >"$repo/$file"
  assert_result "$marker fails open" 0 "skip:" "$repo" "$(diff_for "$file")"
done

printf 'OX_RULE_UNAVAILABLE\n' >"$repo/src/ox-rule-unavailable.ts"
assert_result "unavailable Oxlint rules fail open" 0 "skip: oxlint: analyzer rules unavailable" "$repo" "$(diff_for src/ox-rule-unavailable.ts)"

printf 'duplicate=5:%s/outside.ts\n' "$TMP" >"$repo/src/bad-clone.ts"
printf 'outside=true\n' >"$TMP/outside.ts"
assert_result "jscpd reports an unselected clone path" 0 "skip: jscpd: 1 mapped diagnostic(s) could not be parsed" "$repo" "$(diff_for src/bad-clone.ts)"

for spec in \
  'oxlint:ts:OX_PARTIAL:advisory: oxlint complexity' \
  'ruff:py:RUFF_PARTIAL:advisory: ruff C901' \
  'pylint:py:PYLINT_PARTIAL:advisory: pylint too-many-nested-blocks'; do
  IFS=: read -r tool extension marker finding <<<"$spec"
  file="src/partial-$tool.$extension"
  if [ "$tool" = pylint ]; then printf 'depth=5\n%s\n' "$marker" >"$repo/$file"; else printf 'complexity=11\n%s\n' "$marker" >"$repo/$file"; fi
  out=$(run_lint "$repo" "$(diff_for "$file")"); status=$?
  if [ "$status" -eq 0 ] && [[ "$out" == *"$finding"* ]] && [[ "$out" == *"skip: $tool: 1 mapped diagnostic(s) could not be parsed"* ]]; then
    pass "$tool keeps valid findings beside one unparsed diagnostic"
  else
    fail "$tool keeps valid findings beside one unparsed diagnostic (status=$status output='$out')"
  fi
done

printf 'target=true\n' >"$repo/src/partial-jscpd-target.ts"
printf 'duplicate=5:%s/src/partial-jscpd-target.ts\nJSCPD_PARTIAL\n' "$repo" >"$repo/src/partial-jscpd.ts"
partial_jscpd_diff="$(diff_for src/partial-jscpd.ts)"$'\n'"$(diff_for src/partial-jscpd-target.ts)"
out=$(run_lint "$repo" "$partial_jscpd_diff"); status=$?
if [ "$status" -eq 0 ] && [[ "$out" == *"advisory: jscpd duplicate-code"* ]] && [[ "$out" == *"skip: jscpd: 1 mapped diagnostic(s) could not be parsed"* ]]; then
  pass "jscpd keeps valid clones beside one unparsed clone"
else
  fail "jscpd keeps valid clones beside one unparsed clone (status=$status output='$out')"
fi

printf 'complexity=11\ndiagnostic_path=%s/src/alias.ts\n' "$repo" >"$repo/src/alias-target.ts"
ln -s alias-target.ts "$repo/src/alias.ts"
assert_result "diagnostic path aliases resolve to the selected canonical file" 0 "advisory: oxlint complexity src/alias-target.ts" "$repo" "$(diff_for src/alias.ts)"

printf 'complexity=21\n' >"$repo/src/café.ts"
quoted_diff=$(printf '%s\n' \
  'diff --git "a/src/caf\303\251.ts" "b/src/caf\303\251.ts"' \
  '--- "a/src/caf\303\251.ts"' \
  '+++ "b/src/caf\303\251.ts"' \
  '@@ -0,0 +1 @@' \
  '+changed')
assert_result "quoted non-ASCII diff paths are decoded" 1 "error: oxlint complexity src/café.ts" "$repo" "$quoted_diff"

mkdir -p "$repo/tests" "$repo/src/__tests__"
printf 'complexity=21\n' >"$repo/tests/a.ts"
printf 'complexity=21\n' >"$repo/src/a.test.ts"
printf 'complexity=21\n' >"$repo/src/test_named.py"
excluded="$(diff_for tests/a.ts)"$'\n'"$(diff_for src/a.test.ts)"$'\n'"$(diff_for src/test_named.py)"
assert_clean "test files are excluded" "$repo" "$excluded"

header_like="$(diff_for src/cycle.ts)"$'\n''+++ value;'
assert_result "added code beginning with three pluses keeps the selected file" 1 "error: oxlint" "$repo" "$header_like"

missing="$TMP/missing"; mkdir -p "$missing/src"; printf 'complexity=21\n' >"$missing/src/no-tool.ts"
out=$(run_lint "$missing" "$(diff_for src/no-tool.ts)"); status=$?
if [ "$status" -eq 0 ] && [[ "$out" == *"skip: oxlint: no repository-local tool"* ]] && [[ "$out" == *"skip: jscpd: no repository-local tool"* ]]; then pass "missing local tools fail open"; else fail "missing local tools fail open (status=$status output='$out')"; fi

printf 'complexity=21\n' >"$TMP/outside.ts"
assert_clean "path traversal is ignored" "$repo" "$(diff_for ../outside.ts)"
ln -s "$TMP/outside.ts" "$repo/src/outside-link.ts"
assert_clean "symlink traversal is ignored" "$repo" "$(diff_for src/outside-link.ts)"

complexity_skills=$(grep -Rl 'complexity-lint' "$HARNESS_SOURCE/skills" | sort)
if [ "$complexity_skills" = "$HARNESS_SOURCE/skills/lazar-commit/SKILL.md" ]; then pass "only lazar-commit invokes complexity-lint"; else fail "only lazar-commit invokes complexity-lint (found '$complexity_skills')"; fi

if [ "$failures" -eq 0 ]; then printf '\nall complexity-lint cases passed\n'; exit 0; fi
printf '\n%d complexity-lint case(s) failed\n' "$failures" >&2
exit 1
