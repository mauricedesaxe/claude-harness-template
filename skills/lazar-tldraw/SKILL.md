---
name: lazar-tldraw
description: Draw on a tldraw canvas by describing what you want (talk or voice-to-text): generates .tldr JSON and exports PNG/SVG via @kitschpatrol/tldraw-cli. Use for system-design / architecture diagrams, API / sequence flows, database / ERD schemas, flowcharts, ML diagrams, AND low-fidelity fat-marker UI/UX wireframes + product shape-up sketches. Also use proactively when explaining a system with 3+ components, a data flow, or sketching a screen/flow before building it.
license: MIT
homepage: https://github.com/Agents365-ai/tldraw-skill
compatibility: Requires Node.js + @kitschpatrol/tldraw-cli on PATH (macOS/Linux/Windows). Self-check step requires a vision-enabled model (e.g., Claude Sonnet/Opus); gracefully skipped if unavailable.
platforms: [macos, linux, windows]
metadata: {"openclaw":{"requires":{"bins":["tldraw"]},"emoji":"📝","os":["darwin","linux","win32"],"install":[{"id":"npm-tldraw","kind":"npm","package":"@kitschpatrol/tldraw-cli","global":true,"bins":["tldraw"],"label":"Install tldraw-cli via npm"}]},"hermes":{"tags":["tldraw","diagram","flowchart","architecture","whiteboard","visualization"],"category":"design","requires_tools":["tldraw"],"related_skills":["drawio","mermaid","excalidraw","plantuml"]},"author":"Agents365-ai","version":"1.2.1"}
---

> **Generated file.** Vendored from
> [Agents365-ai/tldraw-skill](https://github.com/Agents365-ai/tldraw-skill) (MIT, see `LICENSE`)
> by `vendor-skills.sh`, which re-applies `patches/lazar-tldraw.patch` to upstream on every run.
> A re-vendor overwrites this file, so an edit left sitting here is an edit lost: change it, then
> run `./vendor-skills.sh --regen-patch` to fold the change back into the patch that carries it.
> The local patch adds the **UI/UX Wireframe** and **Product Shape-up sketch** presets, widens the
> triggers, and fixes the sizing and spacing rules that made diagrams come out packed with text
> overflowing its shapes.
> Requires `@kitschpatrol/tldraw-cli` on PATH (`npm install -g @kitschpatrol/tldraw-cli`).

# tldraw Whiteboard Diagrams

<!-- surface:local -->

## Where the drawing ends up

On disk, as a `.tldr` plus a PNG/SVG export you show the user and iterate on. That's the workflow
the rest of this file describes, and every command in it runs here.

<!-- /surface:local -->

<!-- surface:sandbox -->

## Where the drawing ends up: the session's live board, not this file's workflow

**Use the runtime's `whiteboard` skill and stop reading this one for the how.** Open Inspect
renders a live tldraw canvas in the session side panel, and that board is the only diagram anyone
sees here. The user can pan it, edit it, and draw on it while you're drawing on it. Nothing on
this surface renders a `.tldr`: `@kitschpatrol/tldraw-cli` is deliberately not installed, and
there's no viewer and no browser to open an export in, so the export commands below all fail.

`whiteboard` ships with the sandbox and drives the board through a `board` command on PATH
(`board create`, `board mutate`, `board snapshot`). It owns the record format; read it there.

**Its records are not this file's records**, so don't translate one into the other. The live board
validates against a later tldraw schema and rejects these shapes outright rather than degrading
them: labels are `props.richText` rather than `props.text`, arrows bind through standalone
`binding:` records rather than `props.start.boundShapeId`, and the page is `page:page`. Carrying a
shape across is how you get a batch rejected whole.

What this file is still good for here is the judgement, not the JSON: whether a diagram is worth
drawing at all, which diagram type fits, and the layout and label-sizing rules.

**The loop doesn't wait to be approved.** Locally it runs until the user says approved, done, or
LGTM. Here the board is live and in front of them the moment it's created, so creating it *is* the
handoff, not a draft awaiting sign-off. Draw it, name its title and board id in your final report,
and stop. Whoever's watching the panel edits it directly or asks for a change in a later turn;
whoever isn't still gets a finished board waiting for them. Blocking on an approval that may have
nobody to give it strands the diagram in a sandbox that's about to be torn down.

<!-- /surface:sandbox -->

## Overview

Generate modern whiteboard-style diagrams as `.tldr` JSON files and export to PNG/SVG using `@kitschpatrol/tldraw-cli`. tldraw produces clean hand-drawn aesthetic diagrams with rich shape libraries and smooth arrow routing, and it is well-suited for casual or whiteboard-style visualizations.

**Format:** `.tldr` JSON
**Export:** PNG, SVG (via `@kitschpatrol/tldraw-cli`)
**Aesthetic:** Hand-drawn whiteboard style by default; switchable to clean fonts via `font` prop.

## When to Use

**Explicit triggers:** user says "diagram", "flowchart", "draw", "visualize", "whiteboard diagram", "tldraw diagram", "architecture diagram", "system design", "API design", "database / ERD design", "sketch this out", "wireframe", "mockup", "UI sketch", "low-fi / lo-fi", "shape up", "breadboard".

**Proactive triggers:**
- Explaining a system with 3+ interacting components
- Describing a multi-step process, data flow, or pipeline
- Showing relationships between services/modules
- Architecture overviews, sequence flows, decision trees, ML model layers
- Sketching a screen or UI layout before building it (low-fi wireframe)
- Shaping a product idea's elements and flow before committing (Shape Up)

**Skip when:** a simple list or table suffices, the user wants a polished business-presentation diagram (prefer drawio-skill), or the user is in a quick Q&A flow.

**When NOT to use it, route elsewhere:**
- Logos / solid-color graphics / filled icons: tldraw has **no opaque fill** (`solid` = light tint; white-on-dark can't be reproduced) → use the **drawio** skill or the original vector file.
- Precise vector geometry or strict (hollow-arrow) UML → **drawio** (or **plantuml** for UML).
- Auto-layout of many nodes → **mermaid** (tldraw needs manual coordinates).
- A pixel-faithful copy of an existing image → not a diagram-skill task.

## Prerequisites

```bash
# Install tldraw-cli
npm install -g @kitschpatrol/tldraw-cli

# Verify
tldraw --version
```

Works identically on macOS, Windows, and Linux.

**First-export note:** `tldraw export` renders through a pinned Chrome build via puppeteer. The first export can fail with `Could not find Chrome (ver. <x>)`. The error names the exact version it needs. Install it once, then exports work:

```bash
# The error message names the version; substitute it here
npx puppeteer browsers install chrome@<version-from-error>
```

(Installs to `~/.cache/puppeteer`; only needed once per CLI version.)

## Workflow

Before starting, assess whether the user's request is specific enough. If key details are missing, ask 1-3 focused questions:
- **Diagram type**: which preset? (Architecture, Flowchart, Sequence, ML/DL, ERD, UML, or general)
- **Output format**: PNG (default), SVG?
- **Output location**: default is the user's working dir; honor any explicit path the user gives (e.g. "put it in `./artifacts/`"). Don't ask if they didn't mention one.
- **Scope/fidelity**: how many components? Any specific technologies or labels?

Skip clarification if the request already specifies these details or is clearly simple (e.g., "draw a flowchart of X").

1. **Check deps**: verify `tldraw --version` succeeds; if missing, run `npm install -g @kitschpatrol/tldraw-cli`.
2. **Plan**: identify shapes (geo type per node), connections (arrows with source/target), and layout (TB or LR, group by tier/role). Sketch a coordinate grid before writing JSON.
3. **Generate**: write the `.tldr` JSON file. Default output dir is the user's working dir; if the user specified a path or directory (e.g. `./artifacts/`), `mkdir -p` it first and write there. Apply the same dir choice to PNG/SVG exports in steps 4 and 7.
4. **Export draft**: run CLI to produce a PNG for preview.
5. **Self-check**: use the agent's built-in vision capability to read the exported PNG, catch obvious issues, auto-fix before showing the user (requires a vision-enabled model such as Claude Sonnet/Opus). If vision is unavailable, skip this step.
6. **Review loop**: show image to user, collect feedback, apply targeted JSON edits, re-export, repeat until approved.
7. **Final export**: export the approved version to all requested formats; report file paths for both the `.tldr` source and exported image(s).

### Step 5: Self-Check

After exporting the draft PNG, use the agent's vision capability (e.g., Claude's image input) to read the image and check for these issues before showing the user. If the agent does not support vision, skip self-check and show the PNG directly.

tldraw's own AI agent flags exactly three structural defects: **text overflow** (a box too small for its label), **overlapping text**, and **friendless arrows** (an arrow with an unbound end). The first three rows below target those; size boxes correctly up front (see "Sizing shapes to fit labels") and they rarely occur.

| Check | What to look for | Auto-fix action |
|-------|-----------------|-----------------|
| Text overflow | Label spills past the shape's border, or the box looks taller than you set (tldraw auto-grows an undersized box) | Increase `w`/`h` to fit the label, see the sizing formula below |
| Label outside a non-rectangular shape | Label sits inside the shape's bounding box but crosses the drawn outline, past a diamond's points, a triangle's corners, an ellipse's curve | Apply the shape's `geo` factor (see "Sizing shapes to fit labels"), or shorten the label / switch to `rectangle` |
| Overlapping text | Two text-bearing shapes' labels touch or overlap, hurting legibility | Shift shapes apart by ≥200px |
| Friendless arrow | An arrow with one end not connected to a shape (floats loose) | Bind both ends: every arrow's `start` and `end` need a `boundShapeId` matching an existing shape |
| Off-canvas shapes | Shapes at negative coordinates or far from the main group | Move to positive coordinates near the cluster |
| Arrow-shape overlap | An arrow visually crosses through an unrelated shape | Adjust `bend` value or move endpoints to a different `normalizedAnchor` side |
| Stacked arrows | Multiple arrows overlap each other on the same path | Distribute `normalizedAnchor` across the shape perimeter (use different x/y values) |

- Max **2 self-check rounds**. If issues remain after 2 fixes, show the user anyway.
- Re-export after each fix and re-read the new PNG.

### Step 6: Review Loop

After self-check, show the exported image and ask the user for feedback.

**Targeted edit rules.** For each type of feedback, apply the minimal JSON change:

| User request | JSON edit action |
|-------------|-----------------|
| Change color of X | Find shape by `props.text` matching X, update `props.color` |
| Add a new node | Append a new shape record with next available index, position near related nodes |
| Remove a node | Delete the shape record and any arrow records bound to it |
| Move shape X | Update the shape's `x`/`y` fields |
| Resize shape X | Update `props.w`/`props.h` |
| Add arrow from A to B | Append a new arrow record binding to A and B's shape ids |
| Change label text | Update `props.text` on the matching shape or arrow |
| Change layout direction | **Full regeneration**: replan the grid and rebuild |

**Rules:**
- For single-element changes: edit the existing JSON in place, which preserves layout tuning from prior iterations.
- For layout-wide changes (e.g., swap LR↔TB, "start over"): regenerate full JSON.
- Overwrite the same `{name}.png` each iteration. do not create `v1`, `v2`, `v3` files.
- After applying edits, re-export and show the updated image.
- Loop continues until user says approved / done / LGTM.
- **Safety valve:** after 5 iteration rounds, suggest the user open the `.tldr` file in tldraw.com or the desktop app for fine-grained adjustments.

---

## File Format

### Complete .tldr Skeleton

```json
{
  "tldrawFileFormatVersion": 1,
  "schema": {
    "schemaVersion": 1,
    "storeVersion": 4,
    "recordVersions": {
      "asset": {"version": 1, "subTypeKey": "type", "subTypeVersions": {"image": 2, "video": 2, "bookmark": 0}},
      "camera": {"version": 1},
      "document": {"version": 2},
      "instance": {"version": 17},
      "instance_page_state": {"version": 3},
      "page": {"version": 1},
      "shape": {"version": 3, "subTypeKey": "type", "subTypeVersions": {"group": 0, "embed": 4, "bookmark": 1, "image": 2, "text": 1, "draw": 1, "geo": 7, "line": 0, "note": 4, "frame": 0, "arrow": 1, "highlight": 0, "video": 1}},
      "instance_presence": {"version": 4},
      "pointer": {"version": 1}
    }
  },
  "records": [
    {"id": "document:document", "typeName": "document", "gridSize": 10, "name": "", "meta": {}},
    {"id": "page:page1", "typeName": "page", "name": "Page 1", "index": "a1", "meta": {}}
    /* shapes and arrows go here */
  ]
}
```

**Critical rules:**
- `document:document` and `page:page1` records are ALWAYS required.
- All shapes go in the `records` array after the page record.
- All shapes have `"parentId": "page:page1"`.
- Shape IDs use format `"shape:xxx"` with unique suffix (e.g., `"shape:s1"`, `"shape:a1"`).
- `index` values are fractional-index keys. Use `"a"` + **one** base-62 character, in order: `"a0"`–`"a9"`, then `"aA"`–`"aZ"`, then `"aa"`–`"az"` (62 ordered keys, enough for any normal diagram).
- **Do not append a second character: `"a10"` is invalid.** And never use a leading `"b"`/`"c"` (`"b1"`, `"c1"`, `"b0"`). Those encode a longer integer part, so they are malformed fractional keys and trigger `invalidRecords`. Stick to the single-character `"a*"` keys above.

---

## Geo Shape Record

```json
{
  "id": "shape:s1",
  "typeName": "shape",
  "type": "geo",
  "parentId": "page:page1",
  "index": "a1",
  "x": 100,
  "y": 100,
  "rotation": 0,
  "isLocked": false,
  "opacity": 1,
  "meta": {},
  "props": {
    "w": 200,
    "h": 60,
    "geo": "rectangle",
    "color": "blue",
    "labelColor": "black",
    "fill": "semi",
    "dash": "draw",
    "size": "m",
    "font": "draw",
    "text": "API Gateway",
    "align": "middle",
    "verticalAlign": "middle",
    "growY": 0,
    "url": ""
  }
}
```

**`w` and `h` above are worked examples, not defaults.** They are what the sizing rules below
yield for a size-`m` `rectangle` labeled `"API Gateway"`, nothing more. Copying `200`/`60` onto a
shape with a longer label or a non-rectangular `geo` is the single biggest source of unreadable
diagrams. Compute both from the label and the `geo` before you write the record: see
"Sizing shapes to fit labels".

### Geo Types

| `geo` value | Use for |
|-------------|---------|
| `rectangle` | services, modules, components |
| `ellipse` | databases, start/end nodes |
| `oval` | pill-shaped start/end terminators (flowcharts) |
| `diamond` | decision points |
| `cloud` | external services, infrastructure |
| `hexagon` | event hubs, message buses |
| `triangle` | gateways, load balancers |
| `star` | highlights, key features |
| `pentagon` | stages, milestones |
| `octagon` | stop / terminal / blocking states |
| `trapezoid` | manual operations, transforms |
| `rhombus` / `rhombus-2` | parallelograms, I/O steps (left/right slant) |
| `arrow-right` / `arrow-left` / `arrow-up` / `arrow-down` | directional flow blocks, data movement |
| `x-box` | failed / invalid / rejected states (box with ✕) |
| `check-box` | passed / validated / done states (box with ✓) |
| `heart` | accents (rarely needed for technical diagrams) |

All 20 `geo` values are valid; the above are the useful subset for technical diagrams.

### Color Palette

| `color` | Use for |
|---------|---------|
| `blue` | clients, core services |
| `green` | success, databases, storage |
| `orange` | queues, event buses, warnings |
| `red` | external APIs, errors, alerts |
| `light-red` | soft alerts, secondary warnings |
| `violet` | gateways, security, auth |
| `yellow` | decisions, caches |
| `grey` | neutral, background, legacy |
| `light-blue` | secondary services, metadata |
| `light-violet` | soft auth/security, secondary gateways |
| `light-green` | soft success, secondary storage |
| `white` | blank/empty nodes, placeholders (pair with `fill: solid`) |
| `black` | titles, emphasis |

Full palette (13): `black`, `grey`, `light-violet`, `violet`, `blue`, `light-blue`, `yellow`, `orange`, `green`, `light-green`, `light-red`, `red`, `white`.

### Style Options

| Property | Values | Notes |
|----------|--------|-------|
| `fill` | `semi`, `solid`, `none`, `pattern` | `semi` = tinted fill (recommended) |
| `dash` | `draw`, `solid`, `dashed`, `dotted` | `draw` = hand-drawn default |
| `size` | `s`, `m`, `l`, `xl` | `m` = default |
| `font` | `draw`, `sans`, `serif`, `mono` | `draw` = default whiteboard style |

---

## Arrow Record

```json
{
  "id": "shape:a1",
  "typeName": "shape",
  "type": "arrow",
  "parentId": "page:page1",
  "index": "aG",
  "x": 0,
  "y": 0,
  "rotation": 0,
  "isLocked": false,
  "opacity": 1,
  "meta": {},
  "props": {
    "dash": "draw",
    "size": "m",
    "fill": "none",
    "color": "black",
    "labelColor": "black",
    "bend": 0,
    "start": {
      "type": "binding",
      "boundShapeId": "shape:s1",
      "normalizedAnchor": {"x": 0.5, "y": 1},
      "isExact": false
    },
    "end": {
      "type": "binding",
      "boundShapeId": "shape:s2",
      "normalizedAnchor": {"x": 0.5, "y": 0},
      "isExact": false
    },
    "arrowheadStart": "none",
    "arrowheadEnd": "arrow",
    "text": "",
    "font": "draw"
  }
}
```

### Arrow Connection Rules

- Arrow record `x` and `y` are always `0, 0`.
- Use `"type": "binding"` with `boundShapeId` to connect to a specific shape.
- `normalizedAnchor` specifies WHERE on the target shape the arrow connects (0–1 range):
  - `{x: 0.5, y: 0}` = top center
  - `{x: 0.5, y: 1}` = bottom center
  - `{x: 0, y: 0.5}` = left center
  - `{x: 1, y: 0.5}` = right center
  - `{x: 0.5, y: 0.5}` = center
- Add `"text": "label"` in arrow props for labeled connections.
- Use `"bend": 20` (or `-20`) for slight curves to avoid overlap with other arrows.
- For dashed/dotted arrows (e.g., async flows, optional links), set `"dash": "dashed"` or `"dotted"`.
- Set `"spline": "cubic"` for a smooth curved arrow (default `"line"` is straight/elbow). Useful for skip connections and back-edges.

### Arrowheads

`arrowheadStart` and `arrowheadEnd` each accept any of these 9 values (all render in `@kitschpatrol/tldraw-cli`):

| Value | Looks like | Use for |
|-------|-----------|---------|
| `none` | (no head) | start of a one-way arrow |
| `arrow` | open V | default flow direction |
| `triangle` | filled ▶ | UML inheritance / "is-a" |
| `diamond` | filled ◆ | UML composition / aggregation (on the owner end) |
| `dot` | ● | sequence-diagram message endpoints |
| `square` | ■ | terminal / fixed endpoint |
| `bar` | \| | "stop" / boundary marker |
| `pipe` | \|\| | alternative boundary marker |
| `inverted` | hollow V | de-emphasized direction |

Default arrows use `"arrowheadStart": "none"`, `"arrowheadEnd": "arrow"`. For bidirectional links set both ends to `"arrow"`.

### Distributing Arrows on a Shape

When multiple arrows connect to the same shape, assign different `normalizedAnchor` points to prevent stacking:

| Position | x | y | Use when |
|----------|---|---|----------|
| Top center | 0.5 | 0 | connecting to node above |
| Top-left | 0.25 | 0 | 2nd connection from top |
| Top-right | 0.75 | 0 | 3rd connection from top |
| Right center | 1 | 0.5 | connecting to node on right |
| Bottom center | 0.5 | 1 | connecting to node below |
| Left center | 0 | 0.5 | connecting to node on left |

**Rule:** if a shape has N connections on one side, space them evenly (e.g., 3 connections on bottom → x = 0.25, 0.5, 0.75).

### Multiple Arrows Between the Same Two Nodes

The anchor-distribution rule above spreads arrows going to *different* nodes. When **N arrows connect the same pair** (e.g., bidirectional request/response, or several relationships A↔B), anchors can't separate them. instead spread the `bend` values symmetrically so the arrows fan out into distinct arcs:

- Pick a max bend `amount` (≈ 30–60; larger for nodes that are far apart).
- Assign the N arrows bends evenly spaced from `−amount` to `+amount`:
  - **2 arrows** → `bend: -amount`, `bend: +amount`
  - **3 arrows** → `bend: -amount`, `0`, `+amount`
  - General: `bend[i] = -amount + i * (2*amount / (N-1))` for `i = 0..N-1`
- A straight arrow plus a single curved one (`bend: 0` and `bend: 40`) reads cleanly for a request/response pair.

---

## Container & Annotation Shapes

Beyond `geo` and `arrow`, two more shape types are useful for technical diagrams.

### Frame (labeled container: tiers, subsystems, swimlanes)

A `frame` is a native rectangular container with a title. Use it to group a tier or subsystem with a visible boundary; stack several frames to approximate swimlanes.

```json
{
  "id": "shape:frame1", "typeName": "shape", "type": "frame",
  "parentId": "page:page1", "index": "a1",
  "x": 60, "y": 60, "rotation": 0, "isLocked": false, "opacity": 1, "meta": {},
  "props": { "w": 360, "h": 220, "name": "Backend Tier", "color": "black" }
}
```

- `props.name` is the title shown at the frame's top-left.
- **Child shapes set `"parentId": "shape:frame1"`** (not `page:page1`), and their `x`/`y` are **relative to the frame's top-left corner**, not the page. A child at `x: 40, y: 60` sits 40px in and 60px down from the frame's origin.
- Frames render as a clean (non-hand-drawn) rectangle, good for structural grouping. Arrows can still bind across frames normally.

### Note (sticky-note annotation / callout)

A `note` is a sticky note, ideal for TODOs, callouts, and comments layered onto a diagram.

```json
{
  "id": "shape:n1", "typeName": "shape", "type": "note",
  "parentId": "page:page1", "index": "a4",
  "x": 480, "y": 80, "rotation": 0, "isLocked": false, "opacity": 1, "meta": {},
  "props": { "color": "yellow", "size": "m", "text": "TODO: add retry\nlogic here",
    "font": "draw", "align": "middle", "verticalAlign": "middle",
    "growY": 0, "fontSizeAdjustment": 0, "url": "", "scale": 1, "labelColor": "black" }
}
```

- A note has **no `w`/`h`**. It's a fixed square (~200px) that auto-grows for longer text. Don't add `w`/`h`.
- `yellow` is the classic sticky color; any palette color works.
- Use notes sparingly, for annotations *about* the diagram, not as primary nodes (use `geo` for those).

---

## Index Ordering Rules

Indices control z-order (stacking). Use this sequence:
```
a1, a2, a3, a4, a5, a6, a7, a8, a9,
aA, aB, aC, aD, aE, aF, aG, aH, aI, aJ, aK, aL, aM,
aN, aO, aP, aQ, aR, aS, aT, aU, aV, aW, aX, aY, aZ,
aa, ab, ac, ... az          ← continue here past aZ; never "a10"
```
- Geo shapes first: `a1` through `aF` (or as many as needed).
- Arrow shapes after: `aG`, `aH`, etc.
- Every shape must have a **unique** index.

---

## Layout Tips

**Spacing, scale with complexity:**

| Diagram complexity | Nodes | Horizontal gap | Vertical gap |
|-------------------|-------|----------------|--------------|
| Simple | ≤5 | 200px | 150px |
| Medium | 6–10 | 280px | 200px |
| Complex | >10 | 350px | 250px |

**These gaps are empty space between two shapes' facing edges, they are not a
centre-to-centre pitch, and not a step to add to `x`.** Getting this backwards is the other
half of "the diagram looks cramped": shapes are sized to their labels, so a fixed step makes the
real gap *shrink as labels get longer*, so a 280px step past a 280px-wide `"Payments Service"` box
leaves exactly 0px, and the two boxes touch. Place each shape from the **previous shape's actual
size**:

```
x_next = x_prev + w_prev + horizontal_gap
y_next = y_prev + h_prev + vertical_gap
```

For a row of shapes with different widths, that means a different step per shape. Centre a row by
computing its total width (`Σ w + gaps`) first, then laying it out from the left edge, never by
assuming every shape is the same size.

**Sizing shapes to fit labels (do this up front, not in self-check):** the `draw` font is wide. Compute `w`/`h` from the label so text never clips. Approximate per-character width and line height for the default `draw` font:

| `size` | char width (px) | line height (px) |
|--------|-----------------|------------------|
| `s` | 11 | 18 |
| `m` (default) | 15 | 28 |
| `l` | 22 | 40 |
| `xl` | 32 | 56 |

With `padding = 16` on each side:
- `w = ceil(longest_line_chars * char_width + 2*padding)`, then round up to the next multiple of 10.
- `h = ceil(num_lines * line_height + 2*padding)`, rounded up to a multiple of 10.

Example: a size-`m` box labeled `"API Gateway"` (11 chars, 1 line) → `w ≈ 11*15 + 32 = 197 → 200`, `h ≈ 28 + 32 = 60`. Multi-line labels (with `\n`) count the **longest** line for `w` and the line count for `h`. Err slightly large: extra padding looks fine, a too-narrow box hard-wraps a word mid-letters.

**Why this matters:** if a box is too short for its text, tldraw silently **grows it taller** on render (it sets the shape's `growY`), so the box ends up bigger than the `h` you wrote and collides with whatever you placed below it. Sizing correctly up front keeps `growY` at 0 and your layout intact. This is the single most common cause of "the diagram looks cramped / boxes overlap" after export.

**Then scale for the `geo`, and the formula above is for a `rectangle` only.** tldraw lays a label
into the shape's **bounding box**, not into the outline it draws inside that box. So on any shape
that isn't a full-bleed rectangle, a label sized to `w`×`h` renders *outside the drawn edges*: it
spills past a diamond's left and right points, past a triangle's bottom corners, past an ellipse's
curve. Worst on the shapes the presets reach for most: `triangle` gateways, `diamond` decisions,
`ellipse` databases, `cloud` external APIs.

Multiply the rectangle's `w`/`h` by the shape's factor, then round up to a multiple of 10:

| `geo` | `w` × | `h` × | Why |
|-------|-------|-------|-----|
| `rectangle`, `x-box`, `check-box` | 1.0 | 1.0 | the label's box *is* the shape |
| `oval` | 1.1 | 1.0 | only the rounded ends cut in |
| `octagon` | 1.3 | 1.3 | corners clipped |
| `hexagon` | 1.4 | 1.3 | slanted sides cut into the label's line |
| `trapezoid` | 1.5 | 1.2 | one edge slants across the label |
| `ellipse`, `pentagon` | 1.5 | 1.5 | the curve is tightest exactly at the label's line |
| `rhombus`, `rhombus-2` | 1.6 | 1.2 | the slant offsets the whole line sideways |
| `cloud` | 1.6 | 1.6 | bumps eat the corners |
| `diamond` | 2.0 | 2.0 | the label sits at the diamond's *waist*, its narrowest span |
| `triangle` | 2.2 | 1.8 | mid-height is only half the base width |
| `star` | 2.6 | 2.6 | little of the bounding box falls inside the points |

Any other `geo` (the `arrow-*` blocks, `heart`): start at 1.5 × 1.5 and confirm on the export.

Example: `"API Gateway"` in a `triangle` → rectangle size 200×60, then `w = 200*2.2 = 440`,
`h = 60*1.8 = 108 → 110`. In a `diamond` → 400×120.

**The cheaper fix is often a shorter label or a different `geo`.** A `triangle` that needs to say
`"Payments Service"` wants ~640px of width to do it, at which point use a `rectangle` and carry
the meaning in `color`, or shorten the label to `"Gateway"`. Reserve the dramatic shapes for short
labels.

**Routing corridors:** between shape rows/columns, leave an extra ~80px empty corridor where arrows can route without crossing other shapes. Never place a shape in a gap that arrows need to traverse.

**Grid alignment:** snap all `x`, `y`, `w`, `h` values to **multiples of 10**. This matches tldraw's default `gridSize: 10` and makes manual editing easier.

**General rules:**
- Plan the grid before assigning x/y coordinates. Sketch node positions mentally first.
- Group related nodes in the same horizontal or vertical band.
- Place heavily-connected "hub" nodes centrally so arrows radiate outward instead of crossing.
- For wide shapes (like an API Gateway spanning multiple downstream services), set `w` to cover the full span.
- Center-align a child node under its parent (same center x) to avoid diagonal routing.
- **Event bus pattern**: place the bus (hexagon) in the **center of the service row**, not below. Services on either side reach it with short horizontal arrows (`normalizedAnchor.x = 1` left side, `0` right side), eliminating crossings.
- Horizontal connections never cross vertical nodes in the same row; use them for peer-to-peer and publish connections.

**Avoiding arrow-shape overlap:**
- Before finalizing coordinates, trace each arrow path mentally. If it must cross an unrelated shape, either move the shape or use `bend` to curve around.
- For tree/hierarchical layouts: assign nodes to layers (rows), connect only between adjacent layers to minimize crossings.
- For star/hub layouts: place the hub center, satellites around it. Arrows stay short and radial.

---

## Diagram Type Presets

When the user requests a specific diagram type, apply the matching preset below for shapes, colors, and layout conventions.

### Architecture Diagram

| Element | `geo` | `color` | Notes |
|---------|-------|---------|-------|
| Client (web/mobile) | `rectangle` | `blue` | Top row, label by client type |
| Service / module | `rectangle` | `blue` | Mid rows, group by tier |
| Database | `ellipse` | `green` | Bottom row, one per service |
| Cache | `ellipse` | `yellow` | Sits beside its owning service |
| Queue / event bus | `hexagon` | `orange` | **Center of service row** for hub pattern |
| Gateway / load balancer | `triangle` | `violet` | Above services |
| External API | `cloud` | `red` | Edge of canvas, dashed arrows in |
| Auth / security | `rectangle` | `violet` | Often near gateway |

**Layout:** TB or LR by tier count; ≥4 tiers → TB. Hub nodes centered. Spacing scales with complexity (see table above).

### Flowchart

| Element | `geo` | `color` | Notes |
|---------|-------|---------|-------|
| Start / End | `ellipse` | `green` | Always at top and bottom |
| Process step | `rectangle` | `blue` | Default action box |
| Decision | `diamond` | `yellow` | Always label outgoing arrows (Yes / No) |
| I/O | `rectangle` (with `dash: dashed`) | `orange` | Distinguish from process via dashed border |
| Subprocess | `rectangle` | `violet` | Indicates a callable sub-flow |

**Layout:** TB, ~200px vertical gap. Decisions branch left/right, then merge back to center. Always label decision branches in the arrow's `props.text`.

### Sequence Diagram

tldraw doesn't have native lifeline shapes. Approximate with:

| Element | `geo` | `color` | Notes |
|---------|-------|---------|-------|
| Actor / object header | `rectangle` | `blue` | Top of column |
| Lifeline | `rectangle` (`w: 2`, `fill: solid`, `color: grey`) | `grey` | Thin vertical line under each actor header |
| Sync message | arrow with `arrowheadEnd: arrow` | `black` | Solid horizontal arrow |
| Async message | arrow with `dash: dashed` | `black` | Dashed horizontal arrow |
| Return message | arrow with `dash: dashed`, `color: grey` | `grey` | Grey dashed |

**Layout:** LR for actors (200–280px gap between their edges), TB for time. Each message is a horizontal arrow between two lifelines at increasing `y`.

### ML / Deep Learning Model Diagram

For neural network architecture diagrams, useful for paper figures and explainers.

| Element | `geo` | `color` | Notes |
|---------|-------|---------|-------|
| Input / Output | `rectangle` | `green` | Top and bottom of stack |
| Conv / Pooling | `rectangle` | `blue` | Standard layer block |
| Attention / Transformer | `rectangle` | `violet` | Distinct color for self-attention blocks |
| RNN / LSTM / GRU | `rectangle` | `yellow` | Recurrent layers |
| FC / Linear | `rectangle` | `orange` | Dense projection layers |
| Loss / Activation | `rectangle` | `red` | Final loss / softmax / activation |
| Skip connection | arrow with `bend: 30`, `dash: dashed` | `grey` | Curved dashed bypass |

**Tensor shape annotation:** include the dimensions in `props.text` on a second line. Tldraw renders `\n` literally inside JSON strings, so use a real newline (the JSON encoder will write `\n`):

```
"text": "Conv2D\n(B, 64, 32, 32)"
```

**Layout:** TB (data flows top → bottom), ~150px gap between one layer's bottom edge and the next layer's top edge. Skip connections curve around the main stack.

### ER Diagram (ERD)

tldraw lacks native table/row shapes. Approximate each entity as a tall rectangle with multi-line text.

| Element | `geo` | `color` | Notes |
|---------|-------|---------|-------|
| Entity | `rectangle` (`fill: solid`, `color: light-blue`) | `light-blue` | Title + columns as one multi-line text label |
| Column list | embedded in `props.text` with `\n` between rows | n/a | Mark PK with `*` prefix, FK with `>` |
| Relationship | arrow with `arrowheadStart: arrow`, `arrowheadEnd: arrow` | `black` | Both ends arrowed for many-to-many |
| Optional / weak relationship | arrow with `dash: dashed` | `grey` | Dashed for optional FK |

Label the arrow with cardinality (e.g., `1..*`, `0..1`) via `props.text`.

**Layout:** TB or grid; ≥300px of empty space between entity edges to leave room for column lists.

### UML Class Diagram

| Element | `geo` | `color` | Notes |
|---------|-------|---------|-------|
| Class | `rectangle` (`fill: solid`, `color: light-blue`) | `light-blue` | Title + attributes + methods as one multi-line `text` |
| Inheritance | arrow with `arrowheadEnd: triangle` | `black` | tldraw renders a filled `triangle` arrowhead. Point it at the parent class |
| Composition | arrow with `arrowheadStart: diamond`, `arrowheadEnd: none` | `black` | tldraw renders a filled `diamond` head. Put it on the owner (whole) end |
| Aggregation | arrow with `arrowheadStart: diamond` | `black` | Same diamond head; distinguish from composition via a label or note |
| Association | arrow with `arrowheadEnd: arrow` | `black` | Standard arrow |

**Note:** tldraw's `triangle`/`diamond` arrowheads are **filled**, whereas strict UML uses *hollow* triangles (inheritance) and either filled/hollow diamonds (composition/aggregation). The shapes read correctly for sketches and explainers; for publication-grade UML with hollow heads, drawio-skill (separate skill) is a better fit.

**Layout:** TB, ~250px of empty space between class edges, interfaces above implementations.

### UI / UX Wireframe (low-fidelity, fat-marker)

Rough screen mockups, not pixel-faithful UI. The hand-drawn look is the point, it signals
"this is a sketch, argue with the layout, not the pixels."

| Element | How to draw it |
|---------|----------------|
| Screen / viewport boundary | `frame` with the URL or screen name as `props.name`; place all screen content as its **children** (child `x`/`y` are relative to the frame's top-left) |
| UI region / card / panel | `rectangle`, `fill: none`, `color: grey`, `dash: draw`, an outline box |
| Button / chip / tag / pill | small `rectangle`, `fill: semi`, `size: s`; color by **role**: blue primary, grey secondary, green go/confirm, red destructive, violet nav/meta, light-blue info |
| Body text / paragraph (greeking) | thin `rectangle`, `fill: solid`, `color: grey`, `h: 16`, varied `w`; stack 2–3 to imply a paragraph. **Never** write lorem ipsum |
| Heading / label | `rectangle`, `fill: none`, real text, `size: m`/`l` |
| Input field | `rectangle`, `fill: none`, placeholder text left-aligned (`align: start`) |
| Annotation / callout | `note` (sticky) in `yellow`, for design notes *about* the screen |
| Meter / status / rating | short `rectangle` whose text is a glyph run (e.g. `●●●●○○`) |

**Conventions:**
- Keep `font: draw` and `dash: draw` everywhere, the marker aesthetic *is* the low-fi signal.
- One vertical column per screen, regions stacked top→down. For multiple screens (states,
  responsive variants, before/after) place several `frame`s side by side.
- **Size every box to its label up front** (see "Sizing shapes to fit labels"). A chip that
  overflows past its card is the #1 wireframe defect. Leave ≥20px between a chip's bottom edge
  and its container's bottom edge.
- Convey hierarchy / importance by **position and size**, not color. Reserve color for role.
- Greek the prose; spell out only the words that carry a design decision: the headline, the
  button labels, the key numbers. That's what makes it readable as a *wireframe* not a mockup.

**Layout:** single column ~700–760px wide inside the frame; ~40px page padding; each row is its
content height + a ~20px gap. Snap to multiples of 10.

### Product Shape-up sketch (breadboard / fat-marker)

Shaping an idea's elements and flow *before* committing to build it (37signals' Shape Up).
Coarser than a wireframe, deliberately no layout fidelity, so it stays cheap to redraw.

Two modes:

- **Breadboard** (flows & affordances, no layout): draw **places** as `rectangle` (`fill: none`),
  **affordances** (things you can act on / see) as short text lines or small chips inside each
  place, and **connection lines** as `arrow`s whose `props.text` names the *action/transition*
  (e.g. "submit → confirmation"). Lay places left→right in flow order. A breadboard answers "what
  leads where", not "what does it look like".
- **Fat-marker sketch** (rough spatial idea): the UI-wireframe vocabulary above but even coarser, 
  a few big boxes and arrows, no greeking, just the shape of the thing.

**Conventions:**
- Label the arrows with the *action*, not the data.
- Keep it small: a shape-up that needs >8 places has outgrown a sketch and wants a real wireframe.
- Use a `yellow` `note` for the appetite / open question / rabbit-hole callout, the Shape Up
  metadata that isn't part of the flow itself.

---

## Export Commands

```bash
# Check CLI version
tldraw --version

# PNG at 2x scale (recommended), outputs diagram.png in ./
tldraw export diagram.tldr -f png --scale 2 -o ./

# SVG, outputs diagram.svg in ./
tldraw export diagram.tldr -f svg -o ./

# Transparent background
tldraw export diagram.tldr -f png --scale 2 --transparent -o ./

# Dark theme
tldraw export diagram.tldr -f png --scale 2 --dark -o ./

# Custom output directory (e.g. CI artifacts dir), create if missing, then export there
mkdir -p ./artifacts && tldraw export diagram.tldr -f png --scale 2 -o ./artifacts/
```

**Note:** `-o` is an output **directory**, not a file path. The output file is named after the input file (`diagram.tldr` → `diagram.png`).

### Auto-launch after export

Offer to open the `.tldr` file in the user's default tldraw viewer/editor:

| OS | Command |
|----|---------|
| macOS | `open diagram.tldr` |
| Linux | `xdg-open diagram.tldr` |
| Windows | `start diagram.tldr` |

Or upload to https://tldraw.com (drag-and-drop the `.tldr` file) for browser editing.

---

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| `tldraw` command not found | Run `npm install -g @kitschpatrol/tldraw-cli` |
| `Could not find Chrome (ver. X)` on export | Install the pinned build: `npx puppeteer browsers install chrome@X` (use the exact version from the error) |
| `invalidRecords` on export | Use single-character `a` keys (`a1`…`a9`, `aA`…`aZ`, `aa`…`az`); `a10`, `b1`, `c1` are malformed fractional-index keys |
| Blank/empty export | Verify `document:document` and `page:page1` records are present |
| Output file not found | `-o` is a directory; file name matches input: `tldraw export foo.tldr -o ./` → `./foo.png` |
| Arrow doesn't appear | Use `"type": "binding"` with `boundShapeId`; set arrow `x`/`y` to `0,0` |
| Shapes overlap | Step `x`/`y` by the previous shape's own `w`/`h` **plus** the gap, not by a fixed pitch; scale spacing with complexity |
| Box taller than expected / collides below | Label overflowed an undersized box, so tldraw auto-grew it (`growY`). Size `w`/`h` to the label up front using the sizing formula |
| Text not visible | Check `props.text` is set; if `fill: "none"`, ensure text color contrasts |
| Index collision | All shapes must have unique `index` values |
| Shape ID clash | Use unique IDs: `"shape:s1"`, `"shape:s2"`, `"shape:a1"`, etc. |
| Export fails | Ensure the `.tldr` file is valid JSON: `python3 -m json.tool file.tldr > /dev/null` |
| Multi-line label | Use a real newline character inside the JSON string (`"text": "Line1\nLine2"`); tldraw respects `\n` |
| Arrow crosses shape | Use `bend` to curve around, or move endpoint to a different `normalizedAnchor` |
| Iteration loop never ends | After 5 rounds, suggest the user open `.tldr` in tldraw.com for fine-tuning |

---

## Fallback Chain

When tools are unavailable, degrade gracefully:

| Scenario | Behavior |
|----------|----------|
| `tldraw-cli` missing | Generate `.tldr` JSON only; instruct user to drag-and-drop into https://tldraw.com or install the CLI |
| Vision unavailable for self-check | Skip self-check (step 5); proceed directly to showing user the exported PNG |
| Export fails | Validate JSON with `python3 -m json.tool`; deliver the `.tldr` file and suggest opening in tldraw.com |
