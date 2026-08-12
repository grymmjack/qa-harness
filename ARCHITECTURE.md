# Architecture — the driver/adapter seam

The harness is **core + driver + adapter**. The core owns everything portable; a
**driver** supplies OS input/capture; an **adapter** supplies the few app facts.
Roughly **70% core / 15% driver / 15% adapter** by volume.

```
CORE  (portable; no app, no OS knowledge)
  runner · assert(region diff) · regions/mark · eta · status · report · consent · cli
        │ calls 3 driver capabilities         │ reads a few adapter facts
        ▼                                       ▼
DRIVER (per platform)                     ADAPTER (per app)
  input · capture · target                  identity · launch/quit · window match
  linux-x11 = xdotool+scrot/spectacle+Xvfb  logical→screen · blessed cfg · hooks
```

## The driver interface (what CORE calls)

```
# INPUT — screen coords already resolved by the adapter's logical→screen map
driver_input_move   SX SY
driver_input_button down|up|click  1|2|3
driver_input_key    <combo>          # ctrl+s — holds mods, taps base (SDL2-safe)
driver_input_type   <text>
driver_input_scroll up|down [ticks]

# CAPTURE
driver_capture_full <out.png>        # whole display; CORE crops regions itself

# TARGET / lifecycle
driver_window_bounds_by_title <s>    # → "X Y W H"  (title → pid → geometry degrade)
driver_offscreen_available           # 0/1  (Xvfb usable?)
driver_run_offscreen <cmd...>        # Xvfb @ res, WAYLAND_DISPLAY unset
```

**No stable window id is assumed** — some toolkits (QB64-PE today) never expose
one. Everything downstream works from a **rect** (`window_bounds`): capture crops
it, input targets logical coords mapped through it. Match by title, then pid, then
"the one fullscreen-ish window." An adapter may also `park_window` (a WM hotkey
that moves+resizes the active window to a fixed desktop rect) to make coords
deterministic with no id at all — which is also what enables resize tests.

**Capture backend depends on the display, not the machine** (learned the hard
way): a real **Wayland** session needs `spectacle` (scrot returns black); pure
**X11 / offscreen Xvfb** needs `scrot` (spectacle reaches the real desktop through
the xdg portal and grabs the wrong screen). Selector: `WAYLAND_DISPLAY set →
spectacle, else scrot`; override with `QA_CAPTURE=<tool>`.

## The logical-coordinate rule (the seam)

Tests pass **logical** coords to input and **logical rects** to `region`/`snap`.
The adapter's `adapter_to_screen` converts logical→screen (default: window-origin
+ 1:1; DRAW overrides with a viewport × DISPLAY_SCALE map). The core never
hard-codes a platform or an app coordinate — only the driver and adapter do. This
is what lets one test file run against different apps.

## Offscreen / CI

`driver_run_offscreen` wraps launch in `Xvfb -screen 0 <W>x<H>x24` with
`WAYLAND_DISPLAY` unset. Two invariants: (1) the Xvfb screen must match what the
app expects — an app that derives its size from the screen needs the right res
(`QA_XVFB_RES=WxH`); (2) `WAYLAND_DISPLAY` unset, or spectacle captures the real
desktop and every region diff compares a static wrong frame. The runner emits
`report.html` + `junit.xml` and exits non-zero on any failure — the CI signal.

## Port checklist — lifting CORE out of the original `draw-qa.sh`

The reference script `DRAW/QA/draw-qa.sh` is the source of truth for the port.
Classification (→ where each piece lands):

**→ core/** (portable, de-app'd)
- logging + tally: `log/info/dbg/pass/fail/warn/skip`, `PASS/FAIL/SKIP`
- region registry + marks: `region`, `snap`, `_calibrate_region`, `_emit_where_on_fail`
- assertions: `assert_regions_differ/same`, AE calibration `_calibrate_ae/_ae_number`
- capture orchestration: `snap_region` crop logic (pixels come from the driver)
- eta: `_record_duration/_eta_for/_fmt_secs`
- live status: `_write_status/_suffix_eta` + `--status`
- results + report hook: `_record_result` (→ run TSV) + invoking `report/qa-report.py`
- run isolation + cache + tally: `run_test_file`
- run modes / consent: `--mode`, Xvfb self-wrap, onscreen warning
- CLI: flag parse, `--list/--eta/--report/--status/--reset/--stop`, `--help`

**→ drivers/linux-x11/** (swap per platform)
- `_capture_client_area` (spectacle/scrot + convert crop)
- input verb bodies (`click/drag/key/type_text/scroll_*`) — xdotool
- `_update_win_pos` (xwininfo), `_detect_decoration_height`, offscreen launch

**→ adapters/draw/** (app-specific)
- `_qa_cfg_overrides/_ensure_qa_cfg` (blessed cfg), `_cfg` readers
- `draw_launch/draw_quit`, `WINDOW_TITLE`, `_verify_geometry_model`
- `_abs` + viewport/DISPLAY_SCALE geometry (the logical→screen override)
- `wake_draw` (pre-input jiggle), `canvas_focus`, crash-log dir

Order: (1) skeleton — **done**; (2) port core + linux-x11 driver, keeping the
input/capture *verb names* identical so tests don't change; (3) write
`adapters/draw` and re-run DRAW's suite through `bin/qa` to confirm parity;
(4) add `adapters/rust-gui` reusing the same driver — the proof the seam holds.

## Writing an adapter — completeness (the `_abs` lesson)

The failure that *will* bite you when abstracting or porting a harness:

> **An adapter must expose every app-specific name the TEST CORPUS references
> directly — not just the names the core calls.**

Tests don't only use the high-level verbs (`click`, `snap`, `assert_*`). For
multi-step gestures the core's verbs can't express — a middle-drag pan stepped by
hand, hold-a-key-then-drag, a key tap *mid-drag* — a test drops to **raw driver
calls with absolute coordinates**, and to get those coordinates it calls the app's
own **logical→screen helper by name**. In DRAW that helper is `_abs vx vy`.

When DRAW was ported, the core and every *high-level verb* resolved and smoke was
green — but `_abs`, which is used **inside tests** and never by the core, was not
re-exposed under that name (it existed only as `adapter_to_screen`). Result:
`$(_abs …)` printed nothing, `xdotool mousemove "" ""` was a silent no-op, and all
6 `_abs`-using tests failed with **"regions are identical (action had no
effect?)"** — the symptom that reads like an app bug but is a missing binding. It
was invisible until the **full** suite ran: 92/103 passed and the 10 failures
clustered on exactly the tests using helpers the adapter forgot to expose.

**Rule of the seam:** an adapter's surface =
`(what the core needs) ∪ (every symbol the tests reference)`.
Coordinate helpers, geometry vars, and app-named aliases (`_abs`, `draw_focus`,
`canvas_focus`, `wake_draw`, `WORK_LEFT`, `CANVAS_CX`, …) are part of the contract
**even though the core never touches them**. When you rename a helper in the
adapter (`_abs` → `adapter_to_screen`), keep the original name as a one-line alias
so tests keep resolving:

```bash
adapter_to_screen() { …; }
_abs() { adapter_to_screen "$@"; }   # tests call this name directly
```

**Audit a port before trusting it** — never assume "smoke passed" means "bound".
Diff the names the tests *use* against the names the loaded chain *defines*:

```bash
# 1. bare identifiers the tests call/read (function calls + $VARS)
grep -rhoE '[A-Za-z_][A-Za-z0-9_]*' adapters/<app>/tests/*.sh | sort -u > /tmp/used
# 2. what driver+adapter actually define, after sourcing them the way bin/qa does
source drivers/<drv>/driver.sh; source adapters/<app>/manifest.sh
{ declare -F | awk '{print $3}'; declare -p 2>/dev/null | sed -n 's/^declare [--][^ ]* \([A-Za-z_][A-Za-z0-9_]*\).*/\1/p'; } | sort -u > /tmp/defined
# 3. app-named symbols used but never defined (skip shell builtins/keywords by eye)
comm -23 /tmp/used /tmp/defined | grep -E '^(_abs|draw_|canvas_|wake_|LP_|CANVAS_|WORK_|VIEWPORT_)'
```

Anything the tests reference with an app-specific prefix that isn't defined is a
latent silent no-op. Fastest proactive check in practice: **run the full suite
once** and read the cluster — missing bindings surface as unrelated tests all
failing "action had no effect."

**Two more adapter non-negotiables, both learned the hard way:**
- **Config lock.** If the app persists its own config, the adapter must re-assert
  a *blessed* config on **every** test launch (not cache-and-skip) — the app's
  `CONFIG_save` otherwise bleeds one test's UI state (a moved toolbar, a flipped
  dock edge) into the next and coordinate tests drift. DRAW's
  `adapter_ensure_config` rewrites the pinned `DRAW.qa.cfg` before each launch.
- **Idle / focus quirks.** An app that drops input while idle needs an
  `adapter_pre_input` wake; a WM-less Xvfb sets no input focus, so the adapter must
  focus the window (`windowfocus --sync`) before input — SDL2 apps self-focus,
  plain X11/minifb windows do not.
