#!/bin/bash
# snap-ctrl-inverts.sh — holding Ctrl while drawing temporarily turns snapping
# off when it is on.
# QA-DRAWYRC: Grid/SnapToGrid=true

info "=== drawy: Ctrl inverts snapping while drawing ==="

region rawLeft     210 280 3 40 "raw left edge (x=213)"
region snappedLeft 220 280 2 40 "inside the would-be snapped edge only"

park_mouse
snap rawLeft rawLeft-before;     BEFORE_RL="$SNAP_RESULT"
snap snappedLeft snappedLeft-before; BEFORE_SL="$SNAP_RESULT"

key r
ctrl_drag 213 217 391 383
park_mouse
wait_for 0.5 "rectangle committed"

snap rawLeft rawLeft-after
assert_regions_differ "$BEFORE_RL" "$SNAP_RESULT" "with Ctrl held the left edge should be at the raw x=213"
snap snappedLeft snappedLeft-after
assert_regions_same "$BEFORE_SL" "$SNAP_RESULT" "with Ctrl held nothing should snap to x=220" 0
