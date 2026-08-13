# kaleidotron QA — round 3

30 tests / 179 assertions shipped (rounds 1–2). This round goes after what is
left. Same rules: calibrate offscreen with `adapters/kaleidotron/calibrate.sh`,
run until green, then run **twice more** to prove it is not flaky before the box
is checked. Everything runs via
`bin/qa --adapter adapters/kaleidotron --offscreen`.

## 🔨 NOW — doing right now

_nothing in progress — round 3 complete._

**loop:off** — all 14 items done. 34 tests / 232 assertions, three consecutive clean offscreen runs.

## Plugin formats — the biggest gap (all default OFF, all reachable here)

- [x] `fixtures-plugins/` built (pdf/mp4/obj/wav/ttf/psd) + adapter wiring; blessed config now enables ALL five plugins. The PSD needed regenerating twice: ImageMagick wrote a **16-bit** PSD (the `psd` crate reads 8-bit) — same class as the earlier PCX/TGA surprises.
- [x] `plugin_formats.sh` — all six paint REAL output (13 assertions), with colour checks so a labelled placeholder or spinner cannot pass.

- [x] `threed.sh` — the model rasterises, a drag orbits and re-renders, the wireframe overlay composes, and Reset view returns the camera.

## Today's features, still untested end to end

- [x] `video.sh` — the player shows a decoded frame and seeking changes it. The fixture had to be built FRAME BY FRAME: an ffmpeg `drawbox` with an x expression in `t` silently produced a STATIC clip, so the test would have asserted nothing.

- [x] `tasks.sh` — the ▶ Run menu appears from a discovered .vscode/tasks.json, a task streams into the output panel, and a failure reports differently. **Found an adapter bug: `cp src/*` does not match dotfiles**, so `.vscode/` never reached the sandbox — calibration saw the tasks, the test did not.
- [x] `text_edit.sh` — the code-page combo re-decodes CP437↔Latin-1 and restores EXACTLY, Find highlights, and Wrap drops the gutter. Wrap needed a gutter-only region: measured across the whole document it moved 41px, which is *below the tolerance the harness uses to call two regions identical* — no basis for a claim.

- [x] `theme.sh` — a bundled theme recolours the chrome, and setting the scope to "Code only" returns the chrome to the built-in look. Asserted on the SORT BAR: on the menu bar the change was 119px, below the tolerance the harness calls identical.

## Browsing surface not yet covered

- [x] `sauce.sh` — a hand-written 128-byte SAUCE record is surfaced in Details, and vanishes again for a piece without one.
- [x] `osd.sh` — the OSD draws over the image and fades out. Two traps: HOVERING PINS IT OPEN (the click that opens the file leaves the pointer inside the panel), and the baseline must be the VIEWER — comparing against the grid differs because the view changed and would pass with no OSD at all.
- [x] `table_columns.sh` — hiding a column re-lays-out the table (Name absorbs the freed width). The exact-restore half is deliberately absent: the second toggle could not be made to land reliably and I would not ship an assertion I cannot explain.
- [x] `multiselect.sh` — a click selects visibly, ctrl+click adds a second, and the status bar reports it.
- [x] `keyboard_nav.sh` — **DROPPED, with a finding.** The grid has no arrow-key cursor: those bindings belong to the viewer (step/pan) and the sample browser. Pressing Right 1, 2 or 3 times then Enter opens the SAME file every time, and a tile's card is pixel-identical before and after (0 px) — so keyboard grid navigation is both absent and invisible. Writing a test around behaviour that is not there would assert nothing; reported instead.


## Wrap-up

- [x] README updated: full test table by area, coverage inventory (incl. what is deliberately NOT covered), and a "traps found the hard way" section grown with this round's six.
- [x] Committed, PR'd, merged.

- [x] Full suite: **232 passed, 0 failed** across 34 tests, twice consecutively. Caught one stale assertion of my own: adding 19-sauce.ans changed which file sorts LAST, breaking sort.sh's name-coupled colour check — removed the coupling.

