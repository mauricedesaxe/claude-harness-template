#!/usr/bin/env node

import { accessSync, constants, existsSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = realpathSync(process.cwd());
const JAVASCRIPT_EXTENSIONS = new Set([".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"]);
const PYTHON_EXTENSIONS = new Set([".py", ".pyi"]);
const MAX_COMPLEXITY = 10;
const BLOCKING_COMPLEXITY = 20;

function isExecutable(file) {
  try {
    accessSync(file, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function readStdin() {
  return new Promise((resolveInput) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => (data += chunk));
    process.stdin.on("end", () => resolveInput(data));
    process.stdin.on("error", () => resolveInput(data));
  });
}

function changedPaths(diff) {
  const paths = new Set();
  let current = null;
  let changed = false;
  let inFileHeader = false;
  const flush = () => {
    if (current && changed) paths.add(current);
  };
  for (const line of diff.split("\n")) {
    if (line.startsWith("diff --git ")) {
      flush();
      current = null;
      changed = false;
      inFileHeader = true;
      continue;
    }
    if (inFileHeader && line.startsWith("+++ ")) {
      flush();
      const raw = line.slice(4).split("\t")[0].trim().replace(/^b\//, "");
      current = raw === "/dev/null" ? null : safePath(raw);
      changed = false;
      inFileHeader = false;
      continue;
    }
    if (current && (
      line.startsWith("+") || line.startsWith("-")
    )) changed = true;
  }
  flush();
  return [...paths].filter(isProductionSource);
}

function safePath(raw) {
  if (!raw || isAbsolute(raw)) return null;
  const absolute = resolve(ROOT, raw);
  if (absolute !== ROOT && !absolute.startsWith(ROOT + sep)) return null;
  if (!existsSync(absolute)) return null;
  const real = realpathSync(absolute);
  return real === ROOT || real.startsWith(ROOT + sep) ? real : null;
}

function isProductionSource(file) {
  if (!file) return false;
  const rel = relative(ROOT, file).replaceAll("\\", "/");
  const segments = rel.split("/");
  if (segments.some((segment) => ["test", "tests", "__tests__"].includes(segment))) return false;
  const name = basename(rel);
  if (/\.(?:test|spec)\./i.test(name)) return false;
  if (/^(?:test_.+|.+_test)\.py$/i.test(name)) return false;
  const extension = extname(name).toLowerCase();
  return JAVASCRIPT_EXTENSIONS.has(extension) || PYTHON_EXTENSIONS.has(extension);
}

function languageOf(file) {
  return PYTHON_EXTENSIONS.has(extname(file).toLowerCase()) ? "ruff" : "oxlint";
}

function findTool(file, tool) {
  let directory = dirname(file);
  while (directory === ROOT || directory.startsWith(ROOT + sep)) {
    const candidates = tool === "oxlint"
      ? [join(directory, "node_modules", ".bin", "oxlint")]
      : [join(directory, ".venv", "bin", "ruff"), join(directory, "venv", "bin", "ruff")];
    const found = candidates.find(isExecutable);
    if (found) return found;
    if (directory === ROOT) break;
    directory = dirname(directory);
  }
  return null;
}

function groupFiles(files) {
  const groups = new Map();
  const skipped = [];
  for (const file of files) {
    const tool = languageOf(file);
    const executable = findTool(file, tool);
    if (!executable) {
      if (!skipped.some((item) => item.tool === tool)) skipped.push({ tool, reason: "no repository-local tool" });
      continue;
    }
    const key = `${tool}\0${executable}`;
    if (!groups.has(key)) groups.set(key, { tool, executable, files: [] });
    groups.get(key).files.push(file);
  }
  return { groups: [...groups.values()], skipped };
}

function runOxlint(group) {
  const directory = mkdtempSync(join(tmpdir(), "complexity-lint-"));
  const config = join(directory, "oxlint.json");
  writeFileSync(config, JSON.stringify({
    rules: { complexity: ["error", { max: MAX_COMPLEXITY, variant: "classic" }] },
  }));
  try {
    const result = spawnSync(group.executable, [
      "--config", config,
      "--disable-nested-config",
      "--no-ignore",
      "--format", "json",
      ...group.files,
    ], { cwd: ROOT, encoding: "utf8" });
    return parseRun(group, result, parseOxlint);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function runRuff(group) {
  const result = spawnSync(group.executable, [
    "check",
    "--isolated",
    "--select", "C901",
    "--output-format", "json",
    "--config", `lint.mccabe.max-complexity = ${MAX_COMPLEXITY}`,
    ...group.files,
  ], { cwd: ROOT, encoding: "utf8" });
  return parseRun(group, result, parseRuff);
}

function parseRun(group, result, parser) {
  if (result.error || ![0, 1].includes(result.status)) {
    return { findings: [], skipped: [{ tool: group.tool, reason: "tool process failed" }] };
  }
  let output;
  try {
    output = JSON.parse(result.stdout || "[]");
  } catch {
    return { findings: [], skipped: [{ tool: group.tool, reason: "malformed JSON output" }] };
  }
  const findings = parser(output, new Set(group.files.map((file) => resolve(file))));
  if (findings === null || (result.status === 1 && findings.length === 0)) {
    return { findings: [], skipped: [{ tool: group.tool, reason: "complexity rule unavailable" }] };
  }
  return { findings, skipped: [] };
}

function parseOxlint(output, selected) {
  const diagnostics = [];
  if (Array.isArray(output)) {
    for (const entry of output) {
      if (Array.isArray(entry?.messages)) {
        for (const message of entry.messages) diagnostics.push({ ...message, file: entry.filePath ?? entry.filename });
      } else {
        diagnostics.push(entry);
      }
    }
  } else if (Array.isArray(output?.diagnostics)) {
    diagnostics.push(...output.diagnostics);
  } else {
    return null;
  }
  const findings = [];
  for (const diagnostic of diagnostics) {
    const rule = diagnostic?.ruleId ?? diagnostic?.rule_id ?? diagnostic?.code;
    if (typeof rule !== "string" || !/(?:^|\/)complexity$|^[^(]+\(complexity\)$/.test(rule)) continue;
    const message = diagnostic?.message;
    const score = scoreFromMessage(message);
    const line = diagnostic?.line ?? diagnostic?.location?.start?.line ??
      diagnostic?.span?.start?.line ?? diagnostic?.labels?.[0]?.span?.line;
    const file = validatedFile(diagnostic?.file ?? diagnostic?.filename ?? diagnostic?.filePath, selected);
    if (!file || !validDiagnostic(line, score, message)) continue;
    findings.push(finding("oxlint", file, line, score, message));
  }
  return findings;
}

function parseRuff(output, selected) {
  if (!Array.isArray(output)) return null;
  const findings = [];
  for (const diagnostic of output) {
    if (diagnostic?.code !== "C901") continue;
    const message = diagnostic?.message;
    const score = scoreFromMessage(message);
    const line = diagnostic?.location?.row;
    const file = validatedFile(diagnostic?.filename, selected);
    if (!file || !validDiagnostic(line, score, message)) continue;
    findings.push(finding("ruff", file, line, score, message));
  }
  return findings;
}

function scoreFromMessage(message) {
  if (typeof message !== "string") return null;
  const match = message.match(/(?:complexity\s+(?:of|is)|too complex\s*\()\s*(\d+)/i);
  return match ? Number(match[1]) : null;
}

function validatedFile(file, selected) {
  if (typeof file !== "string") return null;
  const absolute = resolve(ROOT, file);
  return selected.has(absolute) ? absolute : null;
}

function validDiagnostic(line, score, message) {
  return Number.isInteger(line) && line > 0 && Number.isInteger(score) && score > MAX_COMPLEXITY && typeof message === "string";
}

function finding(tool, file, line, score, message) {
  return {
    tool,
    path: relative(ROOT, file).replaceAll("\\", "/"),
    line,
    score,
    message,
    severity: score > BLOCKING_COMPLEXITY ? "error" : "advisory",
  };
}

function report(findings, skipped) {
  for (const item of findings) {
    process.stderr.write(`${item.severity}: ${item.tool} ${item.path}:${item.line} score ${item.score}: ${item.message}\n`);
  }
  for (const item of skipped) process.stderr.write(`skip: ${item.tool}: ${item.reason}\n`);
}

async function main() {
  try {
    const files = changedPaths(await readStdin());
    const { groups, skipped } = groupFiles(files);
    const findings = [];
    for (const group of groups) {
      const result = group.tool === "oxlint" ? runOxlint(group) : runRuff(group);
      findings.push(...result.findings);
      skipped.push(...result.skipped);
    }
    report(findings, skipped);
    if (findings.some((item) => item.severity === "error")) process.exitCode = 1;
  } catch {
    process.stderr.write("skip: complexity-lint: internal failure\n");
    process.exitCode = 0;
  }
}

await main();
