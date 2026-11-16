#!/bin/bash
# clipboard-native-paste.sh — copying a rectangle and pasting it gives a real
# rectangle (same properties panel as the original), not a picture of one.

info "=== drawy: paste creates native objects ==="

region panel 10 255 180 240 "properties panel: stroke to opacity"
region corners 10 595 180 45 "properties panel: corner type"

key r
drag 220 220 400 380
key s
click 900 650
drag 190 190 430 410
wait_for 0.3 "original selected"
park_mouse
snap panel panel-original; ORIGINAL="$SNAP_RESULT"
snap corners corners-original; ORIGINAL_CORNERS="$SNAP_RESULT"

key ctrl+c
wait_for 0.3 "copied"
info "clipboard offers: $(xclip -selection clipboard -t TARGETS -o 2>/dev/null | head -3 | tr '\n' ' ')"
hover 800 500
key ctrl+v
wait_for 0.5 "pasted"
park_mouse
snap panel panel-pasted
assert_regions_same "$ORIGINAL" "$SNAP_RESULT" "the pasted item should be a rectangle, with the rectangle's properties" 0
snap corners corners-pasted
assert_regions_same "$ORIGINAL_CORNERS" "$SNAP_RESULT" "the pasted item should have a corner type, like a rectangle" 0
