#!/bin/bash
# snap-resize.sh — resizing from the bottom right handle with Snap to Grid on
# puts the dragged outline corner on the grid and keeps the opposite side fixed.
# Rectangle (220,220)-(400,380), stroke 6, so its handle sits at (406,386).
# Dragging that by (+33,+29) moves the outline corner to (433,409) raw, which
# snaps to (440,400).
# QA-DRAWYRC: Grid/SnapToGrid=true

info "=== drawy: resizing snaps the dragged corner to the grid ==="

region newRight 439 290 3 40 "snapped right edge (x=440)"
region rawRight 432 290 3 40 "raw right edge (x=433)"
region left     219 290 3 40 "fixed left edge (x=220)"
region leftOut  213 290 3 40 "just outside the fixed left edge"

park_mouse
snap newRight newRight-before; BEFORE_NR="$SNAP_RESULT"
snap rawRight rawRight-before; BEFORE_RR="$SNAP_RESULT"
snap left left-before;     BEFORE_L="$SNAP_RESULT"
snap leftOut leftOut-before;  BEFORE_LO="$SNAP_RESULT"

key r
drag 220 220 400 380
key s
wait_for 0.3 "selection tool"
click 220 300
wait_for 0.3 "rectangle selected"

drag 406 386 439 415
park_mouse
wait_for 0.5 "resize committed"
# deselect so the selection outline does not show up in the strips
click 900 600
park_mouse
wait_for 0.3 "deselected"

snap newRight newRight-after
assert_regions_differ "$BEFORE_NR" "$SNAP_RESULT" "the right edge should land on x=440"
snap rawRight rawRight-after
assert_regions_same "$BEFORE_RR" "$SNAP_RESULT" "the right edge should not be at the raw x=433" 0
snap left left-after
assert_regions_differ "$BEFORE_L" "$SNAP_RESULT" "the left edge should stay on x=220"
snap leftOut leftOut-after
assert_regions_same "$BEFORE_LO" "$SNAP_RESULT" "the left edge should not drift outwards" 0
