#!/bin/bash
# rating.sh — a star rating paints on the tile it was applied to.
#
# rating.rs is unit-tested for the xattr encoding, and ratings.rs for the
# sidecar. Neither says anything about the caption under the thumbnail, which is
# custom-painted — so a rating that is stored correctly and never drawn passes
# the whole in-process suite.
#
# Also covers the rule that the tile UNDER THE CURSOR wins when it isn't part of
# the selection: pressing 3 while pointing at a tile must rate that one.

info "=== kaleidotron: a rating paints on the hovered tile ==="

park_mouse
# The caption strip under the first two tiles, where stars are drawn.
region cap1  62 190 137 24 "the caption under 01-red.png"
region cap2 222 190 137 24 "the caption under 02-green.png"

snap cap1 unrated
CAP1_BEFORE="$SNAP_RESULT"
snap cap2 unrated2
CAP2_BEFORE="$SNAP_RESULT"

# Point at the SECOND tile and press 3 — no click, so nothing is selected and
# the hovered tile is the one that must take the rating.
kt_hover 290 122
wait_for 0.4 "hovering 02-green.png"
key 3
wait_for 0.8 "rating applied"

snap cap2 rated
assert_regions_differ "$CAP2_BEFORE" "$SNAP_RESULT" \
    "pressing 3 while hovering a tile should draw stars in its caption"
snap cap1 still_unrated
assert_regions_same "$CAP1_BEFORE" "$SNAP_RESULT" \
    "…and must NOT rate the tile that merely happened to be first"

assert_window_exists
info "=== rating test done ==="
