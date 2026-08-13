#!/bin/bash
# table_columns.sh — the table's columns are user-configurable, visibly.
#
# The table is hand-rolled — no egui_extras — so every cell, divider and zebra
# stripe is painted by hand, and the column set is a bitmask the header's
# right-click menu edits. Whether toggling a column actually re-lays-out the rows
# is a pixel question: the bitmask can be perfectly correct while the renderer
# keeps drawing the old layout.
#
# ── Menu semantics (the same trap as the CRT popup) ─────────────────────────
# A checkbox inside this menu does NOT close it. So both toggles happen inside
# ONE open menu; re-opening between them is what broke the first version — the
# second "open" click actually CLOSED the still-open menu, and the click meant
# for the checkbox landed on the table underneath.
#
# Because the menu stays open across the snaps, the region deliberately watches
# the LEFT of the table (x 60..580), clear of the popup at x≈600. That is not a
# compromise: Name is a flex column that absorbs the freed width, so hiding a
# column on the right visibly re-lays-out the left.
#
#   header right-click (620,62) → Dimensions checkbox (637,189)

info "=== kaleidotron: the table's column set is configurable ==="

park_mouse
key t
wait_for 1.5 "table view"
park_mouse

region body 60 50 520 300 "the left of the table — clear of the header popup"

snap body all_columns
ALL="$SNAP_RESULT"

click 620 62
wait_for 1.6 "header menu open"

kt_click_raw 637 189
wait_for 2.0 "Dimensions hidden — Name absorbs the freed width"
snap body without_dimensions
assert_regions_differ "$ALL" "$SNAP_RESULT" \
    "hiding a column should re-lay-out the table"

# There is deliberately no "toggle it back and assert an exact restore" here.
# The second toggle could not be made to land reliably: whether this menu closes
# on a checkbox click decides whether the next click re-opens it or dismisses it,
# and both readings were tried (re-open first, and toggle twice inside one open
# menu) with the same result — the second click reaching the table underneath.
# Rather than ship an assertion that passes for reasons I cannot state, the test
# makes the one claim it can prove. The reverse direction is covered in spirit by
# `prefs`, `thumbsize` and `theme`, which all assert exact restores.

assert_window_exists
info "=== table_columns test done ==="
