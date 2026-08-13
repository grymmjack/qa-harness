#!/bin/bash
# immersive_reveal.sh — in immersive mode the bars come back on approach.
#
# `chrome.sh` covers that F11 hides the chrome. This covers the subtler half that
# makes the mode usable: with everything hidden, moving the pointer within ~48px
# of a window edge reveals THAT bar, and moving away hides it again. It is
# computed from pointer distance every frame and produces no state anything else
# can read — it exists only as pixels.

info "=== kaleidotron: immersive mode reveals a bar on approach ==="

park_mouse
region menubar 0 0 300 24 "the menu bar"

snap menubar windowed
WINDOWED="$SNAP_RESULT"

key F11
wait_for 1.5 "immersive"
# Park the pointer mid-window, far from every edge, so nothing is revealed.
kt_hover 550 400
wait_for 1.0 "pointer away from the edges"
snap menubar hidden
assert_regions_differ "$WINDOWED" "$SNAP_RESULT" \
    "F11 should hide the menu bar"
HIDDEN="$SNAP_RESULT"

# Approach the top edge — the menu bar should reveal itself.
kt_hover 550 4
wait_for 1.2 "pointer at the top edge"
snap menubar revealed
assert_regions_differ "$HIDDEN" "$SNAP_RESULT" \
    "moving to the top edge should reveal the menu bar"

# …and retreating hides it again.
kt_hover 550 400
wait_for 1.2 "pointer back to the middle"
snap menubar hidden_again
assert_regions_same "$HIDDEN" "$SNAP_RESULT" \
    "moving away should hide it again"

key F11
wait_for 1.5 "back to windowed"
assert_window_exists
info "=== immersive_reveal test done ==="
