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
- **`surface:local` / `surface:sandbox` blocks are per-environment prose**, in `CLAUDE.md` and in
  `skills/lazar-review/SKILL.md`. The installer keeps the pair matching `HARNESS_SURFACE` and drops
  the rest, so both variants live in the markdown and are edited together. A file carrying one
  surface and not the other stops the install.
- **Vendored skill directories are never hand-edited.** This covers `skills/matt-*`,
  `skills/lazar-tldraw`, `skills/use-railway`, `skills/plannotator-*`, and
  `skills/visual-explainer`. Edit upstream or `patches/lazar-tldraw.patch`, then re-run
  `./vendor-skills.sh`.
- **Never pass `--install` to `install.sh` here.** It honours `$HOME`, `$CLAUDE_CONFIG_DIR` and
  `$XDG_CONFIG_HOME`, so with the flag it overwrites whatever live harness the shell you are
  standing in is configured with. Exercise it with `bash test/install-smoke.sh`, which scrubs the
  environment first. Without the flag it only reports, so running it bare is safe.
