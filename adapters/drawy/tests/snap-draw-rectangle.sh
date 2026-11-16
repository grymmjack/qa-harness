#!/bin/bash
# snap-draw-rectangle.sh — with Snap to Grid on, a rectangle dragged from
# (213,217) to (391,383) is drawn from (220,220) to (400,380) on a 20px grid.
# QA-DRAWYRC: Grid/SnapToGrid=true

info "=== drawy: rectangle corners snap to the grid ==="

region snappedLeft    219 280 3 40 "where the snapped left edge (x=220) lands"
region rawLeft        210 280 3 40 "where an unsnapped left edge (x=213) would be"
region snappedBottom  300 379 40 3 "where the snapped bottom edge (y=380) lands"
region rawBottom      300 385 40 2 "where an unsnapped bottom edge (y=383) would reach"

park_mouse
snap snappedLeft snappedLeft-before;   BEFORE_SL="$SNAP_RESULT"
snap rawLeft rawLeft-before;       BEFORE_RL="$SNAP_RESULT"
snap snappedBottom snappedBottom-before; BEFORE_SB="$SNAP_RESULT"
snap rawBottom rawBottom-before;     BEFORE_RB="$SNAP_RESULT"

key r
drag 213 217 391 383
park_mouse
wait_for 0.5 "rectangle committed"

snap snappedLeft snappedLeft-after
assert_regions_differ "$BEFORE_SL" "$SNAP_RESULT" "left edge should be on the x=220 grid line"
snap rawLeft rawLeft-after
assert_regions_same "$BEFORE_RL" "$SNAP_RESULT" "nothing should be drawn at the raw x=213 position" 0
snap snappedBottom snappedBottom-after
assert_regions_differ "$BEFORE_SB" "$SNAP_RESULT" "bottom edge should be on the y=380 grid line"
snap rawBottom rawBottom-after
assert_regions_same "$BEFORE_RB" "$SNAP_RESULT" "nothing should be drawn at the raw y=383 position" 0
