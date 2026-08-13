#!/bin/bash
# history.sh — the mouse thumb buttons walk the folder history and repaint.
#
# `dir_history` is a Vec and a cursor — trivially model-testable, and equally
# invisible: what a test cannot otherwise check is that button 8 and button 9,
# which no core input verb even covers, are wired to it and that walking the
# history actually redraws the grid.

info "=== kaleidotron: mouse back/forward walk the folder history ==="

park_mouse
kt_goto "$_KT_NAV"
region grid 60 50 700 170 "the tiles"

snap grid at_nav
NAV="$SNAP_RESULT"

click 290 122
wait_for 1.5 "entered sub/"
park_mouse
snap grid in_sub
SUB="$SNAP_RESULT"
assert_regions_differ "$NAV" "$SUB" "sanity: entering the folder repainted"

kt_mouse_back
wait_for 1.5 "mouse-back to the parent"
park_mouse
snap grid after_back
assert_regions_same "$NAV" "$SNAP_RESULT" \
    "the back button should return to the previous folder"

kt_mouse_forward
wait_for 1.5 "mouse-forward again"
park_mouse
snap grid after_forward
assert_regions_same "$SUB" "$SNAP_RESULT" \
    "the forward button should go back into the folder just left"

assert_window_exists
info "=== history test done ==="
