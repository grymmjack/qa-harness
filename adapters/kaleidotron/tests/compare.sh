#!/bin/bash
# compare.sh — the side-by-side compare opens and paints its diff overlay.
#
# `compute_diff_mask` and the layered-PSD writer are unit tested as data. What is
# not covered is the mode itself: that picking a source and a diff from two
# different tiles enters `Mode::Compare`, that both panes draw, and that the
# overlay lands on the DIFF pane only. The overlay is a tint painted at draw time
# over one pane's image rect — there is no state to read back saying it appeared.
#
# Menu geometry (read off a calibration capture, relative to the right-click):
#   Compare              = click + (50, 74)
#   Set as source (left) = click + (212, 75)
#   Set as diff  (right) = click + (212, 98)

info "=== kaleidotron: Compare opens two panes and paints the diff overlay ==="

park_mouse
region whole 60 45 1030 660 "the central area"

snap whole grid_mode
GRID="$SNAP_RESULT"

# 01-red.png as the source…
right_click 130 122
wait_for 0.8 "context menu on 01-red.png"
click 180 196
wait_for 0.8 "Compare submenu"
click 342 197
wait_for 1.0 "set as compare source"

# …and 02-green.png as the diff. Setting BOTH is what enters the mode.
right_click 290 122
wait_for 0.8 "context menu on 02-green.png"
click 340 196
wait_for 0.8 "Compare submenu"
click 502 220
wait_for 2.0 "compare mode opens"
park_mouse

snap whole compare_mode
assert_regions_differ "$GRID" "$SNAP_RESULT" \
    "setting both source and diff should enter the compare view"

# Two panes, split down the middle with a gutter. The diff pane carries the
# overlay, so the halves must not look alike — if the overlay never painted, the
# two panes would be two ordinary images and this is the check that notices.
region left  100 120 380 380 "the SOURCE pane"
region right 640 120 380 380 "the DIFF pane, which carries the overlay"

snap left  source_pane
LEFT="$SNAP_RESULT"
region left_ref 100 120 380 380 "same rect, for a same-size comparison"
snap right diff_pane
assert_regions_differ "$LEFT" "$SNAP_RESULT" \
    "the diff pane should not look like the source pane (no overlay = identical treatment)"

# Escape returns to the browser.
key Escape
wait_for 1.5 "back to the grid"
park_mouse
snap whole back_to_grid
assert_regions_same "$GRID" "$SNAP_RESULT" \
    "Escape should restore the grid exactly"

assert_window_exists
info "=== compare test done ==="
