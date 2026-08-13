#!/bin/bash
# anim.sh — hovering an animated GIF plays it, in the grid.
#
# Unfakeable by any in-process test: the claim is that the SAME tile, untouched,
# shows different pixels a moment later purely because the pointer is resting on
# it. Frame decoding is unit-tested; hover-to-play is a paint-loop behaviour with
# no other observer.
#
# ── Why this samples a sequence instead of taking two snaps ─────────────────
# The first version hovered, snapped, waited a fixed 0.35s and snapped again —
# and failed, not because the animation was broken but because both samples
# landed on the SAME frame. With a two-frame loop the phase is arbitrary (the
# app starts playing whenever the hover registers) and a snap costs an unknown
# tens of milliseconds, so no single fixed offset is safe: the pair is only
# guaranteed to differ at an offset of exactly one frame duration, which is
# precisely what the jitter destroys.
#
# So: sample across MORE than one frame duration at a fine interval. Crossing a
# frame boundary is then certain regardless of phase, and the test asserts on
# the first sample that actually differs. Comparing pairs quietly to pick which
# one to assert on is control flow, not the claim — the claim still goes through
# `assert_regions_differ` so a real failure reports the usual way.

info "=== kaleidotron: hovering a GIF tile animates it ==="

park_mouse
region tile 870 70 120 100 "the 06-anim.gif thumbnail"

# The fixture is two frames of 0.5s. Not hovered, it must be a still first frame:
# if it animates unprompted, the assertion below would pass for the wrong reason.
snap tile still_a
STILL="$SNAP_RESULT"
wait_for 0.8 "still, unhovered"
snap tile still_b
assert_regions_same "$STILL" "$SNAP_RESULT" \
    "an unhovered GIF tile should not animate on its own"

kt_hover 930 122
wait_for 0.4 "hover — playback starts"
snap tile playing_0
FIRST="$SNAP_RESULT"

# 5 samples at 0.3s spans 1.2s — more than one 0.5s frame, so a boundary is
# crossed whatever the phase. `compare` is used quietly here only to choose the
# sample to assert on; if none differ, the last one is used and the assertion
# fails with the normal message.
CHANGED=""
for i in 1 2 3 4 5; do
    wait_for 0.3 "sample $i"
    snap tile "playing_$i"
    if [[ -z "$CHANGED" ]] && ! magick compare -metric AE "$FIRST" "$SNAP_RESULT" null: 2>&1 | grep -q '^0 '; then
        CHANGED="$SNAP_RESULT"
        dbg "frame changed by sample $i"
    fi
done
assert_regions_differ "$FIRST" "${CHANGED:-$SNAP_RESULT}" \
    "a hovered GIF tile should advance frames"

assert_window_exists
info "=== anim test done ==="
