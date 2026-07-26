import type { Plugin } from "@opencode-ai/plugin"

/**
 * comment-lint for OpenCode: the write-time half of the §21 guard, the counterpart
 * to Claude Code's PostToolUse hook. tool.execute.before fires before a write lands,
 * so a throw both blocks it and hands the model the §21 reason. Fail-open.
 */

const BIN = `${process.env.HOME}/.lazar-harness/bin/comment-lint`

export const CommentLint: Plugin = async () => ({
  "tool.execute.before": async (input, output) => {
    const job = resolve(input.tool, output.args ?? {})
    if (!job) return

    let result
    try {
      result = await runCore(job.mode, job.stdin)
    } catch {
      return // bin missing or spawn unavailable: fail open, never block a write
    }
    if (result.code === 0) return
    throw new Error(result.stderr || `comment-lint rejected the ${input.tool}`)
  },
})

/** Maps a file-writing tool to a (core mode, stdin) pair, or null when there's nothing to lint. */
function resolve(tool: string, args: any): { mode: string; stdin: string } | null {
  if (tool === "write" && typeof args.filePath === "string" && typeof args.content === "string")
    return { mode: "claude-hook", stdin: hookPayload(args.filePath, args.content) }
  if (tool === "edit" && typeof args.filePath === "string" && typeof args.newString === "string")
    return { mode: "claude-hook", stdin: hookPayload(args.filePath, args.newString) }
  const patchText = args.patchText ?? args.patch
  if (tool === "apply_patch" && typeof patchText === "string")
    return { mode: "diff", stdin: patchToDiff(patchText) }
  return null
}

function hookPayload(filePath: string, content: string): string {
  return JSON.stringify({ tool_input: { file_path: filePath, content } })
}

/**
 * Rewrites an apply_patch body into the unified-diff shape diff mode parses: each
 * `*** Add/Update File:` header becomes `+++ b/<path>`, its `+` lines already match.
 * Context, `@@`, `-` removals, and the Begin/End markers, diff mode ignores.
 */
function patchToDiff(patchText: string): string {
  const out: string[] = []
  for (const line of patchText.split("\n")) {
    const header = line.match(/^\*\*\* (?:Add|Update) File: (.+)$/)
    if (header) out.push(`+++ b/${header[1].trim()}`)
    else if (line.startsWith("*** Delete File:")) out.push("+++ /dev/null")
    else out.push(line)
  }
  return out.join("\n")
}

async function runCore(mode: string, stdin: string): Promise<{ code: number; stderr: string }> {
  const proc = Bun.spawn([BIN, mode], { stdin: "pipe", stdout: "pipe", stderr: "pipe" })
  proc.stdin?.write(stdin)
  proc.stdin?.end()
  const code = await proc.exited
  const stderr = code === 0 ? "" : (await new Response(proc.stderr).text()).trim()
  return { code, stderr }
}
