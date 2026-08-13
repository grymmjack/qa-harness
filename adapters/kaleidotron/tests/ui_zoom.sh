#!/bin/bash
# ui_zoom.sh — Ctrl +/- scales the whole GUI, not just the thumbnails.
#
# There are two independent zoom axes here and confusing them is easy: Ctrl+wheel
# resizes THUMBNAILS ONLY (thumbsize.sh), while Ctrl +/- scales the entire
# interface through egui's zoom_factor. In process both are floats and a
# regression that wired one to the other would pass every unit test; on screen
# they are unmistakably different, because only this one moves the CHROME.
#
# Asserting on the menu bar is what separates them: a thumbnail change can never
# alter it.

info "=== kaleidotron: Ctrl +/- scales the whole interface ==="

park_mouse
region menubar 0  0 300 24  "the menu bar — chrome, so thumbnail zoom cannot touch it"
region row1   60 50 800 165 "the first row of tiles"

snap menubar default
BAR="$SNAP_RESULT"
snap row1 default_row
ROW="$SNAP_RESULT"

key ctrl+plus
key ctrl+plus
wait_for 1.2 "UI scaled up"
park_mouse

snap menubar zoomed
assert_regions_differ "$BAR" "$SNAP_RESULT" \
    "Ctrl+plus should scale the chrome, which thumbnail zoom never touches"
snap row1 zoomed_row
assert_regions_differ "$ROW" "$SNAP_RESULT" \
    "…and the content with it"

key ctrl+minus
key ctrl+minus
wait_for 1.2 "back to 100%"
park_mouse

snap menubar restored
assert_regions_same "$BAR" "$SNAP_RESULT" \
    "Ctrl+minus should return the chrome to exactly its original scale"

assert_window_exists
info "=== ui_zoom test done ==="
