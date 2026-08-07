#!/usr/bin/env node
/**
 * comment-lint: a runtime-neutral guard that enforces the *shape* half of
 * PHILOSOPHY §21 on comments an agent writes, so floating what-comments and
 * walls of prose get bounced back in-loop instead of at review.
 *
 * It cannot judge why-vs-what (that needs a reader, and clarity-reviewer does it
 * at review time). It judges what a regex can: a full-line comment in a language
 * that has a doc-comment form is a comment sitting where §21 says it shouldn't,
 * because the fix is to move it onto the symbol or onto the line. Doc-comments,
 * tooling directives, shebangs, license headers, and trailing on-the-line
 * comments pass. A density cap catches a wall even when each line is allowed. It
 * weighs lines and characters both, because a wall hides from each one differently.
 *
 * Modes:
 *   comment-lint claude-hook   stdin = Claude Code PostToolUse JSON; writes the §21
 *                              reason to stderr and exits 2 on violation, so Claude revises.
 *   comment-lint diff          stdin = unified (git/jj) diff; lints added lines.
 *                              Exit 1 on violation. The lazar-commit gate.
 *
 * Fail-open by construction: any internal error exits 0 and blocks nothing. A
 * linter bug must never brick a session or a commit.
 */

const DENSITY_LINE_RATIO = 0.3;
const DENSITY_MIN_COMMENT_LINES = 4;
const DENSITY_CHAR_RATIO = 0.4;
/** Four normally-wrapped lines of prose, so both floors admit the same size of why. */
const DENSITY_MIN_COMMENT_CHARS = 250;
const LICENSE_HEADER_SCAN_LINES = 5;

const C_STYLE = "c-style";
const PYTHON = "python";

const LANG_BY_EXT = {
  ts: C_STYLE, tsx: C_STYLE, mts: C_STYLE, cts: C_STYLE,
  js: C_STYLE, jsx: C_STYLE, mjs: C_STYLE, cjs: C_STYLE,
  rs: C_STYLE, go: C_STYLE, java: C_STYLE, cs: C_STYLE,
  swift: C_STYLE, kt: C_STYLE, kts: C_STYLE, scala: C_STYLE,
  c: C_STYLE, h: C_STYLE, cpp: C_STYLE, hpp: C_STYLE, cc: C_STYLE, hh: C_STYLE,
  php: C_STYLE,
  py: PYTHON, pyi: PYTHON,
};

const DIRECTIVE = /(eslint-disable|eslint-enable|prettier-ignore|biome-ignore|@ts-expect-error|@ts-ignore|@ts-nocheck|@ts-check|tslint:|deno-lint-ignore|v8\s+ignore|c8\s+ignore|istanbul\s+ignore|type:\s*ignore|noqa|pylint:|pyright:\s*ignore|ruff:|mypy:|fmt:\s*(on|off)|pragma|go:[a-z]+|@license|SPDX-License-Identifier)/i;

const LICENSE = /(copyright|licen[cs]e|SPDX-License-Identifier|@license|all rights reserved)/i;

const DECISION_HEADER =
  "comment-lint (PHILOSOPHY §21): the code you just wrote adds comments that don't earn their keep.";

const FIX_MENU = [
  "§21: default to no comments. A comment earns its keep only for a non-obvious constraint, a workaround for a named external bug, or a surprising algorithmic choice, and even then it must be native (attached to its symbol).",
  "Fix, in order of preference:",
  "  1. Make the code say it. A rename or an extracted function usually removes the need for the comment.",
  "  2. If it's a genuine why about a symbol, attach it as a doc-comment on that symbol (/** */ or /// in C-style, a docstring in Python).",
  "  3. If it's a why about one line, put it as a trailing comment on that line, not floating above it.",
  "  4. If it's prose that explains the module, move it to docs.",
  "Don't just delete a real why. Move it.",
].join("\n");

function extensionOf(fileName) {
  const base = fileName.split("/").pop() || "";
  const dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(dot + 1).toLowerCase() : "";
}

function langOf(fileName) {
  return LANG_BY_EXT[extensionOf(fileName)] || null;
}

function stripStrings(line) {
  let out = "";
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote) {
      if (ch === "\\") { out += "  "; i++; continue; }
      if (ch === quote) { quote = null; out += " "; continue; }
      out += " ";
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") { quote = ch; out += " "; continue; }
    out += ch;
  }
  return out;
}

function isDirective(commentText) {
  return DIRECTIVE.test(commentText);
}

function classify(kind, countsToDensity) {
  return { kind, countsToDensity };
}

function mk(line, raw, kind, countsToDensity, chars) {
  return { line, snippet: raw.trim(), chars, ...classify(kind, countsToDensity) };
}

function scanCStyle(lines) {
  const comments = [];
  let inBlock = false;
  let blockIsDoc = false;
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    if (inBlock) {
      comments.push(mk(i, raw, blockIsDoc ? "doc" : "loose", true, weightOf(raw)));
      if (raw.includes("*/")) inBlock = false;
      continue;
    }
    const stripped = stripStrings(raw);
    const lineIdx = stripped.indexOf("//");
    const blockIdx = stripped.indexOf("/*");
    const idx = pickFirst(lineIdx, blockIdx);
    if (idx < 0) continue;
    const trailing = raw.slice(0, idx).trim().length > 0;
    const text = raw.slice(idx);
    if (idx === blockIdx && (blockIdx <= lineIdx || lineIdx < 0)) {
      const isDoc = raw.startsWith("/**", idx) || raw[idx + 2] === "*";
      if (raw.indexOf("*/", idx + 2) < 0) { inBlock = true; blockIsDoc = isDoc; }
      if (isDirective(text)) { comments.push(mk(i, raw, "directive", false, 0)); continue; }
      if (isDoc) { comments.push(mk(i, raw, "doc", true, weightOf(text))); continue; }
      comments.push(mk(i, raw, trailing ? "trailing" : "loose", true, weightOf(text)));
      continue;
    }
    const isDoc = text.startsWith("///") || text.startsWith("//!");
    if (isDirective(text)) { comments.push(mk(i, raw, "directive", false, 0)); continue; }
    if (isLicenseHeader(i, text)) { comments.push(mk(i, raw, "license", false, 0)); continue; }
    if (isDoc) { comments.push(mk(i, raw, "doc", true, weightOf(text))); continue; }
    comments.push(mk(i, raw, trailing ? "trailing" : "loose", true, weightOf(text)));
  }
  return comments;
}

function scanPython(lines) {
  const comments = [];
  let inTriple = null;
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    if (i === 0 && raw.startsWith("#!")) { comments.push(mk(i, raw, "shebang", false, 0)); continue; }
    const r = scanPythonLine(raw, inTriple);
    inTriple = r.triple;
    if (r.index < 0) continue;
    const text = raw.slice(r.index);
    if (isDirective(text)) { comments.push(mk(i, raw, "directive", false, 0)); continue; }
    if (isLicenseHeader(i, text)) { comments.push(mk(i, raw, "license", false, 0)); continue; }
    comments.push(mk(i, raw, r.codeBefore ? "trailing" : "loose", true, weightOf(text)));
  }
  return comments;
}

/**
 * Scans one physical line for the first `#` outside every string, so a `#` inside a
 * single/double/triple-quoted span is never read as a comment. Carries the incoming triple
 * state out. Two edges the earlier slice approach got wrong (a `#` comment holding a stray
 * `"""`, and a trailing comment on a docstring's closing line) fall out correctly here,
 * because it stops at the first real `#` and counts a closing triple as code on the line.
 */
function scanPythonLine(line, inTriple) {
  let i = 0;
  let codeBefore = false;
  if (inTriple) {
    const close = line.indexOf(inTriple);
    if (close < 0) return { index: -1, codeBefore: false, triple: inTriple };
    i = close + 3;
    codeBefore = true;
  }
  while (i < line.length) {
    const ch = line[i];
    if (ch === '"' || ch === "'") {
      codeBefore = true;
      const triple = line.slice(i, i + 3);
      if (triple === '"""' || triple === "'''") {
        const close = line.indexOf(triple, i + 3);
        if (close < 0) return { index: -1, codeBefore, triple };
        i = close + 3;
        continue;
      }
      i++;
      while (i < line.length) {
        if (line[i] === "\\") { i += 2; continue; }
        if (line[i] === ch) { i++; break; }
        i++;
      }
      continue;
    }
    if (ch === "#") return { index: i, codeBefore, triple: null };
    if (ch !== " " && ch !== "\t") codeBefore = true;
    i++;
  }
  return { index: -1, codeBefore, triple: null };
}

function isLicenseHeader(lineIndex, text) {
  return lineIndex < LICENSE_HEADER_SCAN_LINES && LICENSE.test(text);
}

function pickFirst(a, b) {
  if (a < 0) return b;
  if (b < 0) return a;
  return Math.min(a, b);
}

/** Non-whitespace only, so a reflow to a different wrap width cannot move the number. */
function weightOf(text) {
  return text.replace(/\s/g, "").length;
}

function lint(fileName, text) {
  const lang = langOf(fileName);
  if (!lang) return { violations: [], density: null };
  const lines = text.split("\n");
  const comments = lang === PYTHON ? scanPython(lines) : scanCStyle(lines);
  const loose = comments.filter((c) => c.kind === "loose");
  const counted = comments.filter((c) => c.countsToDensity);
  return {
    violations: loose,
    density: weighDensity({
      commentLines: counted.length,
      nonBlank: lines.filter((l) => l.trim().length > 0).length || 1,
      commentChars: counted.reduce((sum, c) => sum + c.chars, 0),
      allChars: weightOf(text) || 1,
    }),
  };
}

/**
 * Two measures, either of which trips, because a wall hides from each one differently.
 * Prose wrapped long is few lines and most of the characters; a comment beside every
 * line of code is most of the lines and few of the characters. Each floor keeps a
 * genuine short why below the ratio it would otherwise fail.
 */
function weighDensity({ commentLines, nonBlank, commentChars, allChars }) {
  const lineRatio = commentLines / nonBlank;
  const charRatio = commentChars / allChars;
  const byLine = commentLines >= DENSITY_MIN_COMMENT_LINES && lineRatio > DENSITY_LINE_RATIO;
  const byChar = commentChars >= DENSITY_MIN_COMMENT_CHARS && charRatio > DENSITY_CHAR_RATIO;
  if (!byLine && !byChar) return null;
  return {
    commentLines,
    nonBlank,
    linePct: Math.round(lineRatio * 100),
    charPct: Math.round(charRatio * 100),
    byChar,
  };
}

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => (data += c));
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", () => resolve(data));
  });
}

function candidatesFromHook(payload) {
  const input = payload.tool_input || {};
  const file = input.file_path || input.filePath || "";
  const out = [];
  if (typeof input.content === "string") out.push({ file, text: input.content });
  if (typeof input.new_string === "string") out.push({ file, text: input.new_string });
  if (typeof input.new_content === "string") out.push({ file, text: input.new_content });
  if (Array.isArray(input.edits)) {
    for (const e of input.edits) {
      if (e && typeof e.new_string === "string") out.push({ file, text: e.new_string });
    }
  }
  return out;
}

function reasonFor(results) {
  const parts = [DECISION_HEADER, ""];
  for (const r of results) {
    if (r.violations.length > 0) {
      parts.push(`${r.file}: ${r.violations.length} floating comment(s):`);
      for (const v of r.violations.slice(0, 12)) {
        parts.push(`  ${v.snippet.slice(0, 100)}`);
      }
    }
    if (r.density) parts.push(densityLine(r.file, r.density));
    parts.push("");
  }
  parts.push(FIX_MENU);
  return parts.join("\n");
}

function densityLine(file, d) {
  const measure = d.byChar
    ? `${d.charPct}% of the text is comment, across ${d.commentLines} comment line(s)`
    : `${d.linePct}% of the lines are comment (${d.commentLines} of ${d.nonBlank})`;
  return `${file}: ${measure}. That reads as a wall; keep only the load-bearing ones.`;
}

async function runClaudeHook() {
  const data = await readStdin();
  let payload;
  try {
    payload = JSON.parse(data);
  } catch {
    process.exit(0);
  }
  const results = [];
  for (const cand of candidatesFromHook(payload)) {
    if (!cand.file) continue;
    const r = lint(cand.file, cand.text);
    if (r.violations.length > 0 || r.density) results.push({ file: cand.file, ...r });
  }
  if (results.length === 0) process.exit(0);
  process.stderr.write(reasonFor(results) + "\n");
  process.exit(2);
}

function parseDiff(diff) {
  const files = new Map();
  let current = null;
  for (const line of diff.split("\n")) {
    if (line.startsWith("+++ ")) {
      const path = line.slice(4).replace(/^b\//, "").trim();
      current = path === "/dev/null" ? null : path;
      if (current && !files.has(current)) files.set(current, []);
      continue;
    }
    if (current && line.startsWith("+") && !line.startsWith("+++")) {
      files.get(current).push(line.slice(1));
    }
  }
  return files;
}

async function runDiff() {
  const files = parseDiff(await readStdin());
  const results = [];
  for (const [file, added] of files) {
    if (!langOf(file)) continue;
    const r = lint(file, added.join("\n"));
    if (r.violations.length > 0 || r.density) results.push({ file, ...r });
  }
  reportAndExit(results);
}

function reportAndExit(results) {
  if (results.length === 0) process.exit(0);
  process.stderr.write(reasonFor(results) + "\n");
  process.exit(1);
}

async function main() {
  const mode = process.argv[2];
  try {
    if (mode === "claude-hook") return await runClaudeHook();
    if (mode === "diff") return await runDiff();
    process.stderr.write("usage: comment-lint <claude-hook|diff>\n");
    process.exit(0);
  } catch {
    process.exit(0);
  }
}

main();
