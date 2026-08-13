#!/bin/bash
# sort.sh — reversing the sort re-lays-out the grid.
#
# `sorted_filtered_view` is unit tested, so the ORDERING ITSELF is covered and
# this does not re-test it. The claim here is the part that is not: that the
# sortbar control is wired to it and that the grid REPAINTS in the new order.
# A sort that reorders `entries` and leaves the drawn tiles alone passes every
# in-process test.
#
# Reversing is used rather than changing the key because it is unambiguous: with
# names 01..16, ascending puts 01-red first and descending puts 16-xbin.xb there,
# so tile 1 must change identity — not merely "something moved".

info "=== kaleidotron: reversing the sort repaints the grid in the new order ==="

park_mouse
region tile1 70 70 120 100 "the first tile — 01-red.png ascending, 16-xbin.xb descending"
region row1  60 50 1000 165 "the whole first row"

snap tile1 ascending
ASC_TILE="$SNAP_RESULT"
snap row1 ascending_row
ASC_ROW="$SNAP_RESULT"
# 01-red.png leads while ascending, so tile 1 is red.
kt_assert_dominant "$ASC_TILE" r "ascending, the first tile should be 01-red.png"

# The Asc/Desc toggle sits in the sort bar.
click 368 727
wait_for 1.2 "sorted descending"
park_mouse

snap row1 descending_row
assert_regions_differ "$ASC_ROW" "$SNAP_RESULT" \
    "reversing the sort should re-lay-out the row"
snap tile1 descending
assert_regions_differ "$ASC_TILE" "$SNAP_RESULT" \
    "…and the first tile should now be a different file"
# Descending puts 16-xbin.xb first, which is a green band on black.
kt_assert_dominant "$SNAP_RESULT" g "descending, the first tile should be 16-xbin.xb (green)"

click 368 727
wait_for 1.2 "back to ascending"
park_mouse
snap row1 ascending_again
assert_regions_same "$ASC_ROW" "$SNAP_RESULT" \
    "reversing back should restore the original order exactly"

assert_window_exists
info "=== sort test done ==="
