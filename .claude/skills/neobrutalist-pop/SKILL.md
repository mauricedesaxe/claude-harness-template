---
name: neobrutalist-pop
description: >-
  Build colorful neo-brutalist UI — thick ink borders, hard offset shadows,
  candy-bright accent colors, tactile press physics, and a snappy keyboard-first,
  local-first feel. Use when designing or styling any web UI (marketing sites OR
  apps), building buttons, filter chips, badges/labels, cards, inputs, modals, or
  toasts, or when the user asks for a "neo-brutalist", "Lemon Pie", or "brutalist" look.
---

# Neobrutalist Pop

A colorful, tactile neo-brutalist look: heavy ink outlines, hard offset shadows with
zero blur, candy-bright accents on warm paper, and buttons that physically *press*.
Framework-agnostic — the whole system is plain CSS custom properties + `.brut-*`
classes. Works in a static site or a full app.

A ready-to-import stylesheet ships alongside this skill at `assets/brutpop.css` — it is
exactly the tokens + components below, concatenated. Copy it into a project and
`@import` it, or paste the relevant blocks inline.

## The feel (read this first)

- **Outlined, not soft.** Every interactive thing has an explicit 2–3px ink border.
  Depth comes from hard offset shadows (`4px 4px 0`), never blur or elevation.
- **Colorful but disciplined.** A warm paper canvas, near-black ink, and a small set
  of candy "pop" colors used with intent: lemon = primary, lime = success,
  coral = danger/live, sky = info. One pop dominates per surface.
- **Tactile.** Controls bottom-out on press: shift `2px,2px` and the shadow collapses
  to zero. This is the signature move — it makes the UI feel physical.
- **Heavy type.** Big, black-weight (800–900) headings and labels. Tight, confident.
- **Small radius, not zero.** 3–6px keeps it friendly, not sterile. (Go to `0` only
  for a deliberately harsher variant.)
- **Snappy.** Transitions are 80–120ms. Nothing languid.
- **Keyboard-first & local-first** (when it's an app — see end). Shortcuts on
  everything, optimistic updates, no spinners for local actions.

## Tokens

Drop `assets/brutpop.css` into the project and `@import` it, or paste this `:root`
block in. Everything else references these — retune colors here, not in components.

```css
:root {
  /* Surfaces */
  --paper:   #ffffff;   /* cards, controls */
  --canvas:  #fffbeb;   /* page background — warm cream, not stark white */
  --ink:     #0a0a0a;   /* text */
  --ink-soft:#2a2a2a;   /* secondary text */

  /* Pop palette — the "colorful". One dominant pop per surface. */
  --pop-lemon:  #ffe94a; /* primary / default highlight */
  --pop-lime:   #84cc16; /* success */
  --pop-coral:  #fb7185; /* danger / live */
  --pop-sky:    #38bdf8; /* info */
  --pop-orange: #ff4500; /* hot accent (from Red GTM) */
  --pop-grape:  #c084fc; /* spare accent */
  --tint-lemon: #fef3c7; /* hover / fill tint */

  /* Lines + hard shadows (no blur, no spread — purely geometric) */
  --line:      var(--ink);
  --shadow-sm: 2px 2px 0 0 var(--line);
  --shadow:    4px 4px 0 0 var(--line);
  --shadow-lg: 6px 6px 0 0 var(--line);

  /* Geometry */
  --bw: 2px;        /* control border  */
  --bw-bold: 3px;   /* card / emphasis */
  --r-sm: 3px;      /* badge, kbd      */
  --r:    4px;      /* button, input   */
  --r-lg: 6px;      /* card            */

  /* Motion */
  --press: 2px;     /* press travel == shadow-sm offset */
  --t-fast: 80ms;
  --t: 120ms;
}

@media (prefers-color-scheme: dark) {
  :root {
    --paper:   #171717;
    --canvas:  #0a0a0a;
    --ink:     #fffbeb;
    --ink-soft:#d6ccae;
    --line:    #a89f82;            /* lines go tan in the dark, not pure white */
    --shadow-sm: 2px 2px 0 0 #7d735a;
    --shadow:    4px 4px 0 0 #7d735a;
    --shadow-lg: 6px 6px 0 0 #7d735a;
  }
}
```

## Signature physics (the press)

Apply to anything clickable. This is what makes it feel like Lemon Pie.

```css
.brut-press { transition: transform var(--t-fast) ease, box-shadow var(--t-fast) ease; }
.brut-press:active {
  transform: translate(var(--press), var(--press)); /* shift into the shadow */
  box-shadow: 0 0 0 0 var(--line);                  /* shadow collapses — it lands */
}
```
Variant (Red GTM style): trigger the same shift on `:hover` instead of `:active` for
a "lift to meet you" feel on marketing sites.

## Components

### Buttons  ⭐

```css
.brut-btn {
  display: inline-flex; align-items: center; gap: .5rem;
  padding: .5rem .875rem;
  border: var(--bw) solid var(--line);
  border-radius: var(--r);
  background: var(--paper); color: var(--ink);
  font-weight: 700;
  box-shadow: var(--shadow-sm);
  cursor: pointer;
  transition: transform var(--t-fast) ease, box-shadow var(--t-fast) ease, background var(--t) ease;
  white-space: nowrap;
}
.brut-btn:hover   { background: var(--tint-lemon); }
.brut-btn:active  { transform: translate(var(--press), var(--press)); box-shadow: 0 0 0 0 var(--line); }
.brut-btn:disabled{ opacity: .5; cursor: not-allowed; transform: none; box-shadow: var(--shadow-sm); background: var(--paper); }

.brut-btn-primary { background: var(--pop-lemon); color: var(--ink); }
.brut-btn-danger  { background: var(--pop-coral); color: var(--ink); }
.brut-btn-success { background: var(--pop-lime);  color: var(--ink); }
.brut-btn-icon    { padding: .375rem; }   /* square, for icon-only */
```
```html
<button class="brut-btn brut-btn-primary">Start <kbd class="brut-kbd">Space</kbd></button>
<button class="brut-btn brut-btn-danger">Stop  <kbd class="brut-kbd">Space</kbd></button>
<button class="brut-btn brut-btn-icon" aria-label="Edit">✎</button>
```

### Filter chips  ⭐

A chip is just a `.brut-btn` that wears `.brut-btn-primary` when active. Add a colored
dot to tie a chip to an entity (client, tag, category). Use `aria-pressed` for toggles.

```html
<div class="brut-chips" role="group" aria-label="Filter">
  <button class="brut-btn brut-btn-primary" aria-pressed="true">All</button>
  <button class="brut-btn" aria-pressed="false">
    <span class="brut-dot" style="background:#84cc16"></span> Acme
  </button>
  <button class="brut-btn" aria-pressed="false">Today</button>
</div>
```
```css
.brut-chips { display: flex; flex-wrap: wrap; gap: .5rem; }
.brut-dot {
  height: .75rem; width: .75rem; border-radius: 9999px;
  border: var(--bw) solid var(--line); display: inline-block; vertical-align: middle;
}
```

### Search input  ⭐

Input with a floating shortcut hint. Esc clears, ⌘K focuses (wire in JS).

```html
<div class="brut-search">
  <input class="brut-input" type="text" placeholder="Search descriptions" aria-label="Search" />
  <kbd class="brut-kbd brut-search-hint" aria-hidden="true">⌘K</kbd>
</div>
```
```css
.brut-search { position: relative; }
.brut-search-hint {
  position: absolute; right: .5rem; top: 50%; transform: translateY(-50%);
  opacity: .6; pointer-events: none;
}
.brut-search .brut-input { padding-right: 4rem; }
```

### Badges / entry labels  ⭐

The label that rides on each entry. Pass any color; black text reads on every pop.

```css
.brut-badge {
  display: inline-flex; align-items: center; gap: .375rem;
  padding: .125rem .5rem;
  border: var(--bw) solid var(--line);
  border-radius: var(--r-sm);
  font-size: .75rem; font-weight: 700; line-height: 1.4;
  box-shadow: 1.5px 1.5px 0 0 var(--line);
}
/* Live / recording: coral + a pinging dot */
.brut-badge-live { background: var(--pop-coral); color: var(--ink); }
.brut-ping { position: relative; display: inline-flex; height: .5rem; width: .5rem; }
.brut-ping::before {
  content: ""; position: absolute; inset: 0; border-radius: 9999px;
  background: var(--ink); opacity: .75; animation: brut-ping 1s cubic-bezier(0,0,.2,1) infinite;
}
.brut-ping::after { content: ""; position: relative; height: .5rem; width: .5rem; border-radius: 9999px; background: var(--ink); }
@keyframes brut-ping { 75%,100% { transform: scale(2); opacity: 0; } }
```
```html
<span class="brut-badge" style="background:#84cc16;color:#0a0a0a">Acme</span>
<span class="brut-badge brut-badge-live"><span class="brut-ping"></span> RECORDING</span>
```

### Entry row (badge + buttons together)

```html
<div class="brut-row">
  <span class="brut-row-lead">01:24:10</span>
  <span class="brut-badge" style="background:#38bdf8">Design</span>
  <span class="brut-row-desc">Landing page hero</span>
  <span class="brut-row-actions">
    <button class="brut-btn brut-btn-icon" aria-label="Edit">✎</button>
    <button class="brut-btn brut-btn-icon brut-btn-danger" aria-label="Delete">🗑</button>
  </span>
</div>
```
```css
.brut-row { display: flex; align-items: center; gap: .75rem; padding: .75rem .5rem;
  border-bottom: 1px solid var(--ink-soft); border-radius: var(--r); }
.brut-row:hover { background: var(--tint-lemon); }
.brut-row-lead { font-weight: 900; }
.brut-row-desc { font-weight: 700; flex: 1; min-width: 0;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.brut-row-actions { display: flex; gap: .25rem; }
```

### Cards, inputs, kbd

```css
.brut-card { background: var(--paper); border: var(--bw-bold) solid var(--line);
  border-radius: var(--r-lg); box-shadow: var(--shadow-lg); }

.brut-input, .brut-select { width: 100%; padding: .5rem .75rem;
  border: var(--bw) solid var(--line); border-radius: var(--r);
  background: var(--paper); color: var(--ink); font-weight: 500;
  transition: box-shadow var(--t-fast) ease; }
.brut-input:focus, .brut-select:focus { outline: none; box-shadow: var(--shadow-sm); }
.brut-input::placeholder { color: #9ca3af; }

.brut-kbd { display: inline-flex; align-items: center; justify-content: center;
  min-width: 1.25rem; padding: .0625rem .375rem;
  border: var(--bw) solid var(--line); border-radius: var(--r-sm);
  background: var(--tint-lemon); color: var(--ink);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: .6875rem; font-weight: 700; line-height: 1.4; box-shadow: 1.5px 1.5px 0 0 var(--line); }
```

### Modal & toast

```css
.brut-backdrop { position: fixed; inset: 0; background: rgb(10 10 10 / .4);
  display: flex; align-items: center; justify-content: center; padding: 1rem; z-index: 50; }
.brut-modal { /* compose .brut-card */ padding: 1.5rem; width: 100%; max-width: 28rem; }

.brut-toast { display: flex; align-items: center; gap: .75rem; padding: .75rem 1rem;
  border: var(--bw-bold) solid var(--ink); border-radius: var(--r);
  box-shadow: var(--shadow); font-weight: 700; }
/* tones: background var(--pop-lime) | var(--pop-coral) | var(--pop-lemon) | var(--pop-sky) */
```

## Keyboard-first (apps)

- Bind primary actions to single keys; show the key inside the control via `.brut-kbd`.
- Suggested defaults: `Space` = primary toggle, `⌘K`/`Ctrl+K` = focus search,
  `Esc` = cancel/clear, `Enter` = confirm, `1–9` = pick from a list, single letters
  for nav (e.g. `S` settings).
- Guard global handlers: ignore when focus is in an input/textarea or a modal is open.
- Every shortcut should have a visible hint somewhere — discoverable, not hidden.

## Local-first / optimistic (apps)

- Mutate local state immediately; persist in the background. No spinners for local actions.
- Keep view state (filters, search, open modal) in the URL so reload and back/forward
  just work and links are shareable.
- If there's a server, write optimistically and reconcile quietly; surface failures as
  a toast with an undo/retry action, not a blocking dialog.

## Adapting to your stack

- **Vanilla / any framework:** import `assets/brutpop.css`; use the `.brut-*` classes.
- **Tailwind v4:** paste the token block into `@theme` (rename `--pop-lemon` →
  `--color-pop-lemon` etc. to get `bg-pop-lemon`), keep `.brut-*` as component classes
  in your CSS, or inline the utilities.
- **Tailwind v3:** map tokens in `theme.extend.colors` / `boxShadow`
  (`brutal: '4px 4px 0 #0a0a0a'`) and the `.brut-*` rules into a `@layer components`.
- **Marketing site vibe:** zero radius, single accent (orange), press-on-hover, Syne +
  Inter fonts. **App vibe:** small radius, multi-color pops, press-on-`:active`, heavy
  system font. Same tokens, different dials.

## Do / Don't

**Do** — keep borders explicit and ink-colored · use hard shadows only · let one pop
dominate a surface · use black text on pops · press on interaction · keep motion ≤120ms.

**Don't** — blur or spread shadows · use subtle gray-on-gray borders · stack many pops
at equal weight · round things past ~6px (unless a deliberate variant) · add slow
fades · hide every shortcut.
