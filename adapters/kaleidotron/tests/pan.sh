#!/bin/bash
# pan.sh — a too-large image can be dragged and scrolled around the viewport.
#
# Pan/scroll is pure view state feeding a blit offset: nothing in process
# observes where the image ended up on screen. The keyboard scrolling in
# particular has an app-specific rule that only pixels can check — a PageDown in
# text-mode art moves exactly 25 character rows (one old 80x25 DOS screen),
# not a viewport-proportional jump.
#
# Uses the .ans fixture because it is far taller than the viewport. It also
# auto-plays at 4800 baud on open, so the view must be settled with Home first
# (see textmode.sh) or every snap races the ANSImation.

info "=== kaleidotron: pan and scroll move the image ==="

park_mouse
click 290 290
wait_for 2.0 "08-art.ans opens and plays out"
key Home
wait_for 1.2 "playback interrupted, scrolled to the top"

region view 390 80 400 300 "the top-left of the art"

snap view at_top
TOP="$SNAP_RESULT"

# Keyboard scrolling first — deterministic, unlike a drag.
key Next          # PageDown
wait_for 1.0 "paged down"
snap view paged
assert_regions_differ "$TOP" "$SNAP_RESULT" \
    "PageDown should scroll the art"

key Home
wait_for 1.0 "back to the top"
snap view home_again
assert_regions_same "$TOP" "$SNAP_RESULT" \
    "Home should return to exactly the top"

key End
wait_for 1.0 "jumped to the end"
snap view at_end
assert_regions_differ "$TOP" "$SNAP_RESULT" \
    "End should scroll to the bottom of the art"

key Home
wait_for 1.0 "top again"

# …and a drag pans it. Direction matters: the view is at the TOP, so dragging
# DOWN asks to reveal content above the first line and is correctly clamped to
# no movement — which the first version of this test read as "drag is broken".
# Drag UP, which pulls later rows into view.
drag 600 480 600 300
wait_for 1.0 "dragged"
snap view dragged
assert_regions_differ "$TOP" "$SNAP_RESULT" \
    "dragging should pan the image"

assert_window_exists
info "=== pan test done ==="
