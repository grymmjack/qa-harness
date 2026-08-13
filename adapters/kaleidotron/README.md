# kaleidotron adapter

Adapter #3, for [kaleidotron](https://github.com/grymmjack/kaleidotron) — a
Rust/egui pixel-art browser. Like `rust-demo` it is **window-relative 1:1** with
no viewport model, so the coordinate map is three lines. The real work is state
isolation.

```sh
cd ~/git/kaleidotron && cargo build --release     # once
cd ~/git/qa-harness  && bin/qa --adapter adapters/kaleidotron   # offscreen by default
```

## What this adapter has to say about the app

| Fact | Value |
|---|---|
| Binary | `$KALEIDOTRON_ROOT/target/release/kaleidotron` (`KALEIDOTRON_ROOT` defaults to `~/git/kaleidotron`) |
| Launch | `--folder <dir>` — opens that folder's thumbnail grid |
| Window | title starts `kaleidotron`, **1100×760** default |
| Match | title **+ pid** — winit sets `_NET_WM_PID`, so the pid genuinely filters |
| Coords | window-origin + 1:1 |
| Config | a wiped sandbox `HOME` + XDG dirs, re-made before every launch |

## Two things worth knowing

**Window matching is unambiguous, unlike DRAW.** eframe → winit sets
`_NET_WM_PID` and `WM_CLASS`, so `xdotool search --pid` really does filter. This
adapter therefore does **not** inherit the stale-window race documented in
ARCHITECTURE.md and needs no `settle` helper. Keeping the pid in the search is
also what stops a test binding the developer's own running kaleidotron.

For the same reason `adapter_quit` deliberately does **not** `pkill -x
kaleidotron` the way `rust-demo` reaps `qa-demo`: this app is one the developer
actually runs, and a blanket pkill would kill their session mid-edit.

**State isolation is the whole job.** kaleidotron persists far more than the demo
— window geometry, egui state, `settings.json`, a ratings sidecar, and a
`views.db` SQLite view history — all under the XDG dirs via eframe's
`storage_dir`. Without isolation a run would inherit the developer's panel
layout, theme, thumbnail size and last folder (none of which are the defaults the
tests were calibrated against) *and* write back over them. `adapter_ensure_config`
wipes and recreates a sandbox `HOME` + `XDG_{CONFIG,DATA,CACHE}_HOME` before
**every launch**, per the config-lock rule — the app saves live state on exit, so
caching the sandbox would leak one test's window size into the next.

Verified: after a run, `/tmp/kaleidotron-qa-home/data/kaleidotron/` holds the
`settings.json` / `views.db` / `keybindings.json` the run produced, and the real
`~/.local/share/kaleidotron` is untouched.

## Calibration notes for new tests

Against the default 1100×760 window:

```
menu bar        y≈11          breadcrumbs   y≈33
activity rail   x 0..52       sort bar      y≈727     status bar  y≈749
thumbnail grid  first row y 55..210, tile centres x = 130, 290, 450, 610
central viewer  the rest; an opened image draws 1:1 at the centre
```

Three moving parts to design around rather than wait out:

- **The metadata OSD** fades in over the top of the viewer (y≈68..170) for a few
  seconds after a file opens, then fades out. Keep regions below it.
- **Tile badges.** A tile carries a git status badge (top-left) and a viewed
  check (top-right). The git badge depends on whether the fixtures are committed,
  so tiles are only ever compared against a baseline taken **in the same run**,
  never a stored golden.
- **Format plugins default OFF** (source code, PDF, audio, 3D, video), and the
  initial folder scan happens *before* `settings.json` is applied — so a fresh
  sandbox lists only ordinary images on the first frame. The fixtures are PNGs
  for exactly this reason. A test that needs another type must enable the plugin
  and re-scan (F5).

**Compare regions of the same size.** `compare` diffs only the overlap of two
differently-sized images, so a mismatched pair reports a small, meaningless count
and *passes*. The first version of `grid.sh`'s did-the-fixtures-load guard
compared a 190×190 region against a 120×100 one and passed against an empty
folder; it now pairs `tile1` with an equally-sized `emptyref` patch of
background. Prove a guard fails when it should — `mv fixtures /tmp/hold; mkdir
fixtures` and re-run — before trusting it.

## Tests

- `grid.sh` — the fixtures render, clicking a tile opens it in the viewer, and
  Escape returns to the grid the file was opened from.

## Fixtures

`fixtures/` holds four 128×128 PNGs in flat colours with distinct shapes, so
thumbnails are unambiguous at grid size and diffs are large and obvious.
Regenerate with:

```sh
magick -size 128x128 xc:'#cc2222' -fill white -draw 'circle 64,64 64,20'          01-red.png
magick -size 128x128 xc:'#22aa44' -fill black -draw 'rectangle 24,24 104,104'     02-green.png
magick -size 128x128 xc:'#2255cc' -fill white -draw 'polygon 64,16 112,112 16,112' 03-blue.png
magick -size 128x128 xc:'#ddbb22' -fill black -draw 'roundrectangle 16,40 112,88 12,12' 04-yellow.png
```
