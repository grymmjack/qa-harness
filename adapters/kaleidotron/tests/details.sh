#!/bin/bash
# details.sh — the Details dock fills in from the tile under the cursor.
#
# Everything the dock shows is derived from data the app already tests: the
# metadata comes from the thumbnailer, the palette dots from `extract_palette`,
# the view counts from `viewdb`. What has no other test is the assembly — that
# HOVERING a tile pushes all of it into a painted panel, and that the panel is
# populated rather than showing its empty-state text.
#
# With the dock open the grid shifts right (dock x 52..350), so tiles start at
# x0 = 362: row-1 centres are 430, 590, 750, 910.

info "=== kaleidotron: the Details dock fills from the hovered tile ==="

park_mouse
click 27 172
wait_for 1.2 "details dock open"

region preview 130 110 190 190 "the dock's fit preview"
region meta     60 340 280 170 "the metadata grid"

# Nothing hovered: the dock shows only its "Hover an item to inspect it" line,
# so both regions are empty panel background.
snap preview empty
EMPTY_PREVIEW="$SNAP_RESULT"
snap meta empty_meta
EMPTY_META="$SNAP_RESULT"

kt_hover 430 122
wait_for 1.5 "hovering 01-red.png"

snap preview filled
assert_regions_differ "$EMPTY_PREVIEW" "$SNAP_RESULT" \
    "hovering a tile should draw its preview in the Details dock"
# …and the preview is the file, not a spinner or an empty frame.
kt_assert_dominant "$SNAP_RESULT" r "the preview should be 01-red.png's red"

snap meta filled_meta
assert_regions_differ "$EMPTY_META" "$SNAP_RESULT" \
    "…and fill in the metadata grid"

assert_window_exists
info "=== details test done ==="
