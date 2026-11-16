#!/bin/bash
# snap-move.sh — dragging a shape with Snap to Grid on lands its outline on the
# grid. Rectangle (220,220)-(400,380) dragged by (+47,+23) from inside: the raw top-left would
# be (267,243), snapped it is (260,240).
# QA-DRAWYRC: Grid/SnapToGrid=true

info "=== drawy: moving a shape snaps its outline to the grid ==="

region newLeft  259 300 3 40 "snapped left edge after the move (x=260)"
region rawLeft  266 300 3 40 "raw left edge after the move (x=267)"
region oldLeft  219 300 3 40 "left edge before the move (x=220)"
region newRight 439 300 3 40 "right edge after the move (x=440): a move, not a resize"
region oldRight 399 300 3 40 "right edge before the move (x=400)"

park_mouse
snap newLeft newLeft-before; BEFORE_NL="$SNAP_RESULT"
snap rawLeft rawLeft-before; BEFORE_RL="$SNAP_RESULT"
snap oldLeft oldLeft-before; BEFORE_OL="$SNAP_RESULT"
snap newRight newRight-before; BEFORE_NR="$SNAP_RESULT"
snap oldRight oldRight-before; BEFORE_OR="$SNAP_RESULT"

key r
drag 220 220 400 380
key s
wait_for 0.3 "selection tool"

# select it, then drag from inside the selection box: pressing on the stroke
# itself would grab a resize band of the selection
key ctrl+a
wait_for 0.3 "selected"
drag 310 300 357 323
park_mouse
wait_for 0.5 "move committed"

snap newLeft newLeft-after
assert_regions_differ "$BEFORE_NL" "$SNAP_RESULT" "the left edge should land on x=260"
snap rawLeft rawLeft-after
assert_regions_same "$BEFORE_RL" "$SNAP_RESULT" "the left edge should not stay at the raw x=267" 0
snap oldLeft oldLeft-after
assert_regions_same "$BEFORE_OL" "$SNAP_RESULT" "the old position should be empty" 0
snap newRight newRight-after
assert_regions_differ "$BEFORE_NR" "$SNAP_RESULT" "the right edge should move along to x=440"
snap oldRight oldRight-after
assert_regions_same "$BEFORE_OR" "$SNAP_RESULT" "the right edge should not stay at x=400" 0

# undo restores the original position
key ctrl+z
wait_for 0.5 "undo"
snap oldLeft oldLeft-undone
assert_regions_differ "$BEFORE_OL" "$SNAP_RESULT" "undo should put the shape back at x=220"
