# draw adapter (reference)

The reference adapter — DRAW (a QB64-PE pixel editor). Filled in at **Phase 4
item 3**: `manifest.sh` here will define launch/quit against `DRAW.run`, window
match by title `"DRAW v"` (QB64-PE exposes no stable window id), the viewport ×
`DISPLAY_SCALE` logical→screen override, the blessed `DRAW.qa.cfg`, and hooks
(`wake_draw`, `canvas_focus`, crash-log dir, `park_window` = Meta+Home).

Its ~97 tests live in the DRAW repo at `DRAW/QA/tests/`. Once the core is ported,
`bin/qa --adapter adapters/draw` re-runs that suite through the toolkit; the goal
is **parity** with today's `draw-qa.sh` results — the proof the extraction kept
behavior identical before a second app (rust-gui) is added.

Until then, the working harness is `DRAW/QA/draw-qa.sh` (the source of the port).
