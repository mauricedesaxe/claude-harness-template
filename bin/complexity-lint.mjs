#!/usr/bin/env node

import { accessSync, constants, existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";

const ROOT = realpathSync(process.cwd());
const JAVASCRIPT_EXTENSIONS = new Set([".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts"]);
const PYTHON_EXTENSIONS = new Set([".py", ".pyi"]);
const LIMITS = {
  complexity: { maximum: 10, blockingAbove: 20 },
  depth: { maximum: 4, blockingAbove: 8 },
  "module-lines": { maximum: 500, blockingAbove: 1000 },
  "function-lines": { maximum: 100, blockingAbove: 200 },
  "duplicate-lines": { minimum: 5, blockingAbove: 20 },
};

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
    if (current && (line.startsWith("+") || line.startsWith("-"))) changed = true;
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
  return PYTHON_EXTENSIONS.has(extname(file).toLowerCase()) ? "python" : "javascript";
}

function findTool(file, tool) {
  let directory = dirname(file);
  while (directory === ROOT || directory.startsWith(ROOT + sep)) {
    const candidates = tool === "pylint"
      ? [join(directory, ".venv", "bin", "pylint"), join(directory, "venv", "bin", "pylint")]
      : tool === "ruff"
        ? [join(directory, ".venv", "bin", "ruff"), join(directory, "venv", "bin", "ruff")]
        : [join(directory, "node_modules", ".bin", tool)];
    const found = candidates.find(isExecutable);
    if (found) return found;
    if (directory === ROOT) break;
    directory = dirname(directory);
  }
  return null;
}

function groupsForTool(files, tool) {
  const groups = new Map();
  let missing = false;
  for (const file of files) {
    const executable = findTool(file, tool);
    if (!executable) {
      missing = true;
      continue;
    }
    if (!groups.has(executable)) groups.set(executable, { tool, executable, files: [] });
    groups.get(executable).files.push(file);
  }
  return {
    groups: [...groups.values()],
    skipped: missing ? [{ tool, reason: "no repository-local tool" }] : [],
  };
}

function runOxlint(group) {
  const directory = mkdtempSync(join(tmpdir(), "complexity-lint-oxlint-"));
  const config = join(directory, "oxlint.json");
  writeFileSync(config, JSON.stringify({
    plugins: ["import"],
    rules: {
      complexity: ["error", { max: LIMITS.complexity.maximum, variant: "classic" }],
      "max-depth": ["error", LIMITS.depth.maximum],
      "import/no-cycle": "error",
      "max-lines": ["error", { max: LIMITS["module-lines"].maximum, skipBlankLines: false, skipComments: false }],
      "max-lines-per-function": ["error", {
        max: LIMITS["function-lines"].maximum,
        skipBlankLines: false,
        skipComments: false,
        IIFEs: false,
      }],
    },
  }));
  try {
    const result = spawnSync(group.executable, [
      "--config", config,
      "--disable-nested-config",
      "--no-ignore",
      "--format", "json",
      ...group.files,
    ], { cwd: ROOT, encoding: "utf8" });
    return parseJsonRun(group, result, parseOxlint);
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
    "--config", `lint.mccabe.max-complexity = ${LIMITS.complexity.maximum}`,
    ...group.files,
  ], { cwd: ROOT, encoding: "utf8" });
  return parseJsonRun(group, result, parseRuff);
}

function runPylint(group) {
  const result = spawnSync(group.executable, [
    "--output-format=json",
    "--disable=all",
    "--enable=R1702,C0302",
    "--reports=no",
    "--score=no",
    "--persistent=no",
    `--max-nested-blocks=${LIMITS.depth.maximum}`,
    `--max-module-lines=${LIMITS["module-lines"].maximum}`,
    ...group.files,
  ], { cwd: ROOT, encoding: "utf8" });
  if (result.error || !Number.isInteger(result.status) || (result.status & ~(8 | 16)) !== 0) {
    return skippedRun(group.tool, "tool process failed");
  }
  const parsed = parseJsonOutput(group, result.stdout, parsePylint);
  if (result.status !== 0 && parsed.findings.length === 0 && parsed.skipped.length === 0) {
    return skippedRun(group.tool, "analyzer rules unavailable");
  }
  return parsed;
}

function runJscpd(group) {
  const directory = mkdtempSync(join(tmpdir(), "complexity-lint-jscpd-"));
  const outputDirectory = join(directory, "report");
  const config = join(directory, "jscpd.json");
  writeFileSync(config, JSON.stringify({
    threshold: 100,
    minLines: LIMITS["duplicate-lines"].minimum,
    minTokens: 50,
    mode: "mild",
    reporters: ["json"],
    output: outputDirectory,
  }));
  try {
    const result = spawnSync(group.executable, ["--config", config, ...group.files], {
      cwd: ROOT,
      encoding: "utf8",
    });
    if (result.error || result.status !== 0) return skippedRun(group.tool, "tool process failed");
    let report;
    try {
      report = JSON.parse(readFileSync(join(outputDirectory, "jscpd-report.json"), "utf8"));
    } catch {
      return skippedRun(group.tool, "malformed or missing JSON report");
    }
    const findings = parseJscpd(report, new Set(group.files.map((file) => resolve(file))));
    return findings === null
      ? skippedRun(group.tool, "malformed or unselected clone path")
      : { findings, skipped: [] };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function parseJsonRun(group, result, parser) {
  if (result.error || ![0, 1].includes(result.status)) return skippedRun(group.tool, "tool process failed");
  const parsed = parseJsonOutput(group, result.stdout, parser);

  if (result.status !== 0 && parsed.findings.length === 0 && parsed.skipped.length === 0) {
    return skippedRun(group.tool, "analyzer rules unavailable");
  }
  return parsed;
}

function parseJsonOutput(group, stdout, parser) {
  let output;
  try {
    output = JSON.parse(stdout || "[]");
  } catch {
    return skippedRun(group.tool, "malformed JSON output");
  }
  const findings = parser(output, new Set(group.files.map((file) => resolve(file))));
  return findings === null
    ? skippedRun(group.tool, "malformed analyzer output")
    : { findings, skipped: [] };
}

function skippedRun(tool, reason) {
  return { findings: [], skipped: [{ tool, reason }] };
}

function parseOxlint(output, selected) {
  const diagnostics = flattenOxlint(output);
  if (diagnostics === null) return null;
  const findings = [];
  const rules = {
    complexity: ["complexity", "complexity", scoreFromComplexity],
    "max-depth": ["max-depth", "depth", actualFromParentheses],
    "import/no-cycle": ["import/no-cycle", null, null],
    "max-lines": ["max-lines", "module-lines", actualFromParentheses],
    "max-lines-per-function": ["max-lines-per-function", "function-lines", actualFromParentheses],
  };
  for (const diagnostic of diagnostics) {
    const rawRule = diagnostic?.ruleId ?? diagnostic?.rule_id ?? diagnostic?.code;
    const rule = normalizeOxlintRule(rawRule);
    const definition = rules[rule];
    if (!definition) continue;
    const message = diagnostic?.message;
    const line = diagnostic?.line ?? diagnostic?.location?.start?.line ??
      diagnostic?.span?.start?.line ?? diagnostic?.labels?.[0]?.span?.line;
    const file = validatedFile(diagnostic?.file ?? diagnostic?.filename ?? diagnostic?.filePath, selected);
    if (!file || !validLocation(line, message)) continue;
    const [findingRule, metric, valueParser] = definition;
    if (metric === null) {
      findings.push(finding("oxlint", findingRule, file, line, message, "error"));
      continue;
    }
    const value = valueParser(message);
    if (!Number.isInteger(value) || value <= LIMITS[metric].maximum) continue;
    findings.push(metricFinding("oxlint", findingRule, file, line, metric, value, message));
  }
  return findings;
}

function flattenOxlint(output) {
  const diagnostics = [];
  if (Array.isArray(output)) {
    for (const entry of output) {
      if (Array.isArray(entry?.messages)) {
        for (const message of entry.messages) diagnostics.push({ ...message, file: entry.filePath ?? entry.filename });
      } else {
        diagnostics.push(entry);
      }
    }
    return diagnostics;
  }
  if (Array.isArray(output?.diagnostics)) return output.diagnostics;
  return null;
}

function normalizeOxlintRule(rule) {
  if (typeof rule !== "string") return null;
  const match = rule.match(/^(eslint|import)\(([^)]+)\)$/);
  const normalized = match
    ? match[1] === "import" ? `import/${match[2]}` : match[2]
    : rule === "no-cycle" ? "import/no-cycle" : rule;
  return ["complexity", "max-depth", "import/no-cycle", "max-lines", "max-lines-per-function"].includes(normalized)
    ? normalized
    : null;
}

function parseRuff(output, selected) {
  if (!Array.isArray(output)) return null;
  const findings = [];
  for (const diagnostic of output) {
    if (diagnostic?.code !== "C901") continue;
    const message = diagnostic?.message;
    const value = scoreFromComplexity(message);
    const line = diagnostic?.location?.row;
    const file = validatedFile(diagnostic?.filename, selected);
    if (!file || !validLocation(line, message) || !Number.isInteger(value) || value <= LIMITS.complexity.maximum) continue;
    findings.push(metricFinding("ruff", "C901", file, line, "complexity", value, message));
  }
  return findings;
}

function parsePylint(output, selected) {
  if (!Array.isArray(output)) return null;
  const findings = [];
  const rules = {
    R1702: ["too-many-nested-blocks", "depth"],
    C0302: ["too-many-lines", "module-lines"],
  };
  for (const diagnostic of output) {
    const definition = rules[diagnostic?.["message-id"]];
    if (!definition) continue;
    const message = diagnostic?.message;
    const value = actualFromRatio(message);
    const line = diagnostic?.line;
    const file = validatedFile(diagnostic?.path ?? diagnostic?.abspath, selected);
    if (!file || !validLocation(line, message) || !Number.isInteger(value)) continue;
    const [rule, metric] = definition;
    if (value <= LIMITS[metric].maximum) continue;
    findings.push(metricFinding("pylint", rule, file, line, metric, value, message));
  }
  return findings;
}

function parseJscpd(output, selected) {
  if (!Array.isArray(output?.duplicates)) return null;
  const findings = [];
  for (const duplicate of output.duplicates) {
    const first = duplicate?.firstFile;
    const second = duplicate?.secondFile;
    const firstFile = validatedFile(first?.name, selected);
    const secondFile = validatedFile(second?.name, selected);
    const line = first?.start;
    const secondLine = second?.start;
    const value = duplicate?.lines;
    if (!firstFile || !secondFile || !validLocation(line, "duplicate") || !Number.isInteger(secondLine) || secondLine < 1) return null;
    if (!Number.isInteger(value) || value < LIMITS["duplicate-lines"].minimum) return null;
    const secondPath = relative(ROOT, secondFile).replaceAll("\\", "/");
    const message = `Duplicated block with ${secondPath}:${secondLine}`;
    findings.push(metricFinding("jscpd", "duplicate-code", firstFile, line, "duplicate-lines", value, message));
  }
  return findings;
}

function scoreFromComplexity(message) {
  if (typeof message !== "string") return null;
  const match = message.match(/(?:complexity\s+(?:of|is)|too complex\s*\()\s*(\d+)/i);
  return match ? Number(match[1]) : null;
}

function actualFromParentheses(message) {
  if (typeof message !== "string") return null;
  const match = message.match(/\((\d+)(?:\s*>\s*\d+)?\)/);
  return match ? Number(match[1]) : null;
}

function actualFromRatio(message) {
  if (typeof message !== "string") return null;
  const match = message.match(/\((\d+)\s*\/\s*\d+\)/);
  return match ? Number(match[1]) : null;
}

function validatedFile(file, selected) {
  if (typeof file !== "string") return null;
  const absolute = resolve(ROOT, file);
  return selected.has(absolute) ? absolute : null;
}

function validLocation(line, message) {
  return Number.isInteger(line) && line > 0 && typeof message === "string";
}

function finding(tool, rule, file, line, message, severity, metric, value) {
  return {
    tool,
    rule,
    path: relative(ROOT, file).replaceAll("\\", "/"),
    line,
    ...(metric === undefined ? {} : { metric, value }),
    message,
    severity,
  };
}

function metricFinding(tool, rule, file, line, metric, value, message) {
  const severity = value > LIMITS[metric].blockingAbove ? "error" : "advisory";
  return finding(tool, rule, file, line, message, severity, metric, value);
}

function report(findings, skipped) {
  for (const item of findings) {
    const measurement = item.metric === undefined ? "" : ` ${item.metric} ${item.value}`;
    process.stderr.write(`${item.severity}: ${item.tool} ${item.rule} ${item.path}:${item.line}${measurement}: ${item.message}\n`);
  }
  for (const item of skipped) process.stderr.write(`skip: ${item.tool}: ${item.reason}\n`);
}

function runGroups(groups, runner, findings, skipped) {
  for (const group of groups) {
    const result = runner(group);
    findings.push(...result.findings);
    skipped.push(...result.skipped);
  }
}

async function main() {
  try {
    const files = changedPaths(await readStdin());
    const javascript = files.filter((file) => languageOf(file) === "javascript");
    const python = files.filter((file) => languageOf(file) === "python");
    const findings = [];
    const skipped = [];
    const oxlint = groupsForTool(javascript, "oxlint");
    const ruff = groupsForTool(python, "ruff");
    const pylint = groupsForTool(python, "pylint");
    const jscpd = groupsForTool(files, "jscpd");
    skipped.push(...oxlint.skipped, ...ruff.skipped, ...pylint.skipped, ...jscpd.skipped);
    runGroups(oxlint.groups, runOxlint, findings, skipped);
    runGroups(ruff.groups, runRuff, findings, skipped);
    runGroups(pylint.groups, runPylint, findings, skipped);
    runGroups(jscpd.groups, runJscpd, findings, skipped);
    report(findings, skipped);
    if (findings.some((item) => item.severity === "error")) process.exitCode = 1;
  } catch {
    process.stderr.write("skip: complexity-lint: internal failure\n");
    process.exitCode = 0;
  }
}

await main();
