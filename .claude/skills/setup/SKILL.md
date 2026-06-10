---
name: setup
description: One-shot onboarding for a fresh clone of this repo. Use after `git clone` to install dependencies, bring up the dev stack, verify the build and tests, set the required env vars, and (optionally) wire the recommended MCPs. Idempotent — safe to re-run after pulling new dependency versions.
---

# Setup Skill

Brings a fresh clone of this repo to a working state. Conventions live in `CLAUDE.md`.

> **Template note.** This skill ships as a skeleton — the *shape* is universal (system
> tooling → env vars → deps → bring up the stack → verify → recommended MCPs), but the
> commands and required keys are project-specific. Fill the blocks below with the actual
> commands for *this* project on first setup. Until then, the skill describes the
> *intent* of each step.

## Steps

### 1. System tooling (one-time per machine)

```sh
# Install language runtime + task runner the project uses.
# Examples:
#   brew install node just            # Node + just
#   brew install python uv            # Python + uv
#   rustup install stable             # Rust toolchain
```

Also needs any process supervisors / containers the dev stack relies on (e.g. Docker /
OrbStack for a containerized DB).

Verify:

```sh
# node --version          # match .node-version
# pnpm --version          # match packageManager in package.json
# python --version
# docker info >/dev/null && echo "docker ok"
```

### 2. Environment variables

```sh
cp .env.example .env
```

Fill in the keys this project needs — see `CLAUDE.md` and / or the project's config
loader (e.g. `server/config.ts`) for the authoritative schema. The app should refuse to
start if anything is missing/invalid — that's the point of validated config.

Common categories:

- **Database URL** — usually wired by the docker stack for local dev.
- **External API keys** — third-party services this project consumes. List them
  explicitly in `CLAUDE.md` so onboarding doesn't go fishing.
- **User-Agent / contact strings** — required by some upstreams (OSM, etc.).

Never commit `.env` or `.env.local` — they're git-ignored. Keys are config, never inline.

### 3. Dependencies

```sh
# pnpm install      # or: npm install, yarn install, uv sync, cargo build, etc.
```

If the project enforces supply-chain policies (e.g. `.npmrc` `minimum-release-age`),
note that here so the user expects the refusal on too-new packages.

### 4. Bring up the stack and verify

```sh
# just dev          # or: docker compose up, pnpm dev, cargo run, etc.
```

In another terminal, sanity-check build and tests on the clean clone:

```sh
# just check        # type-check
# just test         # tests
```

Both should be green. Type-checking should catch errors that the dev server alone would
let slide.

### 5. Recommended MCPs (user scope — credentials never enter the repo)

Optional. Skip any you don't need.

**GitHub MCP** — for the `ship` and `capture` skills, issue/PR triage, cross-repo
lookups.

```sh
claude mcp add --scope user --transport http github \
  https://api.githubcopilot.com/mcp/ \
  --header "Authorization: Bearer $(env -u GITHUB_TOKEN gh auth token)"
```

Requires `gh` authenticated with `repo` + `read:org`
(`gh auth refresh -h github.com -s repo,read:org`). The `env -u GITHUB_TOKEN` prefix
bypasses any narrower env-var token (`gh` prefers env over keyring).

### 6. Verify

```sh
claude mcp list                   # expect 'github' as ✓ Connected if installed
jj st                             # expect an empty @ (clean working copy)
```

## Don't

- Don't reach for a global package manager when the project pins one (`corepack` for
  pnpm, `uv` for Python projects). Lockfile drift is silent and painful.
- Don't put MCP credentials or API keys in `.claude/settings.json` or any repo-tracked
  file. User scope / `.env` only.
- Don't commit `node_modules/`, build output, or `.env*`. The `commit` skill commits
  explicit paths (`jj commit <paths>`) for this reason — and jj honours `.gitignore`.
- Don't disable supply-chain policies (`.npmrc` cooldown, package-lock integrity) to
  install a fresh package faster — they're policy, not obstacles.
