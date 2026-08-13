#!/bin/bash
# viewer.sh — the single-image viewer actually re-paints when the view changes.
#
# Zoom, fit and pan are pure paint-time behaviour: the app's own tests can assert
# what `zoom` is set to, but nothing in-process proves the pixels on screen
# changed. kaleidotron's whole reason for existing is that those pixels are
# exact (nearest-neighbour upscale, area-average downscale, integer device-pixel
# snapping), so "did the image redraw differently" is the assertion that matters.

info "=== kaleidotron: the viewer repaints on zoom / fit ==="

park_mouse
# The centre of the viewport, where a 128x128 fixture lands 1:1.
region art 480 290 190 190 "centre of the viewer, where the open image is drawn"
# A ring outside the 1:1 image but inside the viewport — empty at 1:1, covered
# once the image is zoomed up. This is what distinguishes "zoomed" from "merely
# repainted": a change here means the drawn image genuinely got bigger.
region halo 300 180 120 120 "outside the 1:1 image — only covered when zoomed in"

snap art grid_mode
GRID="$SNAP_RESULT"

click 130 122
wait_for 0.8 "01-red.png opens"
snap art opened
assert_regions_differ "$GRID" "$SNAP_RESULT" "the image should be drawn in the viewer"
AT_1_1="$SNAP_RESULT"
snap halo halo_1_1
HALO_1_1="$SNAP_RESULT"

# Fit-to-window (F) scales the 128px fixture up to the viewport. Both the centre
# and the previously-empty halo must change — the centre alone could change for
# any repaint at all.
key f
wait_for 0.8 "fit to window"
snap art fitted
assert_regions_differ "$AT_1_1" "$SNAP_RESULT" "F should rescale the image"
snap halo halo_fit
assert_regions_differ "$HALO_1_1" "$SNAP_RESULT" \
    "fit should make the image cover area that was empty at 1:1"

# …and back to 1:1, via the status-bar button. NOT the "1" key: in the viewer the
# digits set a STAR RATING (the first version of this test pressed 1 and rated
# the image instead of zooming it, which of course changed nothing on screen).
# Pixel-identical to the original 1:1 draw is the real claim: the app snaps to
# integer device-pixel scales, so a round trip must land exactly where it started
# rather than a fraction off.
click 124 748
wait_for 0.8 "back to 1:1"
snap art back_to_1_1
assert_regions_same "$AT_1_1" "$SNAP_RESULT" \
    "1:1 after fit should restore the original pixels exactly"

assert_window_exists
info "=== viewer test done ==="
