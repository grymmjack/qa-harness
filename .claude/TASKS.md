# kaleidotron QA suite — expansion

Goal: cover as much of kaleidotron's **painted / interactive** surface as the
offscreen harness can reach. Everything here runs via
`bin/qa --adapter adapters/kaleidotron --offscreen`.

Each item = one test file, calibrated with `adapters/kaleidotron/calibrate.sh`,
run until green, then run **twice more** to prove it is not flaky before the box
is checked.

Already shipped (13 tests, 72 assertions): grid, formats, viewer, textmode,
code_view, table, chrome, rating, recolor, transparency, anim, selection, search.

## 🔨 NOW — doing right now

_nothing in progress._

**loop:off** — all 22 done. The last item (`rip.sh`) was unblocked when Rick
pointed at a real RIP corpus.

## Fixtures

- [x] Decoder fixtures: svg, bmp, tga, qoi, ico, .bin, .xb — all verified rendering in the grid. `.rip` written but unverified; folded into formats2.
- [x] Navigation fixtures in a SEPARATE `fixtures-nav/` (subfolder + bundle.zip). Kept out of the main folder because dirs/archives sort FIRST and would shift every calibrated coordinate. Added `kt_goto` (breadcrumb path editor) + `kt_assert_dominant` (channel-dominance assertion) helpers.

## Decode → paint coverage

- [x] `formats2.sh` — svg/bmp/tga/qoi/ico/.bin/.xb all paint. **Found and fixed a real app bug: `.tga` has no magic bytes, so `with_guessed_format` failed and every .tga spun forever** — now extension-routed like code/audio, with a unit test.
- [x] `binary_textmode.sh` — folded into formats2: `kt_assert_dominant` asserts 15-attr.bin renders RED (VGA attr 4) and 16-xbin.xb GREEN (attr 2), which is the red↔blue palette-order bug at the pixel level. Also made every format assertion **spinner-proof** — "differs from blank" passes on a loading spinner, which is how the .tga bug hid.

## Browsing / navigation

- [x] `rip.sh` — done once Rick pointed at a real corpus (`~/git/qb64/.../ripshow/RIP/`, 83 files). Uses DRAGON01 — the scene kaleidotron's own RIP notes are about. Asserts the vector scene rasterises green in BOTH the tile and the canvas, and that **picking a baud restarts it and draws it progressively** (2400 baud is ~20% at 2.5s; faster rates finish the art early and a "mid-draw" frame looks identical to the finished one).

- [x] `history.sh` — mouse buttons 8/9 walk the folder history and repaint. Added `kt_mouse_back`/`kt_mouse_forward` (no core verb covers the thumb buttons).
- [x] `sort.sh` — reversing the sort re-lays-out the row AND changes tile 1's identity, asserted by colour (red 01-red.png ascending → green 16-xbin.xb descending).
- [x] `archive.sh` — a .zip mounts and its members paint in their own colours (magenta/cyan), not spinners. Fixed `kt_goto`: the path field opens PRE-FILLED, so typing appended and Enter silently went nowhere — needs ctrl+a first.

## Docks and panels

- [x] `navigation.sh` — entering/leaving a folder repaints the grid AND rebuilds the breadcrumbs; Backspace restores the parent exactly.

- [x] `details.sh` — hovering a tile draws its preview (asserted by colour) and fills the metadata grid.
- [x] `explorer.sh` — the Places dock paints its contents, not an empty panel. **Rail trap found: the icon at y=89 is "Open folder…", a NATIVE FILE DIALOG that would wedge a run** — the Explorer toggle is y=133. Never guess rail positions; hover and read the tooltip.

## Viewer behaviour

- [x] `pan.sh` — PageDown/End scroll and Home returns exactly; a drag pans. Direction matters: at the top, dragging down is correctly CLAMPED, which the first version misread as a broken drag.

- [x] `stepping.sh` — Left/Right step through the folder, asserted BY COLOUR so landing on the wrong neighbour fails. **Trap: tests are sourced into the runner's shell, so `GREEN=` clobbered its ANSI colour variable** and every later log line printed a PNG path.
- [x] `crt_fx.sh` — the scanline slider and the glow toggle each change the blit.

## Chrome / settings

- [x] `prefs.sh` — Preferences opens (via the rail gear, NOT ctrl+comma), section tabs swap the body, and raising grid spacing re-lays-out the tiles.

- [x] `thumbsize.sh` — Ctrl+wheel resizes tiles; View → Reset restores exactly. Needed a new `kt_ctrl_wheel` helper: `scroll_up` takes COORDS not tick counts, and every core verb focuses the window first, which drops a separately-held modifier. Also caught the first version passing for the WRONG reason (a stray ctrl+plus was zooming the whole UI, not the thumbnails).
- [x] `ui_zoom.sh` — Ctrl +/- scales the CHROME (asserted on the menu bar, which thumbnail zoom can never touch) and restores exactly.
- [x] `immersive_reveal.sh` — in immersive mode the top edge reveals the menu bar and retreating hides it again.

## File operations (safe — fixtures are sandboxed copies)


## Compare mode

- [x] `compare.sh` — picking a source and a diff from two tiles enters the two-pane compare, the diff pane differs from the source pane (the overlay), and Escape restores the grid exactly.


## Wrap-up

- [x] Committed, PR'd and merged: qa-harness#2 (the suite) and kaleidotron#93 (the .tga fix it found).

- [x] Full suite run three times: **173 passed, 0 failed, identical every run** — zero flakes. 29 test files.
- [x] README updated: full test table by area, an honest coverage inventory (incl. what is deliberately NOT covered and why), the offscreen `calibrate.sh` workflow, and a "traps found the hard way" section.

