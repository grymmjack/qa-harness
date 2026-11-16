#!/bin/bash
# distribute-horizontally.sh — the Distribute Horizontally button in the
# properties panel spaces three shapes with equal gaps, keeping the outer two in
# place. Boxes (with the 6px stroke) span x 217-283, 297-343 and 497-563, so the
# gaps become 84 and the middle shape moves from x=300 to x=370.

info "=== drawy: distribute three shapes horizontally ==="

region oldMiddle 299 240 3 20 "middle shape's left edge before (x=300)"
region newMiddle 369 240 3 20 "middle shape's left edge after (x=370)"
region left      219 240 3 20 "left shape stays at x=220"
region right     559 240 3 20 "right shape stays at x=560"

park_mouse
snap newMiddle newMiddle-before; BEFORE_NM="$SNAP_RESULT"

key r
drag 220 220 280 280
key r
drag 300 220 340 280
key r
drag 500 220 560 280
key s
key ctrl+a
wait_for 0.5 "all three selected"
park_mouse
snap oldMiddle oldMiddle-before; BEFORE_OM="$SNAP_RESULT"
snap left left-before;           BEFORE_L="$SNAP_RESULT"
snap right right-before;         BEFORE_R="$SNAP_RESULT"

# Alignment section, third row, first button
click 26 533
park_mouse
wait_for 0.5 "distributed"

snap newMiddle newMiddle-after
assert_regions_differ "$BEFORE_NM" "$SNAP_RESULT" "the middle shape should move to x=370"
snap oldMiddle oldMiddle-after
assert_regions_differ "$BEFORE_OM" "$SNAP_RESULT" "the middle shape should leave x=300"
snap left left-after
assert_regions_same "$BEFORE_L" "$SNAP_RESULT" "the left shape should not move" 0
snap right right-after
assert_regions_same "$BEFORE_R" "$SNAP_RESULT" "the right shape should not move" 0

key ctrl+z
wait_for 0.5 "undo"
snap oldMiddle oldMiddle-undone
assert_regions_same "$BEFORE_OM" "$SNAP_RESULT" "undo should put the middle shape back at x=300" 0
