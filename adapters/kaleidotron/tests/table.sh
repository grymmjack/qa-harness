#!/bin/bash
# table.sh — the Grid/Table toggle repaints as rows, with thumbnails in them.
#
# `sorted_filtered_view` is unit-tested, so the ORDER is covered. What isn't is
# that the table renderer draws anything: it's hand-rolled (no egui_extras),
# painting each cell and a zebra stripe by hand on the same virtualised
# ScrollArea the grid uses. A table that lays out but paints no thumbnails, or
# columns that overlap, are visible here and nowhere else.

info "=== kaleidotron: the table view paints rows ==="

park_mouse

region body 60 50 1000 300 "where the tiles are in grid mode, and rows in table mode"
# The first row's thumbnail cell — the table draws a small tile per row.
region row_thumb 62 90 44 40 "the thumbnail in the first table row"

snap body grid
GRID="$SNAP_RESULT"

key t
wait_for 1.0 "table view"
snap body table
assert_regions_differ "$GRID" "$SNAP_RESULT" "T should switch the grid to a table"

region blank_cell 62 620 44 40 "empty area, thumbnail-cell-sized"
snap blank_cell
BLANK="$SNAP_RESULT"
snap row_thumb
assert_regions_differ "$BLANK" "$SNAP_RESULT" \
    "each table row should still paint its thumbnail"

key t
wait_for 1.0 "back to grid"
snap body grid_again
assert_regions_same "$GRID" "$SNAP_RESULT" "T again should restore the grid exactly"

assert_window_exists
info "=== table test done ==="
