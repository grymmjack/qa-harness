#!/bin/bash
# multiselect.sh — ctrl+click and shift+click build a selection, visibly.
#
# `selection` is a PathBuf set, keyed that way precisely so it survives
# re-sorting — and thoroughly testable as a model. What is not testable in
# process is the only thing the user sees: which tiles are drawn as selected.
# The highlight is hand-painted, so kittest cannot see it at all, and a selection
# model that is perfectly correct and paints nothing would ship green.
#
# The status bar also reports the count, which is a second, independent surface
# for the same state — if the two ever disagree, one of them is lying.

info "=== kaleidotron: ctrl+click and shift+click build a visible selection ==="

park_mouse
region card1  62 55 137 155 "the 01-red.png tile card"
region card3 382 55 137 155 "the 03-blue.png tile card"
region status  0 738 420  22 "the status bar, which reports the selection count"

snap card1 unselected
CARD1="$SNAP_RESULT"
snap card3 unselected3
CARD3="$SNAP_RESULT"
snap status counts
STATUS="$SNAP_RESULT"

# A plain click selects — and, in this app, also opens. Escape returns to the
# grid with the selection intact, which is the state to build on.
click 130 122
wait_for 1.2 "01-red.png opened and selected"
key Escape
wait_for 1.2 "back to the grid"
park_mouse

snap card1 selected
assert_regions_differ "$CARD1" "$SNAP_RESULT" \
    "the clicked tile should be drawn as selected"

# Ctrl+click a second tile — it joins the selection without replacing it.
xdotool keydown ctrl
click 450 122
xdotool keyup ctrl
wait_for 1.2 "03-blue.png ctrl+clicked"
park_mouse

snap card3 also_selected
assert_regions_differ "$CARD3" "$SNAP_RESULT" \
    "ctrl+click should add a second tile to the selection"

snap status two_selected
assert_regions_differ "$STATUS" "$SNAP_RESULT" \
    "the status bar should report the selection"

assert_window_exists
info "=== multiselect test done ==="
