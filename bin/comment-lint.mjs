#!/usr/bin/env node

import { readFileSync } from "node:fs";

const C_STYLE = "c-style";
const PYTHON = "python";
const LANG_BY_EXT = {
  ts: C_STYLE, tsx: C_STYLE, mts: C_STYLE, cts: C_STYLE,
  js: C_STYLE, jsx: C_STYLE, mjs: C_STYLE, cjs: C_STYLE,
  rs: C_STYLE, go: C_STYLE, java: C_STYLE, cs: C_STYLE,
  swift: C_STYLE, kt: C_STYLE, kts: C_STYLE, scala: C_STYLE,
  c: C_STYLE, h: C_STYLE, cpp: C_STYLE, hpp: C_STYLE, cc: C_STYLE, hh: C_STYLE,
  php: C_STYLE, py: PYTHON, pyi: PYTHON,
};

const DIRECTIVE = /(eslint-disable|eslint-enable|prettier-ignore|biome-ignore|@ts-expect-error|@ts-ignore|@ts-nocheck|@ts-check|tslint:|deno-lint-ignore|v8\s+ignore|c8\s+ignore|istanbul\s+ignore|type:\s*ignore|noqa|pylint:|pyright:\s*ignore|ruff:|mypy:|fmt:\s*(on|off)|pragma|go:[a-z]+|@license|SPDX-License-Identifier)/i;
const LICENSE = /(copyright|licen[cs]e|SPDX-License-Identifier|@license|all rights reserved)/i;
const LICENSE_HEADER_SCAN_LINES = 5;
const DECISION_HEADER =
  "comment-lint (PHILOSOPHY §21): the code you wrote adds prose comments.";
const FIX_MENU = [
  "Every new non-exempt comment is prohibited.",
  "Make the code say it, or move longer explanation to docs.",
  "Only shebangs, leading license headers, and recognized tooling directives are exempt.",
].join("\n");

function extensionOf(fileName) {
  const base = fileName.split("/").pop() || "";
  const dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(dot + 1).toLowerCase() : "";
}

function langOf(fileName) {
  return LANG_BY_EXT[extensionOf(fileName)] || null;
}

function normalizedToken(text) {
  return text
    .replace(/^\/\*+|\*+\/$/g, "")
    .replace(/^\s*(?:\/\/\/?|#|\*)\s?/gm, "")
    .replace(/\s+/g, " ")
    .trim();
}

function comment(line, raw, kind = "prose") {
  return {
    line,
    endLine: line + (raw.match(/\n/g) || []).length,
    snippet: raw.trim(),
    token: normalizedToken(raw),
    kind,
  };
}

function exemptKind(text, line, raw, leading = false) {
  if (line === 1 && raw.startsWith("#!")) return "shebang";
  if (DIRECTIVE.test(text)) return "directive";
  if (leading && line <= LICENSE_HEADER_SCAN_LINES && LICENSE.test(text)) return "license";
  return "prose";
}

function scanCStyle(text, supportsRegex) {
  const comments = [];
  let line = 1;
  let i = 0;
  let quote = null;
  let inTemplate = false;
  const templateExpressions = [];
  let canStartRegex = true;
  while (i < text.length) {
    const ch = text[i];
    const next = text[i + 1];
    if (quote) {
      if (ch === "\\") { i += 2; continue; }
      if (ch === quote) quote = null;
      if (ch === "\n") line++;
      i++;
      continue;
    }
    if (inTemplate) {
      if (ch === "\\") { i += 2; continue; }
      if (ch === "`") { inTemplate = false; canStartRegex = false; i++; continue; }
      if (ch === "$" && next === "{") {
        templateExpressions.push(1);
        inTemplate = false;
        canStartRegex = true;
        i += 2;
        continue;
      }
      if (ch === "\n") line++;
      i++;
      continue;
    }
    if (ch === '"' || ch === "'") { quote = ch; canStartRegex = false; i++; continue; }
    if (ch === "`" && supportsRegex) { inTemplate = true; i++; continue; }
    if (ch === "\n") { line++; i++; continue; }
    if (ch === "/" && next === "/") {
      const start = i;
      const startLine = line;
      const end = text.indexOf("\n", i + 2);
      i = end < 0 ? text.length : end;
      const raw = text.slice(start, i);
      const leading = text.slice(0, start).replace(/^#![^\n]*\n/, "").trim() === "";
      comments.push(comment(startLine, raw, exemptKind(raw, startLine, raw, leading)));
      continue;
    }
    if (ch === "/" && next === "*") {
      const start = i;
      const startLine = line;
      const close = text.indexOf("*/", i + 2);
      i = close < 0 ? text.length : close + 2;
      const raw = text.slice(start, i);
      line += (raw.match(/\n/g) || []).length;
      const leading = text.slice(0, start).replace(/^#![^\n]*\n/, "").trim() === "";
      comments.push(comment(startLine, raw, exemptKind(raw, startLine, raw, leading)));
      continue;
    }
    if (ch === "/" && supportsRegex && canStartRegex) {
      const regex = skipRegex(text, i);
      if (regex !== null) {
        line += (text.slice(i, regex).match(/\n/g) || []).length;
        i = regex;
        canStartRegex = false;
        continue;
      }
    }
    if (/[A-Za-z_$]/.test(ch)) {
      const start = i;
      while (i < text.length && /[A-Za-z0-9_$]/.test(text[i])) i++;
      canStartRegex = /^(?:return|case|throw|yield|await)$/.test(text.slice(start, i));
      continue;
    }
    if (/[0-9]/.test(ch)) {
      while (i < text.length && /[0-9A-Fa-f_xXn.]/.test(text[i])) i++;
      canStartRegex = false;
      continue;
    }
    if (templateExpressions.length > 0 && ch === "{") {
      templateExpressions[templateExpressions.length - 1]++;
      i++;
      continue;
    }
    if (templateExpressions.length > 0 && ch === "}") {
      templateExpressions[templateExpressions.length - 1]--;
      if (templateExpressions[templateExpressions.length - 1] === 0) {
        templateExpressions.pop();
        inTemplate = true;
      }
      i++;
      continue;
    }
    if (!/\s/.test(ch)) canStartRegex = !/[)\]}]/.test(ch);
    i++;
  }
  return comments;
}

function skipRegex(text, start) {
  let inClass = false;
  for (let i = start + 1; i < text.length; i++) {
    const ch = text[i];
    if (ch === "\n") return null;
    if (ch === "\\") { i++; continue; }
    if (ch === "[") { inClass = true; continue; }
    if (ch === "]") { inClass = false; continue; }
    if (ch === "/" && !inClass) {
      i++;
      while (i < text.length && /[A-Za-z]/.test(text[i])) i++;
      return i;
    }
  }
  return null;
}

function scanPython(text) {
  const comments = [];
  const lines = text.split("\n");
  let triple = null;
  for (let index = 0; index < lines.length; index++) {
    const raw = lines[index];
    const result = scanPythonLine(raw, triple);
    triple = result.triple;
    if (result.index < 0) continue;
    const tokenText = raw.slice(result.index);
    const line = index + 1;
    comments.push(comment(line, tokenText, exemptKind(tokenText, line, raw)));
  }
  return comments;
}

function scanPythonLine(line, inTriple) {
  let i = 0;
  if (inTriple) {
    const close = line.indexOf(inTriple);
    if (close < 0) return { index: -1, triple: inTriple };
    i = close + 3;
  }
  while (i < line.length) {
    const ch = line[i];
    if (ch === '"' || ch === "'") {
      const triple = line.slice(i, i + 3);
      if (triple === '\"\"\"' || triple === "'''") {
        const close = line.indexOf(triple, i + 3);
        if (close < 0) return { index: -1, triple };
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
    if (ch === "#") return { index: i, triple: null };
    i++;
  }
  return { index: -1, triple: null };
}

function tokensFor(fileName, text) {
  const lang = langOf(fileName);
  if (!lang) return [];
  const comments = lang === PYTHON
    ? scanPython(text)
    : scanCStyle(text, /^(?:[cm]?[jt]sx?|mjs)$/.test(extensionOf(fileName)));
  const licenseEnd = leadingLicenseEnd(text, lang);
  return comments.filter(
    (item) => item.kind === "prose" && item.line > licenseEnd && item.token.length > 0,
  );
}

function leadingLicenseEnd(text, lang) {
  const lines = text.split("\n");
  let index = lines[0]?.startsWith("#!") ? 1 : 0;
  while (index < lines.length && lines[index].trim() === "") index++;
  const start = index;
  const prefix = lang === PYTHON ? /^\s*#/ : /^\s*\/\//;
  while (index < lines.length && prefix.test(lines[index])) index++;
  if (index === start) return 0;
  return LICENSE.test(lines.slice(start, index).join("\n")) ? index : 0;
}

function subtractTokens(oldTokens, newTokens) {
  const counts = new Map();
  for (const item of oldTokens) counts.set(item.token, (counts.get(item.token) || 0) + 1);
  return newTokens.filter((item) => {
    const count = counts.get(item.token) || 0;
    if (count === 0) return true;
    counts.set(item.token, count - 1);
    return false;
  });
}

function lintPair(file, oldText, newText) {
  return { file, violations: subtractTokens(tokensFor(file, oldText), tokensFor(file, newText)) };
}

function proseSourceLines(file, text) {
  const lines = text.split("\n");
  const prose = new Set();
  for (const token of tokensFor(file, text)) {
    for (let line = token.line; line <= token.endLine; line++) prose.add(lines[line - 1] ?? "");
  }
  return prose;
}

function lintDiffHunk(file, hunk, currentProse) {
  const direct = lintPair(file, hunk.removed.join("\n"), hunk.added.join("\n")).violations;
  const hasCommentSyntax = [...hunk.removed, ...hunk.added].some((line) =>
    line.includes("/*") || line.includes("*/") || /^\s*(?:\/\/|#)/.test(line),
  );
  if (hasCommentSyntax) return direct;
  const oldTokens = hunk.removed
    .filter((line) => currentProse.has(line))
    .map((line, index) => comment(index + 1, line));
  const removedComment = oldTokens.length > 0;
  const newTokens = hunk.added
    .filter((line) => currentProse.has(line) || (removedComment && /^\s*\*\s*\S/.test(line)))
    .map((line, index) => comment(index + 1, line));
  const inferred = subtractTokens(oldTokens, newTokens);
  return [...new Map([...direct, ...inferred].map((token) => [token.token, token])).values()];
}

function readExisting(file) {
  try {
    return readFileSync(file, "utf8");
  } catch {
    return "";
  }
}

function applyReplacement(text, oldText, newText) {
  const index = text.indexOf(oldText);
  if (index < 0) return null;
  return text.slice(0, index) + newText + text.slice(index + oldText.length);
}

function candidatesFromHook(payload) {
  const input = payload.tool_input || {};
  const file = input.file_path || input.filePath || "";
  if (!file) return [];
  const current = readExisting(file);
  const content = input.content ?? input.new_content ?? input.newContent;
  if (typeof content === "string") {
    const old = input.old_content ?? input.oldContent;
    return [{ file, oldText: typeof old === "string" ? old : current, newText: content }];
  }
  const oldString = input.old_string ?? input.oldString;
  const newString = input.new_string ?? input.newString;
  if (typeof newString === "string") {
    const oldText = typeof oldString === "string" ? oldString : "";
    const replaced = typeof oldString === "string" ? applyReplacement(current, oldString, newString) : null;
    return [{ file, oldText: replaced === null ? oldText : current, newText: replaced === null ? newString : replaced }];
  }
  if (Array.isArray(input.edits)) {
    const pairs = input.edits.flatMap((edit) => {
      const oldText = edit?.old_string ?? edit?.oldString;
      const newText = edit?.new_string ?? edit?.newString;
      return typeof oldText === "string" && typeof newText === "string"
        ? [{ file, oldText, newText }]
        : [];
    });
    let next = current;
    for (const pair of pairs) {
      const replaced = applyReplacement(next, pair.oldText, pair.newText);
      if (replaced === null) return pairs;
      next = replaced;
    }
    return [{ file, oldText: current, newText: next }];
  }
  return [];
}

function parseDiff(diff) {
  const files = new Map();
  let current = null;
  let hunk = null;
  let inFileHeader = false;
  for (const line of diff.split("\n")) {
    if (line.startsWith("diff --git ")) {
      current = null;
      inFileHeader = true;
      continue;
    }
    if (inFileHeader && line.startsWith("+++ ")) {
      const path = line.slice(4).replace(/^b\//, "").split("\t")[0].trim();
      current = path === "/dev/null" ? null : path;
      if (current && !files.has(current)) files.set(current, []);
      hunk = null;
      inFileHeader = false;
      continue;
    }
    if (current && line.startsWith("@@")) {
      hunk = { added: [], removed: [] };
      files.get(current).push(hunk);
      continue;
    }
    if (!current) continue;
    if (!hunk) {
      hunk = { added: [], removed: [] };
      files.get(current).push(hunk);
    }
    if (line.startsWith("+")) hunk.added.push(line.slice(1));
    else if (line.startsWith("-")) hunk.removed.push(line.slice(1));
    else if (line.startsWith(" ")) {
      hunk.added.push(line.slice(1));
      hunk.removed.push(line.slice(1));
    }
  }
  return files;
}

function reasonFor(results) {
  const parts = [DECISION_HEADER, ""];
  for (const result of results) {
    parts.push(`${result.file}: ${result.violations.length} new comment token(s):`);
    for (const violation of result.violations.slice(0, 12)) {
      parts.push(`  line ${violation.line}: ${violation.snippet.slice(0, 100)}`);
    }
    parts.push("");
  }
  parts.push(FIX_MENU);
  return parts.join("\n");
}

function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", () => resolve(data));
  });
}

async function runClaudeHook() {
  let payload;
  try {
    payload = JSON.parse(await readStdin());
  } catch {
    return;
  }
  const results = candidatesFromHook(payload)
    .map(({ file, oldText, newText }) => lintPair(file, oldText, newText))
    .filter((result) => result.violations.length > 0);
  if (results.length === 0) return;
  process.stderr.write(reasonFor(results) + "\n");
  process.exitCode = 2;
}

async function runDiff() {
  const results = [];
  for (const [file, hunks] of parseDiff(await readStdin())) {
    if (!langOf(file)) continue;
    const currentProse = proseSourceLines(file, readExisting(file));
    const violations = hunks.flatMap((hunk) => lintDiffHunk(file, hunk, currentProse));
    if (violations.length > 0) results.push({ file, violations });
  }
  if (results.length === 0) return;
  process.stderr.write(reasonFor(results) + "\n");
  process.exitCode = 1;
}

async function main() {
  try {
    if (process.argv[2] === "claude-hook") return await runClaudeHook();
    if (process.argv[2] === "diff") return await runDiff();
    process.stderr.write("usage: comment-lint <claude-hook|diff>\n");
  } catch {
    process.exitCode = 0;
  }
}

await main();
