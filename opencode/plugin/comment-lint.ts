import type { Plugin } from "@opencode-ai/plugin"

const BIN = `${process.env.HOME}/.lazar-harness/bin/comment-lint`

type Job = { mode: string; stdin: string }
type ToolArgs = {
  filePath?: unknown
  content?: unknown
  oldString?: unknown
  newString?: unknown
  patchText?: unknown
  patch?: unknown
}
type RunResult = { code: number; stderr: string }

export const CommentLint: Plugin = async () => ({
  "tool.execute.before": async (input, output) => {
    let job: Job | null
    try {
      job = jobFor(input.tool, output.args ?? {})
    } catch {
      return
    }
    if (!job) return

    let result: RunResult
    try {
      result = await runCore(job.mode, job.stdin)
    } catch {
      return
    }
    if (result.code === 0) return
    throw new Error(result.stderr || `comment-lint rejected the ${input.tool}`)
  },
})

function jobFor(tool: string, args: ToolArgs): Job | null {
  if (tool === "write" && typeof args.filePath === "string" && typeof args.content === "string") {
    return {
      mode: "claude-hook",
      stdin: hookPayload(args.filePath, { content: args.content }),
    }
  }
  if (tool === "edit" && typeof args.filePath === "string" && typeof args.newString === "string") {
    return {
      mode: "claude-hook",
      stdin: hookPayload(args.filePath, { old_string: args.oldString, new_string: args.newString }),
    }
  }
  const patchText = args.patchText ?? args.patch
  if (tool === "apply_patch" && typeof patchText === "string") {
    return { mode: "diff", stdin: patchToDiff(patchText) }
  }
  return null
}

function hookPayload(filePath: string, values: Record<string, unknown>): string {
  return JSON.stringify({ tool_input: { file_path: filePath, ...values } })
}

function patchToDiff(patchText: string): string {
  const out: string[] = []
  for (const line of patchText.split("\n")) {
    const header = line.match(/^\*\*\* (?:Add|Update) File: (.+)$/)
    if (header) out.push(`diff --git a/${header[1].trim()} b/${header[1].trim()}`, `+++ b/${header[1].trim()}`)
    else if (line.startsWith("*** Delete File:")) out.push("diff --git a/deleted b/deleted", "+++ /dev/null")
    else if (line.startsWith("***")) continue
    else if (line.startsWith("@@") || line.startsWith("+") || line.startsWith("-") || line.startsWith(" ")) out.push(line)
    else out.push(` ${line}`)
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
