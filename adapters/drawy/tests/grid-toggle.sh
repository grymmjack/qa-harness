#!/bin/bash
# grid-toggle.sh — Ctrl+' (Show Grid) draws the grid on an empty canvas and
# hides it again.
# QA-DRAWYRC: Grid/ShowGrid=true

info "=== drawy: show grid toggles the grid ==="

# an empty stretch of canvas, clear of the floating toolbars
region canvas 600 300 200 200 "empty canvas"

snap canvas canvas-grid-on
GRID_ON="$SNAP_RESULT"

key ctrl+apostrophe
wait_for 0.5 "grid hidden"
snap canvas canvas-grid-off
assert_regions_differ "$GRID_ON" "$SNAP_RESULT" "Ctrl+' should hide the grid"

key ctrl+apostrophe
wait_for 0.5 "grid shown again"
snap canvas canvas-grid-on-again
assert_regions_same "$GRID_ON" "$SNAP_RESULT" "Ctrl+' again should restore the same grid" 0

assert_window_exists
