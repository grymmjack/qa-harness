#!/bin/bash
# snap-selection-to-grid.sh — shapes drawn off the grid (snapping off) are
# moved onto it by the Snap Selection to Grid button: each shape's top left
# outline corner goes to the nearest grid point. x=213 → 220, x=507 → 500.

info "=== drawy: snap selected shapes to the grid ==="

region aRaw     212 240 3 20 "shape A's raw left edge (x=213)"
region aSnapped 220 240 2 20 "shape A's snapped left edge (x=220)"
region cRaw     507 240 2 20 "shape C's raw left edge (x=507)"
region cSnapped 498 240 3 20 "shape C's snapped left edge (x=500)"

park_mouse
snap aSnapped aSnapped-before; BEFORE_AS="$SNAP_RESULT"
snap cSnapped cSnapped-before; BEFORE_CS="$SNAP_RESULT"

key r
drag 213 217 273 277
key r
drag 303 223 343 277
key r
drag 507 217 567 277
key s
key ctrl+a
wait_for 0.5 "all three selected"
park_mouse
snap aRaw aRaw-before; BEFORE_AR="$SNAP_RESULT"
snap cRaw cRaw-before; BEFORE_CR="$SNAP_RESULT"

# Alignment section, third row, third button
click 86 533
park_mouse
wait_for 0.5 "snapped"

snap aSnapped aSnapped-after
assert_regions_differ "$BEFORE_AS" "$SNAP_RESULT" "shape A should move onto x=220"
snap aRaw aRaw-after
assert_regions_differ "$BEFORE_AR" "$SNAP_RESULT" "shape A should leave x=213"
snap cSnapped cSnapped-after
assert_regions_differ "$BEFORE_CS" "$SNAP_RESULT" "shape C should move onto x=500"
snap cRaw cRaw-after
assert_regions_differ "$BEFORE_CR" "$SNAP_RESULT" "shape C should leave x=507"
