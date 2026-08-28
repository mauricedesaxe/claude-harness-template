#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

command -v bun >/dev/null 2>&1 || {
  printf 'SKIP Bun is unavailable; OpenCode comment-lint plugin cases were not run\n'
  exit 0
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

await expectPass("whole-file writes let the core read existing content", "write", {
  filePath: process.env.TEST_FILE,
  content: "// Existing explanation.\nexport const value = 2;\n",
})

await expectPass("native docs pass", "write", {
  filePath: "native-doc.ts",
  content: "/** Public docs. */\nexport const value = 1;\n",
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
*** Update File: ${process.env.LOOSE_FILE}
@@
 export const value = 1
+// Explain the value.
*** End Patch`,
})

await expectReject("apply_patch comments in new files are rejected", "apply_patch", {
  patchText: `*** Begin Patch
*** Add File: new-comment.ts
+// Explain the value.
+export const value = 1
*** End Patch`,
})

await expectPass("apply_patch URL edits inside multiline templates pass", "apply_patch", {
  patchText: `*** Begin Patch
*** Update File: ${process.env.URL_FILE}
@@
 export const endpoint = \`
-https://old.example/path
+https://new.example/path
 \`;
*** End Patch`,
})
TS

printf '// Existing explanation.\nexport const value = 1;\n' >"$TMP/existing.ts"
printf 'export const value = 1\n' >"$TMP/loose.ts"
printf 'export const endpoint = `\nhttps://old.example/path\n`;\n' >"$TMP/url.ts"
HOME="$TMP/home" TEST_FILE="$TMP/existing.ts" LOOSE_FILE="$TMP/loose.ts" URL_FILE="$TMP/url.ts" \
  bun "$TMP/run.ts" "$HARNESS_SOURCE/opencode/plugin/comment-lint.ts"
printf '\nall OpenCode comment-lint plugin cases passed\n'
