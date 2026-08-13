# kaleidotron adapter

Adapter #3, for [kaleidotron](https://github.com/grymmjack/kaleidotron) — a
Rust/egui pixel-art browser. Like `rust-demo` it is **window-relative 1:1** with
no viewport model, so the coordinate map is three lines. The real work is state
isolation.

```sh
cd ~/git/kaleidotron && cargo build --release     # once
cd ~/git/qa-harness  && bin/qa --adapter adapters/kaleidotron   # offscreen by default
```

## What these tests are for

They **extend** kaleidotron's own `cargo test`, they don't repeat it. The 390
in-process tests cover pure logic — decoders, palettes, sorting, ratings, SAUCE,
the RIP rasteriser, CP437 round-trips — and the `egui_kittest` GUI tests drive
menus and dialogs through AccessKit. But kaleidotron's own notes are explicit
that **custom-painted grid tiles carry no accessibility label, so kittest covers
the chrome, not the tiles**.

That gap is this suite's whole remit: **anything painted**. A format can regress
to a blank tile, a placeholder, or another decoder's output with every unit test
still green. A zoom can update its state and never redraw. A display-only
transform like CRT aspect changes no readable state at all. Each test below
asserts on pixels for something no in-process test can observe.

## Tests

| test | what it proves that a unit test cannot |
|---|---|
| `grid.sh` | tiles render; a click opens the viewer; Escape returns to the same grid |
| `formats.sh` | six decoder families each paint a **distinct, non-blank** tile — the decode → texture → paint chain, per format |
| `viewer.sh` | the viewer really repaints on fit/zoom, and 1:1 after fit restores the **exact** pixels (integer device-pixel snapping) |
| `textmode.sh` | ANSI art renders; the navigator minimap paints; CRT aspect restretches the blit; the 9-dot VGA cell re-decodes wider |
| `code_view.sh` | a CP437 `.bas` rasterises as art **and** opens as text, and the two readings differ — guards three paint-time bugs that shipped |
| `table.sh` | the hand-rolled table paints rows with thumbnails, and toggling back restores the grid |
| `chrome.sh` | docks resize the central panel; F11 immersive hides and restores the chrome |
| `rating.sh` | a star rating paints in the caption, on the **hovered** tile rather than the first one |

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

**The XDG dirs are not the only place this app writes.** A star rating on an
on-disk file is stored as a `user.baloo.rating` **xattr on that file** (the
KDE/Baloo scheme, so ratings interoperate with Gwenview). So `rating.sh` was
writing ratings onto the fixtures *in the repository*, where they survived every
sandbox wipe — later runs started from a pre-rated tile, and a stray keypress in
an early draft of `viewer.sh` (where `1`–`5` set ratings, not zoom) left a
permanent star on `01-red.png`. `adapter_ensure_config` therefore copies the
fixtures into the sandbox and the app is pointed at the **copy**, with
`--no-preserve=xattr` so a stale rating cannot resurrect itself. Isolating an
app's config dirs is not isolation if its state model includes the files it
browses.

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
- **Format plugins default OFF** (source code, PDF, audio, 3D, video), so the
  blessed `settings.json` turns the source-code one on for the `.bas` fixture.
  This used to need an F5 as well — the app scanned the launch folder before
  reading `settings.json`, so the plugin had no effect on the first listing.
  That was **fixed upstream** after this suite surfaced it; `formats.sh` now
  asserts the `.bas` tile paints on the first frame, and reverting the fix makes
  exactly that one assertion fail.

### Calibrating offscreen — `calibrate.sh`

Writing a region test means knowing where things are, and the obvious way to find
out takes over the developer's screen. `./calibrate.sh out.png ['xdotool cmd'…]`
launches the app inside its own Xvfb + openbox, optionally drives it, and writes
a PNG to look at. Coordinates in `mousemove` are window-relative, like a test's.

```sh
./calibrate.sh /tmp/x.png 'key F5' 'sleep 1' 'mousemove 290 290' 'click 1' 'sleep 1.5'
CAL_SETTINGS=/tmp/blessed.json ./calibrate.sh /tmp/x.png     # with a chosen app config
```

**`env -u WAYLAND_DISPLAY` is load-bearing, not hygiene.** kaleidotron is winit,
and winit prefers Wayland whenever `WAYLAND_DISPLAY` is set — it will ignore
`DISPLAY` entirely and open a real window on the developer's actual compositor,
while every xdotool search against the Xvfb display finds nothing and the script
reports "window never appeared". Both `calibrate.sh` and `adapter_launch` unset
it. The driver's offscreen wrapper does too; the adapter asserts it anyway,
because the failure mode is a window appearing on someone's screen mid-run.

### Two app behaviours that will bite a new test

**Text-mode art auto-plays.** An `.ans` opens in the baud-rate player (4800 by
default) and types itself out, auto-scrolling to follow the cursor. Any snap
taken during that races an animation. `Home` interrupts playback *and* scrolls to
the top, giving one settled frame — `textmode.sh` does this before its baseline.

**"CRT" in the status bar is a menu, not a toggle**, and clicking a switch inside
it *closes the popup*. So each toggle is open-then-click; adding a dismiss step
re-opens the menu and the next click closes it instead of toggling. `Escape` is
not a dismiss either — it leaves the **viewer**. Two separate versions of
`textmode.sh` failed on this, both with the tell-tale signature of two different
actions producing byte-identical results.

**Compare regions of the same size.** `compare` diffs only the overlap of two
differently-sized images, so a mismatched pair reports a small, meaningless count
and *passes*. The first version of `grid.sh`'s did-the-fixtures-load guard
compared a 190×190 region against a 120×100 one and passed against an empty
folder; it now pairs `tile1` with an equally-sized `emptyref` patch of
background. Prove a guard fails when it should — `mv fixtures /tmp/hold; mkdir
fixtures` and re-run — before trusting it.

## Fixtures

`fixtures/` holds one file per decoder family, chosen so each paints something
unmistakably different: flat-colour PNGs with distinct shapes, a transparent PNG
(which draws over the checkerboard backdrop), an animated GIF, an indexed PCX
(the hand-written palette-preserving decoder), CP437 ANSI art, and a `.bas` whose
comment banner is box-drawing. Regenerate the PNGs with:

```sh
magick -size 128x128 xc:'#cc2222' -fill white -draw 'circle 64,64 64,20'          01-red.png
magick -size 128x128 xc:'#22aa44' -fill black -draw 'rectangle 24,24 104,104'     02-green.png
magick -size 128x128 xc:'#2255cc' -fill white -draw 'polygon 64,16 112,112 16,112' 03-blue.png
magick -size 128x128 xc:'#ddbb22' -fill black -draw 'roundrectangle 16,40 112,88 12,12' 04-yellow.png
```
