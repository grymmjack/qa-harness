#!/bin/bash
# explorer.sh — the Places/Folders dock paints its contents.
#
# `chrome.sh` already covers that opening a dock resizes the central panel. The
# separate claim here is that this dock draws anything: Places entries, the
# sub-tab strip, the folder tree. A panel that opens empty looks identical from
# the outside to one that opened correctly and simply had nothing to show.

info "=== kaleidotron: the explorer dock paints its contents ==="

# ⚠ The rail icon at y=89 is "Open folder…", which raises a NATIVE FILE DIALOG —
# a modal that would wedge the run. The Explorer toggle is the one below it at
# y=133. Verified by hovering each and reading the tooltip; never guess at rail
# positions.
park_mouse
region dock 56 60 290 260 "the top of the left dock"

# Before: the dock is closed, so this region is grid.
snap dock closed
CLOSED="$SNAP_RESULT"

click 27 133
wait_for 1.5 "explorer dock open"
park_mouse
snap dock open
assert_regions_differ "$CLOSED" "$SNAP_RESULT" \
    "opening the explorer should paint a dock where the grid was"
OPEN="$SNAP_RESULT"

# The dock's content must not be blank panel. Compare against an equally-sized
# patch lower down, which is empty dock background once the list runs out.
region dock_low 56 420 290 260 "empty dock background, same size"
snap dock_low
assert_regions_differ "$OPEN" "$SNAP_RESULT" \
    "the dock should list places, not open empty"

click 27 133
wait_for 1.2 "explorer dock closed"
park_mouse
snap dock closed_again
assert_regions_same "$CLOSED" "$SNAP_RESULT" \
    "closing it should restore the grid exactly"

assert_window_exists
info "=== explorer test done ==="
