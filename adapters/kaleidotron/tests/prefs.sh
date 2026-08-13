#!/bin/bash
# prefs.sh — Preferences opens, switches sections, and a setting takes visible effect.
#
# kittest can already open this dialog through AccessKit, so "does it open" is
# not the point. The part no in-process test reaches is the consequence: that a
# control in the dialog is wired to the thing it names and that the GRID
# re-lays-out when it changes. A setting that stores its value perfectly and
# never reaches the layout passes the whole in-process suite.
#
# Grid spacing is used because its effect is unambiguous — the tiles physically
# move — and because it needs no scrolling within the dialog.
#
# The dialog is reached from the gear at the foot of the activity rail, NOT
# Ctrl+comma (which is unbound here).

info "=== kaleidotron: a Preferences change repaints the grid ==="

park_mouse
region row1   60 50 1000 165 "the first row of tiles"
region dialog 20 20  790 490 "where the Preferences window opens"

snap row1 before
ROW_BEFORE="$SNAP_RESULT"
snap dialog no_dialog
NO_DIALOG="$SNAP_RESULT"

click 27 735
wait_for 0.8 "gear menu open"
click 110 629
wait_for 1.5 "Preferences open"

snap dialog opened
assert_regions_differ "$NO_DIALOG" "$SNAP_RESULT" "Preferences should open"
APPEARANCE="$SNAP_RESULT"

# The section strip across the top swaps the whole body.
click 156 97
wait_for 1.0 "Viewer section"
snap dialog viewer_section
assert_regions_differ "$APPEARANCE" "$SNAP_RESULT" \
    "switching section should replace the dialog body"

# Back to Appearance and push horizontal grid spacing well up. egui sliders jump
# to the clicked position, so this is a click rather than a drag.
click 78 97
wait_for 1.0 "Appearance section again"
click 200 469
wait_for 1.2 "grid spacing raised"

click 789 41
wait_for 1.2 "Preferences closed"
park_mouse

snap row1 after
assert_regions_differ "$ROW_BEFORE" "$SNAP_RESULT" \
    "raising grid spacing should re-lay-out the tiles"

assert_window_exists
info "=== prefs test done ==="
