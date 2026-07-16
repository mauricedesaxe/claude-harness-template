# AGENTS.md

Guidance for Codex, OpenCode, and any other agent working in **this** repository.

`CLAUDE.md` here is not this repo's rules file. It's the **payload**: the instructions
`install.sh` writes to `~/.claude/CLAUDE.md` and, under OpenCode's name for the same thing,
`~/.config/opencode/AGENTS.md`. Read it as both, because a harness that doesn't hold in its own
repo doesn't hold anywhere.

It points at the philosophy rather than restating it, and the philosophy is installed, not carried
by a repo: `~/.claude/rules/PHILOSOPHY.md` with the packs under `~/.claude/rules/packs/`, or the
same files under `~/.config/opencode/rules/`. This repo also holds their **source**, at
`docs/PHILOSOPHY.md` and `docs/packs/`. Edit the source here; read the installed copy anywhere
else. `§N` numbers are stable IDs, so a citation resolves through the spine's Section index.

What's specific to this repo, and easy to get wrong:

- **`CLAUDE.md` has a line budget**, asserted by `test/install-smoke.sh`: under 200 lines, because
  adherence drops as it grows. Make budget by pointing at the philosophy or at `/matt-ask-matt`,
  not by dropping a rule.
- **Its `surface:local` block is generated per surface.** `install.sh` swaps it for the sandbox
  default. Edit the block, and the sandbox text in `install.sh`, together.
- **Nothing under `skills/matt-*` or `skills/lazar-tldraw` is hand-edited.** Both are vendored and
  regenerated. Edit upstream or `patches/lazar-tldraw.patch`, then re-run `./vendor-skills.sh`.
- **Never run `install.sh` by hand.** It honours `$HOME`, `$CLAUDE_CONFIG_DIR`, and
  `$XDG_CONFIG_HOME`, so it will overwrite a live harness. Run `bash test/install-smoke.sh`, which
  scrubs the environment first.
