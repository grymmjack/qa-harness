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

## macOS caveat — GLUT remaps modifier+clicks

When this adapter runs on **macOS**, DRAW renders through **Apple's GLUT
framework**, whose **"Button Emulation"** is ON by default for a one-button device
(the trackpad, and VMs that present it as one-button). GLUT rewrites modified
clicks into other buttons *before DRAW (or the harness's input) is observed*:

- **Ctrl + Click → right button (button 2)**
- **Option/Alt + Click → middle button (button 3)**

So any test that uses `ctrl_click` / `alt_click` / `with_mods ctrl|alt click ...`
(e.g. DRAW's `modifier-mouse.sh` Alt-eyedrop, Ctrl+click symmetry) will behave
**differently on macOS** than on the linux-x11 driver: an Alt+left-click arrives
at DRAW as a *middle* click, not a left click, and the assertion fails for reasons
that have nothing to do with DRAW or the test.

A future macOS driver/run must therefore **disable GLUT Button Emulation before
launching DRAW** (a per-user `defaults write <domain> <key> -bool false`, read by
GLUT at `glutInit`), or those modifier+click tests can't be trusted. Full
explanation + the exact fix is in the DRAW repo:
`INSTALL/MAC-USERS-README.md` → "Mouse: Option/Ctrl + Click and FreeGLUT Button
Emulation". This is DRAW/QB64-PE-specific, but the general lesson — *a macOS GUI
toolkit can remap modifier+clicks upstream of the app* — is why it lives in the
adapter, not the tests.
