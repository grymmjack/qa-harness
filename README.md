# qa-harness

A **visual, human-collaborative GUI test harness** you can point at any desktop
app — regardless of language or toolkit. It drives real mouse/keyboard input,
captures the screen, and asserts on **regions of pixels**, so a test proves the
app *looks* right, not just that a function returned. It grew out of a QB64
pixel-editor's QA script and was split along a **driver + adapter seam** so the
same core runs against a Rust GUI, a C app, a web page — anything you can point
at and screenshot.

> Status: **skeleton** (Phase 4). The portable pieces are being lifted out of the
> original `draw-qa.sh` into `core/`; `report/` is already here and app-agnostic.
> See `ARCHITECTURE.md` for the full seam map and the port checklist.

## Why it exists (the design goals)

- **Human sees what the harness sees.** Tests declare named **regions**
  (`region canvas 40 40 300 200`); `--calibrate` outlines every region on the
  live UI so a person can confirm placement *before* trusting a run, and a failed
  assertion auto-saves a `-where` frame with the region boxed in red.
- **Human-emulated input**: mouse move/click/drag, key chords, typing, scroll —
  through one driver so a test never hard-codes `xdotool`.
- **Runs anywhere on the spectrum**: one run, a subset (shell glob), or the whole
  suite; **offscreen by default** under Xvfb (a shared machine stays usable, and
  it's the CI path) or **onscreen** with a takeover warning + ETA + consent.
- **You always know where a run is**: per-test + session ETA in **clock time**, a
  queryable live-status file, and a machine-readable `PROGRESS` stream.
- **Results you can act on**: a rendered HTML report (header + test/result/secs/
  notes) and JUnit XML + non-zero exit for CI.

## The three layers (one narrow seam)

```
CORE     portable; knows nothing about the app or the OS
  runner · assert(region diff) · regions/mark · eta · status · report · consent
      │ needs 3 verbs from a DRIVER        │ needs a few facts from an ADAPTER
      ▼                                     ▼
DRIVER (per platform)                 ADAPTER (per app — tiny)
  input:  move/click/drag/key/type/scroll   launch/quit · window match
  capture: full-frame → PNG                  logical→screen geometry
  target:  find window · bounds · offscreen  blessed config · hooks(wait/alive)
  linux-x11 = xdotool + spectacle/scrot + Xvfb    draw / rust-gui / web = adapters
```

Tests speak **logical** coordinates; the adapter maps logical→screen. That single
seam is what lets one test file run against different apps. Full contract:
`ARCHITECTURE.md`.

## Layout

| Path | Role |
|------|------|
| `core/` | portable bash: runner, assertions, regions/marks, eta, status, report hook, CLI |
| `drivers/linux-x11/` | the only OS-specific bash: `xdotool` input, `spectacle`/`scrot` capture, `xwininfo` bounds, Xvfb offscreen |
| `report/qa-report.py` | project-agnostic HTML + JUnit report from a run's TSV (already portable) |
| `adapters/` | one tiny manifest per app; `adapters/draw/` is the reference adapter |
| `bin/qa` | entry point: load core + a driver + an adapter manifest, then run |
| `examples/` | sample tests that exercise the driver against a trivial app |

## Quickstart (once core is ported)

```bash
# run an app's suite offscreen, render a report + junit
bin/qa --adapter adapters/draw --offscreen
bin/qa --adapter adapters/draw tests/smoke.sh   # one test, onscreen (warns first)
bin/qa --adapter adapters/draw --status         # where is a running suite?
```

### Running suites in parallel

The core is concurrency-safe: `xvfb-run -a` auto-picks a free X display, and every
snapshot/FAIL frame is PID-scoped (`…_<PID>.png`), so files never collide. The
startup screenshot clean is also PID-scoped — it only removes frames whose run PID
is dead, so a newcomer can never wipe an in-flight run's frames.

For fully independent runs (separate results, logs, passed-cache, and per-app
sandbox in one move), give each its own results dir:

```bash
QA_RESULTS_DIR=/tmp/runA bin/qa --adapter adapters/draw     --offscreen &
QA_RESULTS_DIR=/tmp/runB bin/qa --adapter adapters/kaleidotron --offscreen &
```

One caveat is per-adapter, not core: an adapter that pins a fixed app-`HOME`/config
path must derive it from `QA_RESULTS_DIR` (as the kaleidotron adapter does) or two
runs of *that* app share one app sandbox.

## Adding an app (write an adapter)

Copy `adapters/adapter.template.sh`, fill in six things: how to **launch/quit**,
how to **match the window** (title / pid / geometry — a stable window id is *not*
required), the **logical→screen** mapping, any **blessed config**, lifecycle
**hooks** (`is_alive`, optional `wait`/`park_window`), and where the **tests**
live. That's the whole integration surface.
