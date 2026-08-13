#!/bin/bash
# search.sh — the filename filter repaints the grid down to what matched.
#
# `sorted_filtered_view` is unit tested, so the FILTERING is covered. What is
# not is that typing into the search bar re-lays-out the grid: the bar appears,
# the tiles that no longer match stop being drawn, and clearing brings them
# back. That is a paint-and-layout claim about the real widget, and the vim-style
# `/` binding is only reachable through actual keystrokes.

info "=== kaleidotron: the / filter repaints the grid ==="

park_mouse
region row1  60 50 1000 165 "the whole first row of tiles"
region tile3 390 70  120 100 "03-blue.png — a tile that should NOT survive the filter"

snap row1  unfiltered
ROW1="$SNAP_RESULT"
snap tile3 present
TILE3="$SNAP_RESULT"

key slash
wait_for 0.6 "search bar open"
type_text "green"
wait_for 1.0 "filtered to matching filenames"

snap row1 filtered
assert_regions_differ "$ROW1" "$SNAP_RESULT" \
    "typing a filter should re-lay-out the grid"
snap tile3 gone
assert_regions_differ "$TILE3" "$SNAP_RESULT" \
    "a tile that does not match should stop being drawn"

# Escape closes the filter and everything comes back.
key Escape
wait_for 1.0 "filter cleared"
park_mouse
snap row1 restored
assert_regions_same "$ROW1" "$SNAP_RESULT" \
    "clearing the filter should restore the full grid exactly"

assert_window_exists
info "=== search test done ==="
