#!/bin/bash
# grid.sh — kaleidotron's thumbnail grid opens a file in the viewer, and Escape
# comes back. The first test for adapter #3: proves launch + state isolation +
# the window-relative coordinate map + region diffing all hold against a third
# app, and that the fixtures render at all.
#
# Logical coords are window-relative (adapters/kaleidotron/manifest.sh), against
# the app's default 1100x760 window:
#
#   menu bar        y≈11
#   breadcrumbs     y≈33
#   thumbnail grid  first row y 55..210 — tile centres x = 130, 290, 450, 610
#   central viewer  the rest, down to the sort/status bars at y≈715
#
# Two things in this app move on their own and both are avoided rather than
# waited out:
#   * the metadata OSD fades in over the TOP of the viewer (y≈68..170) for a few
#     seconds after a file opens, so every region here sits well below it;
#   * a tile carries a git badge and a "viewed" check in its top-left/right
#     corner, so the grid region is only ever compared against a baseline taken
#     in the same run, never a stored golden.

info "=== kaleidotron: the grid opens a file and Escape returns ==="

# The area the opened image lands in: a 128x128 fixture is drawn 1:1 at the
# centre of the central panel (512..640 x 316..444). Sized a little larger so a
# small centring difference doesn't fall outside the region.
region viewer 480 290 190 190 "centre of the viewer, where an opened image lands"
# The first tile, thumbnail only — below the git badge, above the caption. Paired
# with a same-sized patch of empty background from the second grid row, which
# stays blank with only four fixtures.
region tile1    70  70 120 100 "the first thumbnail (01-red.png)"
region emptyref 70 420 120 100 "background below the grid — the same size as tile1"

# ── Baseline: the grid is up, the viewer area is empty background ────────────
snap viewer grid_mode
GRID_MODE="$SNAP_RESULT"

# The fixtures must actually have rendered. Without this every assertion below
# still "passes" against an app showing an empty folder — verified by pointing
# the adapter at an empty fixtures dir and watching this fail first.
#
# The two regions compared here are deliberately the SAME SIZE. `compare` diffs
# only the overlap of two differently-sized images, so a mismatched pair reports
# a small, meaningless count and passes — which is exactly how the first version
# of this guard let an empty folder through.
snap emptyref background
EMPTY="$SNAP_RESULT"
snap tile1 thumbnail
assert_regions_differ "$EMPTY" "$SNAP_RESULT" \
    "the first fixture thumbnail should be visible (identical to blank = fixtures did not load)"

# ── Open it: a plain click both selects and activates (app.rs `activate`) ────
click 130 122
wait_for 0.8 "01-red.png opens in the viewer"
snap viewer opened
assert_regions_differ "$GRID_MODE" "$SNAP_RESULT" \
    "clicking a tile should open the image in the viewer"
OPENED="$SNAP_RESULT"

# ── …and Escape comes back to the grid ──────────────────────────────────────
# The viewer region returns to empty background. The tile's own appearance HAS
# changed by now (it gained a viewed-check and a selection highlight), which is
# exactly why this compares the viewer region and not the grid.
key Escape
wait_for 0.8 "back to the thumbnail grid"
snap viewer back_in_grid
assert_regions_differ "$OPENED" "$SNAP_RESULT" \
    "Escape should leave the viewer"
assert_regions_same "$GRID_MODE" "$SNAP_RESULT" \
    "Escape should restore the grid view the file was opened from"

assert_window_exists
info "=== kaleidotron grid test done ==="
