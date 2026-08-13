#!/bin/bash
# chrome.sh — the docks and immersive mode actually change the layout.
#
# Panel visibility IS reachable from kittest (it drives menus through
# AccessKit), but what kittest cannot see is the consequence: whether the
# central panel repainted at a different size. A dock that toggles its bool and
# paints nothing passes every in-process test.

info "=== kaleidotron: docks and immersive mode repaint the layout ==="

park_mouse
# A strip of the grid that a left dock would push sideways. If the docks open
# and the grid does not move, the layout did not actually change.
region grid_strip 60 55 400 160 "the left end of the thumbnail row"
# The menu bar — present normally, gone in immersive mode.
region menubar    0   0 300  22 "the menu bar"

snap grid_strip docked_closed
CLOSED="$SNAP_RESULT"

# The activity rail down the left edge toggles the docks (x≈27).
click 27 172        # Details
wait_for 0.8 "details dock open"
snap grid_strip details_open
assert_regions_differ "$CLOSED" "$SNAP_RESULT" \
    "opening the Details dock should push the grid over"
OPEN="$SNAP_RESULT"

click 27 172        # …and closed again
wait_for 0.8 "details dock closed"
snap grid_strip details_closed
assert_regions_same "$CLOSED" "$SNAP_RESULT" \
    "closing the dock should restore the previous layout exactly"

# F11 — immersive: every panel hidden, decorations off, only the art left.
snap menubar shown
BAR="$SNAP_RESULT"
key F11
wait_for 1.2 "immersive mode"
snap menubar hidden
assert_regions_differ "$BAR" "$SNAP_RESULT" \
    "F11 should hide the menu bar"

key F11
wait_for 1.2 "back to windowed"
snap menubar shown_again
assert_regions_same "$BAR" "$SNAP_RESULT" \
    "leaving immersive mode should restore the chrome"

assert_window_exists
info "=== chrome test done ==="
