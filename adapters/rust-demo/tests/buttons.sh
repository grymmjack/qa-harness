#!/bin/bash
# buttons.sh — clicking a color button fills the demo's canvas with that color.
# Proves the linux-x11 driver's click + the core's region-diff assertions work
# against a second app with a plain window-relative coordinate map (no viewport).
#
# Logical coords are window-relative (see adapters/rust-demo/manifest.sh):
#   buttons row y≈40 — RED cx=80, GREEN cx=240, BLUE cx=400
#   canvas fills the area below; sample an interior rect clear of the borders.

info "=== rust-demo: buttons fill the canvas ==="

region canvas 40 120 200 80 "the demo's fill canvas"

# Baseline (canvas starts on its dark clear color).
snap canvas blank
BLANK="$SNAP_RESULT"

# Click RED → canvas should change.
click 80 40
wait_for 0.3 "canvas filled red"
snap canvas red
assert_regions_differ "$BLANK" "$SNAP_RESULT" "clicking RED should fill the canvas"
RED_SNAP="$SNAP_RESULT"

# Click GREEN → canvas should change again (red → green).
click 240 40
wait_for 0.3 "canvas filled green"
snap canvas green
assert_regions_differ "$RED_SNAP" "$SNAP_RESULT" "clicking GREEN should change the canvas from red"

assert_window_exists
info "=== rust-demo buttons test done ==="
