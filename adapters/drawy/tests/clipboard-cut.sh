#!/bin/bash
# clipboard-cut.sh — Ctrl+X removes the selection; Ctrl+V brings it back as a
# native object.

info "=== drawy: cut and paste ==="

region edge 219 300 3 40 "the rectangle's left edge"
region panel 10 255 180 240 "properties panel: stroke to opacity"
region corners 10 595 180 45 "properties panel: corner type"

park_mouse
snap edge edge-empty; EMPTY="$SNAP_RESULT"

key r
drag 220 220 400 380
key s
click 900 650
drag 190 190 430 410
wait_for 0.3 "selected"
park_mouse
snap panel panel-original; ORIGINAL="$SNAP_RESULT"
snap corners corners-original; ORIGINAL_CORNERS="$SNAP_RESULT"

key ctrl+x
wait_for 0.5 "cut"
snap edge edge-cut
assert_regions_same "$EMPTY" "$SNAP_RESULT" "cut should remove the rectangle" 0

hover 800 500
key ctrl+v
wait_for 0.5 "pasted"
park_mouse
snap panel panel-pasted
assert_regions_same "$ORIGINAL" "$SNAP_RESULT" "the cut rectangle should paste back as a rectangle" 0
snap corners corners-pasted
assert_regions_same "$ORIGINAL_CORNERS" "$SNAP_RESULT" "the pasted item should have a corner type, like a rectangle" 0
