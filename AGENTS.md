# AGENTS.md

Guidance for Codex, OpenCode, and any other agent working in **this** repository.

`CLAUDE.md` here is not this repo's rules file. It's the **payload**: the instructions
`install.sh` writes to `~/.claude/CLAUDE.md` and, under OpenCode's name for the same thing,
`~/.config/opencode/AGENTS.md`. Read it as both, because a harness that doesn't hold in its own
repo doesn't hold anywhere.

It points at the philosophy rather than restating it. The philosophy is installed, never carried
by a repo: `~/.claude/rules/PHILOSOPHY.md` with the packs under `~/.claude/rules/packs/`, or the
same files under `~/.config/opencode/rules/`. This repo also holds their **source**, at
`docs/PHILOSOPHY.md` and `docs/packs/`. Edit the source here; read the installed copy anywhere
else. `§N` numbers are stable IDs, so a citation resolves through the spine's Section index.

What's specific to this repo, and easy to get wrong:

- **`CLAUDE.md` has a line budget**: keep it lean, because adherence drops as it grows. Make budget
  by pointing at the philosophy or at `pstack-poteto-mode`, not by dropping a rule.
- **`surface:local` / `surface:sandbox` blocks are per-environment prose**, in `CLAUDE.md` and in
  `skills/lazar-review/SKILL.md`. The installer keeps the pair matching `HARNESS_SURFACE` and drops
  the rest, so both variants live in the markdown and are edited together. A file carrying one
  surface and not the other stops the install.
- **Most vendored skill directories are never hand-edited.** This covers `skills/matt-*`,
  `skills/lazar-tldraw`, `skills/use-railway`, `skills/plannotator-*`, and
  `skills/visual-explainer`. Edit upstream or `patches/lazar-tldraw.patch`, then re-run
  `./vendor-skills.sh`.
- **`skills/pstack-*` is the exception: a hand-maintained fork.** Its Cursor coupling is translated
  for the harness by hand, so you edit these files in place. `skills-lock.json` pins each one's
  pristine-upstream hash, and `./vendor-skills.sh --check-pstack-drift` reports when upstream has
  moved and the fork needs a manual reconcile. A re-vendor never overwrites them.
- **Never pass `--install` to `install.sh` here.** It honours `$HOME`, `$CLAUDE_CONFIG_DIR` and
  `$XDG_CONFIG_HOME`. With the flag it overwrites the live harness your current shell points at. Exercise it with `bash test/install-smoke.sh`, which scrubs the
  environment first. Without the flag it only reports, so running it bare is safe.
