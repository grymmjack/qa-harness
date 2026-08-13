#!/bin/bash
# selection.sh — selection and the viewed check are painted on the tile.
#
# `selection` is a PathBuf set and `viewdb` is a SQLite table; both are unit
# tested as data. Whether either reaches the tile is not: the highlight and the
# check badge are hand-painted, and kittest cannot see a custom-painted tile at
# all. A selection model that works perfectly and draws nothing would ship.

info "=== kaleidotron: selection highlight and viewed badge are painted ==="

park_mouse
# Whole tile cards, including the border and caption where the highlight shows.
region card1  62 55 137 155 "the 01-red.png tile card"
region card2 222 55 137 155 "the 02-green.png tile card"
# The top-right corner of tile 1's thumbnail, where the viewed check is drawn.
region badge 160 58 40 34 "the corner of tile 1 that carries the viewed check"

snap card1 unselected
CARD1="$SNAP_RESULT"
snap card2 unselected2
CARD2="$SNAP_RESULT"
snap badge unviewed
BADGE="$SNAP_RESULT"

# Open and come straight back: that marks the file viewed, which must paint a
# check on its tile.
click 130 122
wait_for 1.0 "01-red.png opens — and is marked viewed"
key Escape
wait_for 1.0 "back to the grid"
park_mouse

snap badge viewed
assert_regions_differ "$BADGE" "$SNAP_RESULT" \
    "opening a file should paint a viewed check on its tile"

# Opening also selected it, so its card must differ from the untouched one.
snap card1 selected
assert_regions_differ "$CARD1" "$SNAP_RESULT" \
    "the opened tile should be drawn as selected"
snap card2 still_unselected
assert_regions_same "$CARD2" "$SNAP_RESULT" \
    "…and its neighbour should be untouched"

assert_window_exists
info "=== selection test done ==="
