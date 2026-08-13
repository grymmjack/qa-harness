#!/bin/bash
# stepping.sh — Left/Right walk through the folder without going back to the grid.
#
# `step_image` is model logic, but "the next image is now on screen" is not
# something an in-process test can see, and the binding is genuinely overloaded:
# in the viewer Left/Right step images, but in a PDF they turn pages and in a
# multi-sheet .xmind they change sheets. Only an end-to-end press proves which
# behaviour a plain image gets.
#
# Deliberately asserts on COLOUR, not just change: stepping to the wrong file
# (say, wrapping to the end) still "changes" the pixels.

# ⚠ Tests are SOURCED into the runner's shell, so a variable here can clobber one
# of its own. `GREEN=` in the first version of this file overwrote the runner's
# ANSI colour escape with a PNG path, and every log line after it printed that
# path instead of turning green. Prefix snapshot variables rather than naming
# them after colours.

info "=== kaleidotron: Left/Right step through images in the viewer ==="

park_mouse
region art 480 290 190 190 "the centre of the viewer"

# Open 02-green.png — the second tile, so there is a neighbour on each side.
click 290 122
wait_for 1.2 "02-green.png opens"
snap art green
kt_assert_dominant "$SNAP_RESULT" g "opened 02-green.png — green should lead"
GREEN_SNAP="$SNAP_RESULT"

key Right
wait_for 1.2 "stepped forward"
snap art blue
assert_regions_differ "$GREEN_SNAP" "$SNAP_RESULT" "Right should show a different image"
kt_assert_dominant "$SNAP_RESULT" b "stepping forward from 02-green lands on 03-blue.png"

key Left
wait_for 1.2 "stepped back"
snap art green_again
assert_regions_same "$GREEN_SNAP" "$SNAP_RESULT" \
    "Left should return to exactly the image stepped away from"

key Left
wait_for 1.2 "stepped back again"
snap art red
kt_assert_dominant "$SNAP_RESULT" r "stepping back again lands on 01-red.png"

assert_window_exists
info "=== stepping test done ==="
