#!/bin/bash
# navigation.sh — entering and leaving a folder repaints the grid and the crumbs.
#
# `open_folder` is exercised constantly by the app's own tests as a model
# operation. What is not covered anywhere is that a navigation actually
# *redraws*: a new listing painted into the grid, and a breadcrumb bar rebuilt
# to match. Both are painted, so kittest cannot see either.
#
# Runs against `fixtures-nav`, a folder kept deliberately outside the browsed one
# — folders and archives sort FIRST, so putting them beside the images would
# shift every calibrated tile coordinate in the rest of the suite.
#   tile 1 = bundle.zip   tile 2 = sub/     (centres x 130 / 290, y 122)

info "=== kaleidotron: navigating repaints the grid and the breadcrumbs ==="

park_mouse
kt_goto "$_KT_NAV"

region grid   60 50 700 170 "the tiles"
region crumbs 110 24 700 20 "the breadcrumb bar"

snap grid   at_nav
NAV_GRID="$SNAP_RESULT"
snap crumbs at_nav_crumbs
NAV_CRUMBS="$SNAP_RESULT"

# Into the subfolder. Its two fixtures are different images, so the grid must
# repaint; the crumbs must gain a segment.
click 290 122
wait_for 1.5 "entered sub/"
park_mouse
snap grid   in_sub
assert_regions_differ "$NAV_GRID" "$SNAP_RESULT" \
    "entering a folder should repaint the grid with its contents"
snap crumbs in_sub_crumbs
assert_regions_differ "$NAV_CRUMBS" "$SNAP_RESULT" \
    "the breadcrumb bar should gain the folder just entered"

# …and Backspace goes back up, restoring exactly what was there.
key BackSpace
wait_for 1.5 "back up to fixtures-nav"
park_mouse
snap grid   back_at_nav
assert_regions_same "$NAV_GRID" "$SNAP_RESULT" \
    "Backspace should restore the parent listing exactly"
snap crumbs back_at_nav_crumbs
assert_regions_same "$NAV_CRUMBS" "$SNAP_RESULT" \
    "…and the breadcrumbs with it"

assert_window_exists
info "=== navigation test done ==="
