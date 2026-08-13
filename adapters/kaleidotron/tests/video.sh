#!/bin/bash
# video.sh — a video opens in the in-app player and seeking changes the frame.
#
# The player is a fusion of three subsystems — an ffmpeg raw-frame pipe with a
# bounded channel, a rodio soundtrack, and an A/V sync clock — and none of it is
# observable in process: the clock is a float and the "current frame" is a buffer
# that only exists to be blitted. Whether the picture on screen actually followed
# the transport is a pixel question.
#
# Runs offscreen with no sound device, which is fine: the video path is separate
# from playback, and a missing device degrades rather than fails.
#
# The fixture is built frame by frame (a yellow bar tracking across blue) rather
# than with an ffmpeg filter expression — a `drawbox` whose x depended on `t`
# silently produced a STATIC clip, so "the frame advanced" could never have been
# true and the test would have been asserting nothing.
#
# Transport (window coords): the seek bar spans the width at y≈107.

info "=== kaleidotron: the video player shows frames and seeks ==="

park_mouse
kt_goto "$_KT_PLUGINS"
wait_for 3.0 "the heavy decoders finish"

click 290 122
wait_for 4.0 "02-clip.mp4 opens and plays through"

region frame 380 250 340 260 "the video frame in the viewport"
region ref   380 560 340 100 "empty viewport below the frame"

snap ref
BLANK="$SNAP_RESULT"
snap frame shown
SHOWN="$SNAP_RESULT"
assert_regions_differ "$BLANK" "$SHOWN" \
    "the player should be showing a decoded frame"
kt_assert_dominant "$SHOWN" b "the clip is blue with a yellow bar — a placeholder is not"

# Seek near the start, then near the end. The bar tracks across the frame, so the
# two positions must look different — that is the whole claim.
click 150 107
wait_for 2.0 "seeked near the start"
snap frame early
EARLY="$SNAP_RESULT"

click 900 107
wait_for 2.0 "seeked near the end"
snap frame late
assert_regions_differ "$EARLY" "$SNAP_RESULT" \
    "seeking to a different position should show a different frame"

assert_window_exists
info "=== video test done ==="
