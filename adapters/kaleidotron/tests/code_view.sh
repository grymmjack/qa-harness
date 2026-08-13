#!/bin/bash
# code_view.sh — a CP437 source file renders as art AND opens as text.
#
# Guards a regression that shipped and three bugs behind it, none of which any
# unit test caught, because all three were paint-time:
#
#   * a custom code font panicked the app the instant a source file opened
#     (set_fonts only takes effect NEXT frame, so naming the family in the same
#     frame is a panic inside epaint);
#   * a .bas whose comment banner is CP437 box-drawing failed `read_to_string`
#     and silently fell through to the IMAGE viewer;
#   * and the rasterised tile drew that banner as `REM ????`, because
#     `from_utf8_lossy` made every byte U+FFFD and `to_cp437` had no box-drawing
#     entry.
#
# The unit tests now cover the CP437 round-trip as bytes. What they cannot cover
# is that the glyphs actually reach the screen in both surfaces.

info "=== kaleidotron: CP437 source renders as art and opens as text ==="

park_mouse

# 09-code.bas is row 2, position 3 → tile centre (450, 290).
region tile     390 238 120 100 "the 09-code.bas thumbnail"
region tile_ref 390 570 120 100 "empty background BELOW the last grid row. y=570, not 420: the folder grew to three rows and the old reference sat on a tile, tile-sized"
region page     100  80 800 200 "the top of whichever viewer opened"

snap tile_ref
BLANK="$SNAP_RESULT"
snap tile
assert_regions_differ "$BLANK" "$SNAP_RESULT" \
    "the .bas tile should be rasterised (blank = the source-code plugin is off)"

# Plain click → the text viewer (the default for source), NOT the image viewer.
click 450 290
wait_for 1.0 "09-code.bas opens"
snap page as_text
AS_TEXT="$SNAP_RESULT"
region page_ref 100 520 800 200 "empty area, page-sized"
snap page_ref
assert_regions_differ "$AS_TEXT" "$SNAP_RESULT" \
    "opening a .bas should draw something (a blank pane = the CP437 decode failed)"

key Escape
wait_for 0.8 "back to the grid"

# …and the right-click menu's "Preview (image)" gives the OTHER reading of the
# same file. The two must differ: identical would mean one of the menu entries
# is not doing what it says.
right_click 450 290
wait_for 0.5 "context menu open"
# The menu opens at the pointer; "Preview (image)" is its first entry.
click 470 314
wait_for 1.0 "opened as an image instead"
snap page as_image
assert_regions_differ "$AS_TEXT" "$SNAP_RESULT" \
    "Preview (image) and View (text) should render the same file differently"

assert_window_exists
info "=== code_view test done ==="
