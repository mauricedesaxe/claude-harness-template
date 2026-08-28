#!/usr/bin/env node

import { readFileSync } from "node:fs";

const C_STYLE = "c-style";
const PYTHON = "python";
const LANG_BY_EXT = {
  ts: C_STYLE, tsx: C_STYLE, mts: C_STYLE, cts: C_STYLE,
  js: C_STYLE, jsx: C_STYLE, mjs: C_STYLE, cjs: C_STYLE,
  go: C_STYLE, py: PYTHON, pyi: PYTHON,
};

const DIRECTIVE = /^(?:eslint-disable\b|eslint-enable\b|prettier-ignore\b|biome-ignore\b|@ts-expect-error\b|@ts-ignore\b|@ts-nocheck\b|@ts-check\b|tslint:|deno-lint-ignore\b|v8\s+ignore\b|c8\s+ignore\b|istanbul\s+ignore\b|type:\s*ignore\b|noqa\b|pylint:|pyright:\s*ignore\b|ruff:|mypy:|fmt:\s*(?:on|off)\b|go:[a-z]+\b|@license\b|SPDX-License-Identifier\b|#pragma\b|pragma\s*:)/i;
const LICENSE = /(copyright|licen[cs]e|SPDX-License-Identifier|@license|all rights reserved)/i;
const LICENSE_HEADER_SCAN_LINES = 5;
const DECISION_HEADER =
  "comment-lint (PHILOSOPHY §21): this change adds prose comments.";
const FIX_MENU = [
  "Delete narration that restates the code.",
  "Keep a comment only for a non-obvious invariant, an external workaround, or a surprising algorithmic choice.",
  "Use native symbol docs or an explicit Why: rationale when the explanation belongs at the code.",
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
  if (DIRECTIVE.test(normalizedToken(text))) return "directive";
  if (leading && line <= LICENSE_HEADER_SCAN_LINES && LICENSE.test(text)) return "license";
  return "prose";
}

function scanCStyle(text, isJavaScript) {
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
      if (ch === "\\" && quote !== "`") { i += 2; continue; }
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
    if (ch === "`" && isJavaScript) { inTemplate = true; i++; continue; }
    if (ch === "`" && !isJavaScript) { quote = ch; i++; continue; }
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
    if (ch === "/" && isJavaScript && canStartRegex) {
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
      if (triple === '"""' || triple === "'''") {
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
    (item) => item.kind === "prose" && item.line > licenseEnd && item.token.length > 0 &&
      !allowedComment(fileName, text, item),
  );
}

function allowedComment(fileName, text, item) {
  if (/^Why:\s+\S/i.test(item.token)) return true;
  if (/^(?:[cm]?[jt]sx?|mjs)$/.test(extensionOf(fileName)) && isJavaScriptDoc(text, item)) return true;
  return extensionOf(fileName) === "go" && isGoLineDoc(text, item);
}

function isJavaScriptDoc(text, item) {
  if (!item.snippet.startsWith("/**") && !item.snippet.startsWith("///")) return false;
  const lines = text.split("\n");
  if (!/^\s*(?:\/\*\*|\/\/\/)/.test(lines[item.line - 1] ?? "")) return false;
  const declaration = lines[item.endLine] ?? "";
  return /^\s*(?:(?:export|declare)\s+)*(?:default\s+)?(?:async\s+)?(?:function|class|interface|type|enum|namespace|const|let|var)\s+[A-Za-z_$]/.test(declaration) ||
    /^\s+(?:(?:public|private|protected|static|readonly|abstract|async|get|set)\s+)*[#A-Za-z_$][\w$#]*\s*(?:[(:=])/.test(declaration);
}

function isGoLineDoc(text, item) {
  const lines = text.split("\n");
  if (!item.snippet.startsWith("//") || !/^\s*\/\//.test(lines[item.line - 1] ?? "")) return false;
  let start = item.line - 1;
  while (start > 0 && /^\s*\/\//.test(lines[start - 1])) start--;
  let index = item.endLine;
  while (index < lines.length && /^\s*\/\//.test(lines[index])) index++;
  const declaration = lines[index]?.match(/^\s*(?:func\s+(?:\([^)]*\)\s*)?|type\s+|var\s+|const\s+)([A-Za-z_]\w*)/);
  return declaration !== null && normalizedToken(lines[start]).startsWith(declaration[1]);
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
  const file = input.file_path || "";
  if (!file) return [];
  const current = readExisting(file);
  const content = input.content ?? input.new_content;
  if (typeof content === "string") {
    const old = input.old_content;
    return [{ file, oldText: typeof old === "string" ? old : current, newText: content }];
  }
  const oldString = input.old_string;
  const newString = input.new_string;
  if (typeof newString === "string") {
    const oldText = typeof oldString === "string" ? oldString : "";
    const replaced = typeof oldString === "string" ? applyReplacement(current, oldString, newString) : null;
    return [{ file, oldText: replaced === null ? oldText : current, newText: replaced === null ? newString : replaced }];
  }
  if (Array.isArray(input.edits)) {
    const pairs = input.edits.flatMap((edit) => {
      const oldText = edit?.old_string;
      const newText = edit?.new_string;
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

function decodeDiffPath(value) {
  const raw = value.split("\t")[0].trim();
  const path = raw.startsWith('"') && raw.endsWith('"') ? decodeCQuoted(raw.slice(1, -1)) : raw;
  return path.replace(/^b\//, "");
}

function decodeCQuoted(value) {
  const bytes = [];
  const escapes = { a: 7, b: 8, t: 9, n: 10, v: 11, f: 12, r: 13, '"': 34, "\\": 92 };
  for (let index = 0; index < value.length; index++) {
    if (value[index] !== "\\") {
      const slash = value.indexOf("\\", index);
      const end = slash < 0 ? value.length : slash;
      bytes.push(...new TextEncoder().encode(value.slice(index, end)));
      index = end - 1;
      continue;
    }
    const octal = value.slice(index + 1).match(/^[0-7]{1,3}/)?.[0];
    if (octal) {
      bytes.push(Number.parseInt(octal, 8));
      index += octal.length;
      continue;
    }
    const escaped = value[++index];
    if (escaped === undefined) return "";
    bytes.push(escapes[escaped] ?? escaped.charCodeAt(0));
  }
  return new TextDecoder().decode(Uint8Array.from(bytes));
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
      const path = decodeDiffPath(line.slice(4));
      current = path === "/dev/null" ? null : path;
      if (current && !files.has(current)) files.set(current, { hunks: [], synthetic: false });
      hunk = null;
      inFileHeader = false;
      continue;
    }
    if (current && line.startsWith("@@")) {
      const range = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
      hunk = {
        oldStart: range ? Number(range[1]) : null,
        oldCount: range ? Number(range[2] ?? 1) : null,
        newStart: range ? Number(range[3]) : null,
        newCount: range ? Number(range[4] ?? 1) : null,
        operations: [],
      };
      files.get(current).hunks.push(hunk);
      if (!range) files.get(current).synthetic = true;
      continue;
    }
    if (!current) continue;
    if (!hunk) {
      hunk = { oldStart: null, oldCount: null, newStart: null, newCount: null, operations: [] };
      files.get(current).hunks.push(hunk);
      files.get(current).synthetic = true;
    }
    if (line.startsWith("+")) {
      hunk.operations.push({ kind: "+", text: line.slice(1) });
    } else if (line.startsWith("-")) {
      hunk.operations.push({ kind: "-", text: line.slice(1) });
    }
    else if (line.startsWith(" ")) {
      hunk.operations.push({ kind: " ", text: line.slice(1) });
    }
  }
  return files;
}

function reconstructOldFile(current, hunks) {
  const lines = current.split("\n");
  for (const hunk of [...hunks].reverse()) {
    const newLines = hunk.operations.filter((operation) => operation.kind !== "-").map((operation) => operation.text);
    const oldLines = hunk.operations.filter((operation) => operation.kind !== "+").map((operation) => operation.text);
    if (newLines.length !== hunk.newCount || oldLines.length !== hunk.oldCount) return null;
    const index = hunk.newStart - 1;
    if (index < 0 || lines.slice(index, index + newLines.length).some((line, offset) => line !== newLines[offset])) return null;
    lines.splice(index, newLines.length, ...oldLines);
  }
  return lines.join("\n");
}

function applySyntheticHunks(current, hunks) {
  const lines = current.split("\n");
  let cursor = 0;
  for (const hunk of hunks) {
    const oldLines = hunk.operations.filter((operation) => operation.kind !== "+").map((operation) => operation.text);
    const newLines = hunk.operations.filter((operation) => operation.kind !== "-").map((operation) => operation.text);
    if (oldLines.length === 0) {
      if (current !== "" || hunks.length !== 1 || hunk.operations.some((operation) => operation.kind !== "+")) return null;
      return newLines.join("\n");
    }
    const matches = [];
    for (let index = cursor; index <= lines.length - oldLines.length; index++) {
      if (oldLines.every((line, offset) => lines[index + offset] === line)) matches.push(index);
    }
    if (matches.length !== 1) return null;
    lines.splice(matches[0], oldLines.length, ...newLines);
    cursor = matches[0] + newLines.length;
  }
  return lines.join("\n");
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
  for (const [file, parsed] of parseDiff(await readStdin())) {
    if (!langOf(file)) continue;
    const current = readExisting(file);
    const compared = parsed.synthetic
      ? applySyntheticHunks(current, parsed.hunks)
      : reconstructOldFile(current, parsed.hunks);
    const violations = compared === null ? [] : parsed.synthetic
      ? lintPair(file, current, compared).violations
      : lintPair(file, compared, current).violations;
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
