#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

command -v bun >/dev/null 2>&1 || {
  printf 'FAIL Bun is required for the OpenCode comment-lint test\n' >&2
  exit 1
}

mkdir -p -- "$TMP/home/.lazar-harness/bin"
cp -- "$HARNESS_SOURCE/bin/comment-lint" "$TMP/home/.lazar-harness/bin/comment-lint"
cp -- "$HARNESS_SOURCE/bin/comment-lint.mjs" "$TMP/home/.lazar-harness/bin/comment-lint.mjs"
chmod +x "$TMP/home/.lazar-harness/bin/comment-lint"

cat >"$TMP/run.ts" <<'TS'
import { pathToFileURL } from "node:url"

const pluginPath = process.argv[2]
const module = await import(pathToFileURL(pluginPath).href)
const plugin = await module.CommentLint({} as never)
const before = plugin["tool.execute.before"]

if (!before) throw new Error("plugin has no tool.execute.before hook")

async function expectPass(name: string, tool: string, args: Record<string, unknown>) {
  await before({ tool } as never, { args } as never)
  console.log(`ok   ${name}`)
}

async function expectReject(name: string, tool: string, args: Record<string, unknown>) {
  try {
    await before({ tool } as never, { args } as never)
  } catch {
    console.log(`ok   ${name}`)
    return
  }
  throw new Error(`${name} passed unexpectedly`)
}

await expectPass("a clean edit passes", "edit", {
  filePath: "clean.ts",
  oldString: "export const value = 1",
  newString: "export const value = 2",
})

await expectReject("a new comment is rejected", "edit", {
  filePath: "new-comment.ts",
  oldString: "export const value = 1",
  newString: "// Explain the value.\nexport const value = 1",
})

await expectPass("unchanged comment context passes", "edit", {
  filePath: "unchanged.ts",
  oldString: "// Existing explanation.\nexport const value = 1",
  newString: "// Existing explanation.\nexport const value = 2",
})

await expectReject("apply_patch comment additions are rejected", "apply_patch", {
  patchText: `*** Begin Patch
*** Update File: patched.ts
@@
 export const value = 1
+// Explain the value.
*** End Patch`,
})
TS

HOME="$TMP/home" bun "$TMP/run.ts" "$HARNESS_SOURCE/opencode/plugin/comment-lint.ts"
printf '\nall OpenCode comment-lint plugin cases passed\n'
