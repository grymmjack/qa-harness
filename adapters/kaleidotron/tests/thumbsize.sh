#!/bin/bash
# thumbsize.sh — Ctrl+wheel resizes the tiles, and Reset puts them back.
#
# Two independent zoom axes exist in this app and they are easy to confuse:
# Ctrl+wheel changes the THUMBNAIL SIZE only, while Ctrl +/- scales the whole
# GUI. Nothing in process distinguishes them — both end up as a float — but on
# screen they are obviously different, and a regression that wires one to the
# other would pass every unit test.
#
# The wheel gesture matters too: egui pre-classifies Ctrl+wheel as a ZOOM event,
# so it never appears in scroll deltas. That is app-visible behaviour a mocked
# input could not reproduce.

info "=== kaleidotron: Ctrl+wheel resizes the thumbnails ==="

park_mouse
region row1  60 50 1000 200 "the first row of tiles"
region tile1 70 70 120 100  "the first thumbnail"

snap row1 default_size
DEFAULT_ROW="$SNAP_RESULT"

# Point at the grid, then Ctrl+wheel up a few notches.
kt_ctrl_wheel 400 300 up 4
wait_for 1.2 "tiles enlarged"
park_mouse

snap row1 enlarged
assert_regions_differ "$DEFAULT_ROW" "$SNAP_RESULT" \
    "Ctrl+wheel should resize the tiles and re-lay-out the row"

# View → Reset thumbnail size puts it back. Menu-item coordinates are read off a
# calibration capture, never guessed — the first version of this test clicked
# 77px too high and silently hit nothing.
click 90 11
wait_for 0.8 "View menu"
click 154 222
wait_for 1.2 "thumbnail size reset"
park_mouse

snap row1 reset
assert_regions_same "$DEFAULT_ROW" "$SNAP_RESULT" \
    "Reset thumbnail size should restore the default layout exactly"

assert_window_exists
info "=== thumbsize test done ==="
