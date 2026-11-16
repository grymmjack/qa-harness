#!/bin/bash
# snap-off-draws-freely.sh — control for snap-draw-rectangle: with snapping off
# the same drag puts the edges at the raw cursor positions.

info "=== drawy: without snapping the rectangle follows the cursor ==="

region rawLeft     210 280 3 40 "raw left edge (x=213)"
region snappedLeft 220 280 2 40 "inside the would-be snapped edge only"

park_mouse
snap rawLeft rawLeft-before;     BEFORE_RL="$SNAP_RESULT"
snap snappedLeft snappedLeft-before; BEFORE_SL="$SNAP_RESULT"

key r
drag 213 217 391 383
park_mouse
wait_for 0.5 "rectangle committed"

snap rawLeft rawLeft-after
assert_regions_differ "$BEFORE_RL" "$SNAP_RESULT" "left edge should be at the raw x=213"
snap snappedLeft snappedLeft-after
assert_regions_same "$BEFORE_SL" "$SNAP_RESULT" "nothing should be drawn at x=220..221" 0
