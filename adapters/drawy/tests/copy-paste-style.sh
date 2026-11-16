#!/bin/bash
# copy-paste-style.sh — Copy Style (Ctrl+Shift+C) on a red rectangle and Paste
# Style (Ctrl+Shift+V) on a black one makes it red; undo makes it black again.

info "=== drawy: copy and paste style ==="

region edgeA 219 300 3 40 "rectangle A's left edge (x=220)"
region edgeB 519 300 3 40 "rectangle B's left edge (x=520)"

key r
drag 220 220 400 380
key r
drag 520 220 700 380
key s
park_mouse
snap edgeA edgeA-black; A_BLACK="$SNAP_RESULT"

# make B red with the second stroke colour swatch
click 900 650
drag 490 190 730 410
wait_for 0.3 "B selected"
click 50 292
wait_for 0.3 "B red"
park_mouse
snap edgeB edgeB-red; B_RED="$SNAP_RESULT"
assert_regions_differ "$A_BLACK" "$B_RED" "B should now be a different colour from A"

key ctrl+shift+c
click 900 650
drag 190 190 430 410
wait_for 0.3 "A selected"
key ctrl+shift+v
wait_for 0.5 "style pasted"
park_mouse
snap edgeA edgeA-pasted
assert_regions_same "$B_RED" "$SNAP_RESULT" "A should take B's style" 0

key ctrl+z
wait_for 0.5 "undo"
park_mouse
snap edgeA edgeA-undone
assert_regions_same "$A_BLACK" "$SNAP_RESULT" "undo should give A its own style back" 0
