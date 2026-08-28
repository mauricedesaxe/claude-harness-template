#!/usr/bin/env bash
set -euo pipefail

HARNESS_SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Which environment the installed instructions are for, not which runtime reads them: Claude Code
# and OpenCode both run on a laptop and both run inside a sandbox, and it is the environment that
# decides whether the working copy is shared. A sandbox image build passes `sandbox` when it
# invokes this script; everything else gets the laptop default.
HARNESS_SURFACE="${HARNESS_SURFACE:-local}"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CLAUDE_RULES="$CLAUDE_HOME/rules"
OPENCODE_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_RULES="$OPENCODE_HOME/rules"

# The two roots OpenCode reads that the harness installs nothing into, and empties instead.
#
# OpenCode resolves skills from four global roots, in this order, highest first (probed by planting
# colliding canaries and reading `opencode debug skill` back, not inferred):
#
#   $OPENCODE_HOME/skills  >  $OPENCODE_HOME/skill  >  ~/.agents/skills  >  ~/.claude/skills
#
# Claude Code reads only the last of those. So a skill in either root below loads in OpenCode and
# not in Claude Code, which is the divergence this harness exists to prevent — and because both
# outrank ~/.claude/skills, a name the harness *does* ship can be shadowed there by a different
# copy, which diverges the two runtimes while every file the installer wrote is still on disk.
#
# Neither is installed into. OpenCode auto-loads ~/.claude/skills directly and unconditionally, so
# the harness's skills already reach it without a second copy; adding one would be double state
# that drifts (`§26`), which is the same reason bootstrap-harness tells Codex to read
# .claude/skills through the bridge rather than mirror into .agents/skills.
#
# The two resolve differently on purpose. The singular is OpenCode's own, so it follows OpenCode's
# home and honours XDG_CONFIG_HOME like everything else under it. ~/.agents answers to no config
# home at all — OpenCode reads it straight off HOME, with nothing to redirect it — so it is the one
# skills root that is shared across all three Claude Code profiles on this laptop rather than being
# one profile's. That gives it the shape CLAUDE_HOOKS has and the same cost, stated where that one
# states it: every profile's install purges this one directory, and none of them knows the others
# exist. Unlike the hooks case there is nothing left dangling by that — an emptied root is emptied
# for everyone, which is what all three profiles wanted anyway.
AGENTS_SKILLS="$HOME/.agents/skills"
OPENCODE_SKILL_SINGULAR="$OPENCODE_HOME/skill"
OPENCODE_COMMANDS="$OPENCODE_HOME/commands"

# The linter cores live here, not under CLAUDE_HOOKS, on purpose. The Claude Code hook is only
# one comment-lint caller: the lazar-commit gate calls both linters from whatever runtime commits,
# and OpenCode has no CLAUDE_HOOKS installed while a sandbox's CLAUDE_HOME is not a path OpenCode
# knows. $HOME is the one root Claude Code, OpenCode and a sandbox all agree on (same reason the
# machine-local notes sit under it), so a $HOME-anchored bin is the single copy every caller can
# name. It sits beside those notes under ~/.lazar-harness but in its own subdir: bin is the
# installer's, repos/ is hand-edited, and replace_dir on bin leaves repos/ untouched.
LAZAR_BIN="$HOME/.lazar-harness/bin"

# The harness manages only the skills it installs, never the whole skills tree. A skills root can
# hold skills another tool owns (Newsjack drops ~30 under ~/.claude/skills and marks each
# `.newsjack-installed`, the way Railway drops use-railway), and purging by omission would take
# them with it. So the harness records the exact set it installs and, on the next run, removes only
# the recorded skills it no longer ships. Everything it never installed is left untouched.
#
# `skills-manifest.txt` is the committed declaration of that set. `test/skills-manifest.sh` fails if
# it drifts from the `skills/` directories, so adding or renaming a skill is a change nobody makes
# by accident. Each skills destination carries its own hidden footprint, so one profile cannot
# forget a retired skill before another profile upgrades. The old shared footprint remains a
# migration input for destinations that do not have their own record yet.
SKILLS_MANIFEST="$HARNESS_SOURCE/skills-manifest.txt"
LEGACY_SKILLS_FOOTPRINT="$HOME/.lazar-harness/installed-skills"
SKILLS_FOOTPRINT_NAME=".lazar-harness-installed-skills"

# The per-machine model config the pstack fan-out skills resolve first. It is seeded from the shipped
# docs/models.md once and never overwritten, so the OpenAI-vs-GLM swap and any per-machine slug edit
# survive every reinstall. It sits under ~/.lazar-harness beside the tracker notes, owned by no
# runtime, for the same reason the footprint and the notes do.
MODELS_LOCAL="$HOME/.lazar-harness/models.md"

# The prefixes and bare names the harness owns, used once to seed the footprint on the first run
# after this landed, when no footprint exists yet but a prior wholesale install left the harness's
# skills on disk unrecorded. After that first run the footprint is authoritative and names stop
# mattering, which is the whole point of recording rather than inferring.
harness_owned_skill() {
  case "$1" in
  lazar-* | matt-* | pstack-* | plannotator-* | visual-explainer | bro | use-railway) return 0 ;;
  *) return 1 ;;
  esac
}

# The instructions merge drops its own previous entries by matching this prefix, so changing the
# spelling orphans an existing install's rather than replacing them. `~` is what OpenCode expands
# and what is already on disk; only rules landing outside $HOME need the absolute form.
case "$OPENCODE_RULES" in
"$HOME"/*) OPENCODE_RULES_REF="~/${OPENCODE_RULES#"$HOME"/}" ;;
*) OPENCODE_RULES_REF="$OPENCODE_RULES" ;;
esac

die() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

APPLY=false

# `rm -rf` unlinks a symlink rather than following it, so a destination that is one has to be
# resolved before it is replaced, and named as what it resolves to before it is reported: on this
# machine ~/.claude-personal/skills is a link to ~/.claude/skills, and both the deletion and the
# report are only true of the target. CDPATH would print the directory it matched on a relative
# path, and this is a command substitution, so it would land in the caller's variable.
resolve_dir() {
  CDPATH='' cd -- "$1" && pwd -P
}

# A destination is replaced wholesale, so whatever is in it that the source has no name for is
# what an install costs, and it is the same list either way: the run that applies it prints it too.
# Recursive, because the replace reaches all the way down and a report that stopped at the top
# would keep quiet about a file hand-edited inside a directory the harness does still ship. It
# prunes at the shallowest name that goes, so an orphan skill is one line rather than its whole
# tree, and it never reads the report out of a directory it could not read.
report_replace() {
  local dest=$1 source=$2 entries entry name
  [ -d "$dest" ] || return 0
  dest=$(resolve_dir "$dest")
  entries=$(find "$dest" -mindepth 1 -maxdepth 1 2>/dev/null | sort || true)
  [ -n "$entries" ] || return 0
  while IFS= read -r entry; do
    name=${entry##*/}
    if [ ! -e "$source/$name" ]; then
      printf '  %-7s %s\n' delete "$entry"
    elif [ -d "$entry" ] && [ -d "$source/$name" ]; then
      report_replace "$entry" "$source/$name"
    fi
  done <<<"$entries"
}

# A root that is emptied rather than replaced: everything in it goes, so the report never recurses.
# It stops at the shallowest name, which is the whole name — an orphan skill is one line, not its
# tree, and there is no surviving sibling underneath to keep quiet about.
report_purge() {
  local dest=$1 entries entry
  [ -d "$dest" ] || return 0
  dest=$(resolve_dir "$dest")
  entries=$(find "$dest" -mindepth 1 -maxdepth 1 2>/dev/null | sort || true)
  [ -n "$entries" ] || return 0
  while IFS= read -r entry; do
    printf '  %-7s %s\n' delete "$entry"
  done <<<"$entries"
}

# Resolved through its parent for the same reason report_replace resolves: one report naming the
# same directory two ways is a report the reader has to check rather than read.
report_write() {
  local dest=$1 verb=${2:-replace}
  if [ -e "$dest" ]; then
    printf '  %-7s %s/%s\n' "$verb" "$(resolve_dir "$(dirname -- "$dest")")" "${dest##*/}"
  fi
}

report_plan() {
  printf 'install.sh: %s\n' "$1"
  printf '  claude    %s\n' "$CLAUDE_HOME"
  printf '  opencode  %s\n' "$OPENCODE_HOME"
  # Named on its own line because it is the one target that is not under either home above, and a
  # purge list is only knowable in advance if the reader knows which directory it is about to read.
  printf '  hooks     %s\n' "$CLAUDE_HOOKS"
  # Same footing as hooks: a shared $HOME-anchored path outside either config home, named here for
  # the same reason, so the replace line below has a directory the reader already knows.
  printf '  bin       %s\n' "$LAZAR_BIN"
  # Same reason, and one more: this directory is the Railway CLI's, not the harness's. It is emptied
  # and never written to, and `railway skills install` puts its skill straight back, so a reader who
  # only saw the delete line below would not know who to expect it back from.
  printf '  agents    %s (harness skills removed; the rest is another tool'"'"'s)\n' "$AGENTS_SKILLS"
  # Named even though it sits under the opencode home above, because what that header implies is a
  # directory that gets replaced, and this one gets emptied. An empty one prints no delete lines at
  # all, so without this the only root the reader would never learn about is the invisible one.
  printf '  skill     %s (emptied; OpenCode reads it, the harness ships nothing to it)\n' \
    "$OPENCODE_SKILL_SINGULAR"
  printf '  surface   %s\n' "$HARNESS_SURFACE"
  report_write "$CLAUDE_HOME/CLAUDE.md"
  report_write "$OPENCODE_HOME/AGENTS.md"
  report_write "$CLAUDE_RULES/PHILOSOPHY.md"
  report_write "$OPENCODE_RULES/PHILOSOPHY.md"
  report_write "$CLAUDE_RULES/models.md"
  report_write "$OPENCODE_RULES/models.md"
  report_models_local
  report_write "$OPENCODE_HOME/opencode.json" merge
  report_write "$CLAUDE_HOME/settings.json" merge
  report_replace "$CLAUDE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  report_replace "$OPENCODE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  report_skills_tracked "$CLAUDE_HOME/skills" "$HARNESS_SOURCE/skills"
  report_skills_tracked "$OPENCODE_HOME/skills" "$HARNESS_SOURCE/skills"
  report_write "$OPENCODE_COMMANDS/bro.md"
  report_purge_harness "$AGENTS_SKILLS"
  report_purge "$OPENCODE_SKILL_SINGULAR"
  report_replace "$CLAUDE_HOME/agents" "$HARNESS_SOURCE/agents"
  report_replace "$OPENCODE_HOME/agents" "$HARNESS_SOURCE/agents"
  report_replace "$OPENCODE_HOME/plugin" "$HARNESS_SOURCE/opencode/plugin"
  report_replace "$CLAUDE_HOOKS" "$HARNESS_SOURCE/hooks"
  report_replace "$LAZAR_BIN" "$HARNESS_SOURCE/bin"
}

# Stage the copy before deleting anything: a destination that resolves back into the source
# (a symlinked ~/.claude/skills, say) would otherwise have the payload deleted out from under it.
# Dropping a real directory over a link would leave the tree it pointed at untouched, and a tree
# replaced wholesale that way purges nothing a runtime reading the other path still loads.
replace_dir() {
  local dest=$1 source=$2 staged
  [ -d "$dest" ] && dest=$(resolve_dir "$dest")
  mkdir -p -- "$(dirname -- "$dest")"
  staged=$(mktemp -d -- "$(dirname -- "$dest")/.install-XXXXXX")
  cp -R -- "$source" "$staged/payload"
  rm -rf -- "$dest"
  mv -- "$staged/payload" "$dest"
  rmdir -- "$staged"
}

# Read this destination's footprint first. An older shared footprint migrates profiles that have not
# installed since per-destination records landed. With neither record, infer the harness-owned names
# once from the destination itself.
prior_skills_footprint() {
  local dest=$1 footprint entry base
  footprint="$dest/$SKILLS_FOOTPRINT_NAME"
  if [ -f "$footprint" ]; then
    cat -- "$footprint"
    return 0
  fi
  if [ -f "$LEGACY_SKILLS_FOOTPRINT" ]; then
    cat -- "$LEGACY_SKILLS_FOOTPRINT"
    return 0
  fi
  [ -d "$dest" ] || return 0
  for entry in "$dest"/*/; do
    [ -d "$entry" ] || continue
    base=${entry%/}
    base=${base##*/}
    if harness_owned_skill "$base"; then printf '%s\n' "$base"; fi
  done
  return 0
}

# The recorded harness skills a dest still holds that the harness no longer ships. A foreign skill is
# absent from the footprint, so it never appears here; a shipped skill is in the manifest, so it does
# not either. What is left is exactly the orphans a wholesale replace used to purge, minus every
# skill the harness never installed.
stale_harness_skills() {
  local dest=$1 name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ -e "$dest/$name" ] || continue
    grep -qxF -- "$name" "$SKILLS_MANIFEST" || printf '%s\n' "$name"
  done < <(prior_skills_footprint "$dest" | LC_ALL=C sort -u)
  return 0
}

# Replaces the wholesale replace for a skills tree. Remove the stale harness skills, drop the freshly
# built set over the top, and leave every other directory (another tool's skills) alone. Resolved
# for the same reason replace_dir resolves: on this machine the dest can be a symlink, and the
# delete and the copy are only right against the target.
install_skills_tracked() {
  local dest=$1 source=$2 resolved name base
  mkdir -p -- "$dest"
  resolved=$(resolve_dir "$dest")
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    rm -rf -- "${resolved:?}/$name"
  done < <(stale_harness_skills "$resolved")
  for name in "$source"/*/; do
    [ -d "$name" ] || continue
    base=${name%/}
    base=${base##*/}
    rm -rf -- "$resolved/$base"
    cp -R -- "$name" "$resolved/$base"
  done
  return 0
}

# The dry-run counterpart. A stale harness skill is one delete line; a shipped skill the dest still
# holds is replaced, so report_replace names its hand-edited files the way it does for any replaced
# tree. A foreign skill is named nowhere, because the install leaves it alone.
report_skills_tracked() {
  local dest=$1 source=$2 resolved name
  [ -d "$dest" ] || return 0
  resolved=$(resolve_dir "$dest")
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    printf '  %-7s %s\n' delete "$resolved/$name"
  done < <(stale_harness_skills "$resolved")
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -d "$resolved/$name" ] && [ -d "$source/$name" ]; then
      report_replace "$resolved/$name" "$source/$name"
    fi
  done < "$SKILLS_MANIFEST"
  return 0
}

# Written after its tree is installed, so a failed copy leaves the prior footprint in place.
write_skills_footprint() {
  local dest=$1
  LC_ALL=C sort -u -- "$SKILLS_MANIFEST" >"$dest/$SKILLS_FOOTPRINT_NAME"
}

# Seed the per-machine model config once. Create-only: an existing file is the user's, edited for
# their machine's providers and credits, and a reinstall must never clobber it.
seed_models_local() {
  [ -e "$MODELS_LOCAL" ] && return 0
  mkdir -p -- "$(dirname -- "$MODELS_LOCAL")"
  cp -- "$HARNESS_SOURCE/docs/models.md" "$MODELS_LOCAL"
}

# The dry-run counterpart: names it a seed when absent, and says it is left alone when present, so the
# plan never implies it would overwrite an edited file.
report_models_local() {
  if [ -e "$MODELS_LOCAL" ]; then
    printf '  %-7s %s (yours; left as-is)\n' keep "$MODELS_LOCAL"
  else
    printf '  %-7s %s (seeded from docs/models.md)\n' seed "$MODELS_LOCAL"
  fi
}

# The one arrangement in which emptying a root would empty the harness itself.
#
# The purged roots are named as paths and reached through whatever they turn out to be, so a link
# from one onto a directory the installer fills is not a strange thing to imagine — it is the
# obvious way to read "one source of truth", it is how ~/.claude-personal and ~/.claude-iconic
# already reach ~/.claude/skills on this machine, and Railway installing to both ~/.agents/skills
# and ~/.claude/skills is a standing invitation to tie them together. Left alone it is silent and
# total: install_skills fills the skills tree, purge_dir resolves the link onto that same tree and
# empties it, and the run prints its success line and exits 0 with every skill gone.
#
# The report does not save anyone either. report_purge would list all of them under `delete`,
# which reads exactly like the orphan lines beside it.
#
# So it stops, before the plan rather than during the install: it is a machine that is wired wrong
# rather than a state to reconcile, and there is no answer here that is not a guess at which of the
# two directories was meant. Skipping the purge instead would leave OpenCode reading the root this
# ticket exists to close.
assert_purge_root_distinct() {
  local root=$1 resolved target
  [ -d "$root" ] || return 0
  resolved=$(resolve_dir "$root")
  for target in "$CLAUDE_HOME/skills" "$OPENCODE_HOME/skills"; do
    [ -d "$target" ] || continue
    [ "$resolved" = "$(resolve_dir "$target")" ] || continue
    die "$root resolves to $resolved, which is where this installer puts the skills it ships, so
emptying it would take every one of them with it. Point it somewhere of its own or remove it:
OpenCode reads $CLAUDE_HOME/skills directly, so a link from here to there buys nothing it does
not already have."
  done
}

# Emptied, not removed. The directory itself is left standing for the same reason its contents are
# not: ~/.agents is the Railway CLI's — it created it, and `railway skills` documents that it
# "always installs to ~/.agents/skills" — so taking the directory away is a decision about another
# tool's layout that the harness has no standing to make, and no purpose either, since Railway
# recreates it on the next run. What the harness has standing to say is which skills load in the
# runtimes it configures, and that is what emptying it says.
#
# Resolved first for the same reason replace_dir resolves: on this machine a skills dir can be a
# symlink, and `rm -rf` unlinks a link rather than following it, so an unresolved purge would take
# the link and leave every skill it pointed at loading.
purge_dir() {
  local dest=$1
  [ -d "$dest" ] || return 0
  dest=$(resolve_dir "$dest")
  find "$dest" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

# ~/.agents is another tool's root: Railway's, and now Newsjack's too, which drops ~30 skills there
# alongside the ones it puts in ~/.claude/skills. The harness never installs there, so it keeps no
# footprint of it. What it has standing to do is stop a copy of its *own* skill in that
# higher-precedence root from shadowing the one it ships, so it removes only the skills it owns by
# name, current or retired, and leaves every foreign skill and marker file where the tool that put
# them there expects them. This is the one place a name check still decides ownership, because a
# root the harness does not install into records no footprint to consult instead.
purge_harness_skills() {
  local dest=$1 entry base
  [ -d "$dest" ] || return 0
  dest=$(resolve_dir "$dest")
  for entry in "$dest"/*/; do
    [ -d "$entry" ] || continue
    base=${entry%/}
    base=${base##*/}
    if harness_owned_skill "$base"; then rm -rf -- "${dest:?}/$base"; fi
  done
  return 0
}

# The dry-run counterpart to purge_harness_skills: one delete line per owned skill in the root, and
# nothing for a foreign one, so the plan names exactly what the install would take.
report_purge_harness() {
  local dest=$1 entry base
  [ -d "$dest" ] || return 0
  dest=$(resolve_dir "$dest")
  for entry in "$dest"/*/; do
    [ -d "$entry" ] || continue
    base=${entry%/}
    base=${base##*/}
    if harness_owned_skill "$base"; then printf '  %-7s %s\n' delete "$dest/$base"; fi
  done
  return 0
}

# OpenCode rejects an agent without `mode`. Every agent this harness ships is a reviewer,
# so it gets the reviewer's permissions: no edit tool, and the bash it needs to read a diff.
write_opencode_agent() {
  local source=$1 dest=$2

  [ "$(head -n 1 -- "$source")" = "---" ] || die "$source has no frontmatter"

  awk '
    NR == 1 { print; next }
    !past_frontmatter && /^---$/ {
      print "mode: subagent"
      print "permission:"
      print "  edit: deny"
      print "  bash: allow"
      print "  webfetch: allow"
      print
      past_frontmatter = 1
      next
    }
    !past_frontmatter && /^name:/ { next }
    { print }
  ' "$source" >"$dest"

  grep -q '^mode: subagent$' "$dest" ||
    die "$source: frontmatter never closes, so no OpenCode mode was generated"
}

# The surfaces the block convention below knows. A markdown file naming anything else has a typo in
# it, and the cost of rendering that as prose is a marker line shipped to a reader as instruction.
HARNESS_SURFACES='local sandbox'

# Prose that differs by environment is authored in the markdown it belongs to, between a
# `<!-- surface:NAME -->` and a `<!-- /surface:NAME -->`, and this keeps the blocks whose name is
# the surface being installed while dropping the rest. Both variants therefore sit next to each
# other in the file someone edits and reviews, rather than one of them living as a heredoc in this
# script, and a second file needing the treatment costs no change here at all.
#
# What differs is only ever the default action. `§28` states the isolation principle for every
# surface. A block that contradicted the other variant rather than adapting it would be two
# harnesses, not one.
#
# `sandbox` says the working copy is not shared, there is no GUI, and the run is ephemeral. It does
# not say nobody is watching: an Open Inspect session someone is driving and an unattended
# automation run are both this surface. So a block that turns on whether a human can answer settles
# that from what the skill is for, never from the flag. `lazar-pr-status` is always Alex driving, so
# it asks first and treats no answer as a no. A second flag for attendedness would be a knob no caller
# can set correctly.
#
# Staged like every other write here, so a file that fails to render leaves the previous install in
# place rather than a half-written one. Every failure below is a mis-authored source: an unclosed
# block silently truncates at the marker, and a missing block silently ships one surface the other
# one's instructions, so both stop the run rather than being reconciled.
render_surface() {
  local source=$1 dest=$2 staged

  staged=$(mktemp -- "$dest.XXXXXX")
  awk -v want="$HARNESS_SURFACE" -v surfaces="$HARNESS_SURFACES" '
    function bail(message) {
      printf "%s\n", message > "/dev/stderr"
      aborted = 1
      exit 1
    }
    function surface_of(line, name) {
      name = line
      sub(/^<!-- \/?surface:/, "", name)
      sub(/ -->$/, "", name)
      return name
    }
    BEGIN { split(surfaces, list, " "); for (i in list) known[list[i]] = 1 }
    /^<!-- surface:[a-z]+ -->$/ {
      name = surface_of($0)
      if (!(name in known)) bail("surface:" name " is not a surface this installer knows")
      if (open != "") bail("surface:" name " opens inside surface:" open)
      open = name
      seen[name] = 1
      keep = (name == want)
      next
    }
    /^<!-- \/surface:[a-z]+ -->$/ {
      name = surface_of($0)
      if (open != name) bail("surface:" name " closes with " (open == "" ? "nothing" : "surface:" open) " open")
      open = ""
      next
    }
    open == "" || keep
    END {
      if (aborted) exit 1
      if (open != "") bail("surface:" open " never closes")
      if (!(want in seen)) bail("there is no surface:" want " block to install")
    }
  ' "$source" >"$staged" || {
    rm -f -- "$staged"
    die "$source did not render for the $HARNESS_SURFACE surface, so $dest was left alone"
  }

  mv -- "$staged" "$dest"
}

# Which files carry surface blocks is read off the files rather than listed here, so a skill that
# grows one is rendered without this script learning its name (`§26`). A file with no marker is
# never passed to render_surface, whose "no block for this surface" assertion would reject it.
render_surface_tree() {
  local root=$1 file
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    render_surface "$file" "$file"
  done <<<"$(grep -rlE '^<!-- surface:[a-z]+ -->$' "$root" 2>/dev/null || true)"
}

install_instructions() {
  mkdir -p -- "$CLAUDE_HOME" "$OPENCODE_HOME"
  render_surface "$HARNESS_SOURCE/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
  render_surface "$HARNESS_SOURCE/CLAUDE.md" "$OPENCODE_HOME/AGENTS.md"
}

# A config the harness merges into rather than owns has to survive being absent and being empty. jq
# reads empty stdin as no input at all: it prints nothing and exits 0, so a merge of an empty file
# would stage an empty file, report success, and replace a config that carries someone's model
# choice with nothing. Whitespace-only reads the same way.
read_json_object() {
  local existing=''
  [ -f "$1" ] && existing=$(<"$1")
  [ -n "${existing//[[:space:]]/}" ] || existing='{}'
  printf '%s' "$existing"
}

# Belt to read_json_object's braces: jq can also stop after writing nothing for a reason neither of
# them saw coming, and every one of those ends the same way — an empty file moved over a real one.
commit_merge() {
  local staged=$1 config=$2
  [ -s "$staged" ] || {
    rm -f -- "$staged"
    die "merging $config produced an empty file, so $config was left alone"
  }
  mv -- "$staged" "$config"
}

# OpenCode has no equivalent of `paths:`, so every instructions entry loads in every session and
# the packs cannot scope themselves there.
write_opencode_instructions() {
  local config="$OPENCODE_HOME/opencode.json" existing staged

  existing=$(read_json_object "$config")

  staged=$(mktemp -- "$config.XXXXXX")
  printf '%s' "$existing" | jq \
    --arg schema https://opencode.ai/config.json \
    --arg prefix "$OPENCODE_RULES_REF/" \
    --arg spine "$OPENCODE_RULES_REF/PHILOSOPHY.md" \
    --arg packs "$OPENCODE_RULES_REF/packs/*.md" '
      ."$schema" //= $schema
      | .instructions = (
          [(.instructions // [])[] | select(startswith($prefix) | not)] + [$spine, $packs]
        )
      | .permission = (
          if (.permission | type) == "string" then { "*": .permission }
          else (.permission // {})
          end
        )
      | .permission.skill = (
          if (.permission.skill | type) == "string" then
            { "*": .permission.skill, "bro": "deny" }
          else
            ((.permission.skill // {}) | del(.bro) | . + { "bro": "deny" })
          end
        )
    ' >"$staged" || {
    rm -f -- "$staged"
    die "could not merge $config"
  }
  commit_merge "$staged" "$config"
}

# Claude Code reads every .md under its rules dir. A rule with no `paths:` frontmatter loads in
# every session; one with `paths:` loads only when the agent touches a file that matches. That is
# what carries the spine into every repo with no per-repo setup while each pack applies itself by
# paradigm. Spine and packs keep their source layout so the relative links between them resolve.
install_philosophy() {
  mkdir -p -- "$CLAUDE_RULES" "$OPENCODE_RULES"
  cp -- "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$CLAUDE_RULES/PHILOSOPHY.md"
  cp -- "$HARNESS_SOURCE/docs/PHILOSOPHY.md" "$OPENCODE_RULES/PHILOSOPHY.md"
  # models.md is the per-role model config the pstack fan-out skills resolve against. It installs
  # beside the spine so a skill finds it at a stable path in whichever runtime it runs.
  cp -- "$HARNESS_SOURCE/docs/models.md" "$CLAUDE_RULES/models.md"
  cp -- "$HARNESS_SOURCE/docs/models.md" "$OPENCODE_RULES/models.md"
  seed_models_local
  replace_dir "$CLAUDE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  replace_dir "$OPENCODE_RULES/packs" "$HARNESS_SOURCE/docs/packs"
  write_opencode_instructions
}

# A skill the harness stops shipping has to stop loading, so the whole tree is replaced rather
# than each shipped name in turn, which never touches a destination the source has no name for.
#
# Replacing those two is only half of it: OpenCode reads two further roots that Claude Code does
# not, and both outrank ~/.claude/skills. A skill left in either goes on loading in one runtime and
# not the other, which the file-level assertions above this cannot see — every file the installer
# wrote is exactly where it put it, and the runtimes still disagree. So the roots the harness does
# not ship into are emptied, and what proves it is `opencode debug skill` resolving the same set of
# names Claude Code has, not a directory listing.
#
# Rendered into a build directory before either replace, the way an agent's OpenCode dialect is, so
# a skill that fails to render stops the run with both trees still on their previous install rather
# than with one of them already replaced by the copy that failed.
install_skills() {
  local built
  built=$(mktemp -d)
  cp -R -- "$HARNESS_SOURCE/skills" "$built/skills"
  render_surface_tree "$built/skills"

  install_skills_tracked "$CLAUDE_HOME/skills" "$built/skills"
  write_skills_footprint "$(resolve_dir "$CLAUDE_HOME/skills")"
  install_skills_tracked "$OPENCODE_HOME/skills" "$built/skills"
  write_skills_footprint "$(resolve_dir "$OPENCODE_HOME/skills")"
  rm -rf -- "$built"
  purge_harness_skills "$AGENTS_SKILLS"
  purge_dir "$OPENCODE_SKILL_SINGULAR"
}

# Claude Code's invocation lock has no OpenCode equivalent: OpenCode advertises every discovered
# skill to the model. Its user-invoked surface is a command, so /bro gets an adapter there while
# the skill permission above hides the model-facing route. This owns one file, not the commands
# directory, because other tools install commands alongside it.
install_opencode_commands() {
  mkdir -p -- "$OPENCODE_COMMANDS"
  cp -- "$HARNESS_SOURCE/opencode/commands/bro.md" "$OPENCODE_COMMANDS/bro.md"
}

# The tools enforce-jj.sh decides on. Claude Code only hands a hook the calls its matcher names, so
# a tool missing here is a tool the hook never sees: `Agent` is on the list because `isolation:
# "worktree"` cuts a git worktree through neither `Bash` nor `EnterWorktree`, which is how it walked
# past the hand-wired matcher this replaces for as long as that matcher was hand-wired.
JJ_HOOK_MATCHER='Bash|EnterWorktree|Agent'

# A hook is the only rule the harness enforces rather than asks for: CLAUDE.md and the rules dir
# are not inherited by subagents, so a rule written there reaches a main loop and dies at the first
# delegation boundary, while a PreToolUse hook fires for every agent at every depth. That is not
# theoretical — an agent told not to run this file complied, and the subagent it spawned ran it.
#
# This is Claude Code's alone. OpenCode does have a write-time enforcement surface —
# tool.execute.before, which install_opencode_plugin wires for comment-lint — but the jj guard is
# not ported to it: this hook denies a git *mutation*, which OpenCode's own tool loop does not run
# in the shape enforce-jj matches on, and the harness gates jj there through guidance instead.
# Enforcement where it earns its keep beats enforcement everywhere, and that asymmetry is chosen.
#
# A hook the harness stops shipping has to stop firing, so the tree is replaced whole the way
# skills and agents are. Taking the script off the disk is only half of it: write_claude_settings
# takes the wiring with it, or every prompt would fire a file that is no longer there.
install_hooks() {
  replace_dir "$CLAUDE_HOOKS" "$HARNESS_SOURCE/hooks"
}

# The linter cores and launchers. replace_dir touches only the bin subdir, so a hand-edited
# ~/.lazar-harness/repos/ note next to it survives. cp -R carries the executable bits the repo set.
install_linters() {
  replace_dir "$LAZAR_BIN" "$HARNESS_SOURCE/bin"
}

# The OpenCode write-time guard: a tool.execute.before plugin that shells out to the same
# comment-lint core the Claude Code hook and the lazar-commit gate call, so §21 is enforced before a
# write lands in OpenCode too, not only at commit. It reshapes OpenCode's tool args into the
# claude-hook payload the core already reads, so no second core mode exists to drift. OpenCode loads
# every ~/.config/opencode/plugin/*.ts globally with no build step; the tree is replaced whole so a
# plugin the harness stops shipping stops loading.
install_opencode_plugin() {
  replace_dir "$OPENCODE_HOME/plugin" "$HARNESS_SOURCE/opencode/plugin"
}

# settings.json is the profile's own file — model choice, enabledPlugins, extraKnownMarketplaces,
# auth-adjacent config — and it is the file that genuinely differs between the profiles here, so it
# is merged and never replaced. Same shape as write_opencode_instructions: drop what a previous run
# of this installer wrote, recognised by the hooks directory it points into, then add back what the
# harness ships now. A matcher group left with no hooks, and an event left with no groups, go too,
# or the file grows an empty shell of every hook ever shipped.
write_claude_settings() {
  local config="$CLAUDE_HOME/settings.json" existing staged

  existing=$(read_json_object "$config")

  staged=$(mktemp -- "$config.XXXXXX")
  printf '%s' "$existing" | jq \
    --arg prefix "$CLAUDE_HOOKS/" \
    --arg binprefix "$LAZAR_BIN/" \
    --arg matcher "$JJ_HOOK_MATCHER" \
    --arg command "$CLAUDE_HOOKS/enforce-jj.sh" \
    --arg lintmatcher "Edit|Write|MultiEdit" \
    --arg lintcommand "$LAZAR_BIN/comment-lint claude-hook" '
      def without_harness_hooks:
        [ .[] | .hooks = [ (.hooks // [])[]
              | select((.command // "") | (startswith($prefix) or startswith($binprefix)) | not) ]
              | select((.hooks | length) > 0) ];
      .hooks = ((.hooks // {}) | with_entries(.value |= without_harness_hooks))
      | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{
          matcher: $matcher,
          hooks: [{ type: "command", command: $command }]
        }, {
          matcher: $lintmatcher,
          hooks: [{ type: "command", command: $lintcommand }]
        }])
      | .hooks |= with_entries(select((.value | length) > 0))
    ' >"$staged" || {
    rm -f -- "$staged"
    die "could not merge $config"
  }
  commit_merge "$staged" "$config"
}

# An agent the harness stops shipping has to stop reviewing, so each directory is replaced
# rather than copied into.
install_agents() {
  local built agent name
  built=$(mktemp -d)
  mkdir -p -- "$built/claude" "$built/opencode"

  for agent in "$HARNESS_SOURCE"/agents/*.md; do
    name=$(basename -- "$agent")
    cp -- "$agent" "$built/claude/$name"
    write_opencode_agent "$agent" "$built/opencode/$name"
  done

  # After the dialect transform, not before, so each runtime's copy is rendered and neither can
  # ship a marker line as instruction.
  render_surface_tree "$built"

  replace_dir "$CLAUDE_HOME/agents" "$built/claude"
  replace_dir "$OPENCODE_HOME/agents" "$built/opencode"
  rm -rf -- "$built"
}

# Writing is opt-in because not writing has to be what a script nobody has read does. A
# code-reviewer subagent ran this file with no argument while CLAUDE_CONFIG_DIR pointed at a live
# harness, and the purge wiped it: 12 skills, 5 agents and a hand-written CLAUDE.md, off the
# machine it was reviewing on. It had been told not to; the brief reached the agent that spawned it
# and stopped there, which is the whole reason this is a line of code and not a line of prose.
#
# The flag rides argv rather than the environment on purpose. The test scrubs with `env -i` and
# passes it alongside, so the one thing that authorises a write is the one thing that cannot arrive
# by inheritance from the shell an agent happens to be standing in. A `HARNESS_INSTALL=1` would
# read the same and hand that back.
for arg in "$@"; do
  case "$arg" in
  --install) APPLY=true ;;
  *) die "$arg is not an argument this takes; it takes --install and nothing else" ;;
  esac
done

# Every other target resolves through the runtime's own config home, which is what lets one
# installer serve the three Claude Code profiles on this laptop. Hooks are the deliberate exception,
# and they can be: settings.json names a hook by absolute path rather than discovering it under a
# config home, so one script serves every profile that points at it and three copies would only give
# three things to drift. That is also why this is a plain shared path and not the symlink the skills
# dir uses — a symlink is there to make a directory appear under a home that globs it, and nothing
# globs this one, so the link would be indirection bought for a lookup that never happens.
#
# The exception is the topology's, not the harness's: a sandbox has one config home and no profiles,
# so there is nothing to share with and it resolves like everything else.
#
# The cost of sharing, stated because it is real. This run purges a directory every profile reads
# but only rewrites the settings.json of the profile it was pointed at, because that is the only one
# it can see: nothing tells it the other two exist. So a run that drops a hook leaves the profiles it
# was not run for wiring a file that is gone, until they are installed too. Every other target has
# the same shape — a profile has last release's CLAUDE.md until its own run — but for those the
# stale profile is merely behind, and for this one it fires a missing file on every prompt. Install
# every profile in one go, and read the plan before the first, not between the second and the third.
case "$HARNESS_SURFACE" in
local) CLAUDE_HOOKS="$HOME/.claude/hooks" ;;
sandbox) CLAUDE_HOOKS="$CLAUDE_HOME/hooks" ;;
*) die "HARNESS_SURFACE is $HARNESS_SURFACE; it takes local or sandbox" ;;
esac

# Only the merges need it, so a run that reports and stops is not the place to insist on it.
[ "$APPLY" = false ] ||
  command -v jq >/dev/null ||
  die "jq is needed to merge OpenCode's instructions array and Claude Code's hooks"

# Before the plan, not before the purge: a report that listed every installed skill under `delete`
# would be answered by the reader, not the script, and the answer it invites is to run it anyway.
assert_purge_root_distinct "$AGENTS_SKILLS"
assert_purge_root_distinct "$OPENCODE_SKILL_SINGULAR"

if [ "$APPLY" = false ]; then
  report_plan "this is what installing would do to this machine"
  printf 'install.sh: nothing was written. Re-run with --install to apply it.\n'
  exit 0
fi

report_plan "installing"

install_instructions
install_philosophy
install_skills
install_opencode_commands
install_agents
install_opencode_plugin

# The wiring before the disk. A merge that dies takes the whole run with it, and the order decides
# which side of the purge it dies on: this way settings.json still names a hook that is still there,
# and the run can be re-read and re-run. The other way round leaves the state this pair exists to
# prevent — a hook purged off the disk and every profile still firing it on every prompt.
#
# The linter bin lands before the settings merge names comment-lint, so a failed merge never leaves
# settings.json pointing at a PreToolUse command that was not written yet.
install_linters
write_claude_settings
install_hooks

printf 'lazar-harness installed to %s and %s for the %s surface, with hooks in %s\n' \
  "$CLAUDE_HOME" "$OPENCODE_HOME" "$HARNESS_SURFACE" "$CLAUDE_HOOKS"
