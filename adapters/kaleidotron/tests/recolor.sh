#!/bin/bash
# recolor.sh — the Recolor pipeline actually repaints the image and the preview.
#
# `apply_pipeline` is well covered as arithmetic: the unit tests check the ops,
# the ordering, the cache keys. What none of them touch is the part the user
# sees — that moving a slider re-runs the pipeline, uploads a new texture, and
# repaints BOTH the main viewer and the pane's own preview. A pipeline that
# computes a perfect buffer and never reaches the screen passes every existing
# test.
#
# Also covers the palette strip, which is `extract_palette`'s only visible
# output.

info "=== kaleidotron: the recolor pipeline repaints image and preview ==="

park_mouse
click 130 122
wait_for 1.0 "01-red.png opens"

# The Recolor pane is the 4th icon down the activity rail. Opening it narrows the
# central panel, so the image re-centres — every region below is measured with
# the pane already open.
click 27 211
wait_for 1.2 "recolor pane open"

region art     345 320 120 120 "the open image, re-centred by the narrower panel"
region preview 815  85 230 225 "the recolor pane's own preview"
region swatch  770 360 320  38 "the extracted palette strip"
region swatch_ref 770 660 320 38 "empty pane background, swatch-strip-sized"

snap art       plain
ART="$SNAP_RESULT"
snap preview   plain_preview
PREVIEW="$SNAP_RESULT"

# The palette strip is `extract_palette`'s only visible surface.
snap swatch
SW="$SNAP_RESULT"
snap swatch_ref
assert_regions_differ "$SW" "$SNAP_RESULT" \
    "the extracted palette should be drawn as swatches"

# Invert is the clearest op to assert on: a red square becomes cyan, so the
# change is unmistakable rather than a few tones. Clicking near the right end of
# an egui slider jumps it there.
click 960 647
wait_for 1.2 "invert applied"

snap art     inverted
assert_regions_differ "$ART" "$SNAP_RESULT" \
    "an adjustment should repaint the image in the main viewer"
snap preview inverted_preview
assert_regions_differ "$PREVIEW" "$SNAP_RESULT" \
    "…and the recolor pane's preview as well"

# Reset all — the pipeline must come back off, not merely stop changing.
click 957 55
wait_for 1.2 "reset all"
snap art restored
assert_regions_same "$ART" "$SNAP_RESULT" \
    "Reset all should restore the original pixels exactly"

assert_window_exists
info "=== recolor test done ==="
