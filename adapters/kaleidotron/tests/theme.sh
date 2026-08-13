#!/bin/bash
# theme.sh — an imported VS Code theme recolours the app, and the scope is honoured.
#
# Theme parsing is unit tested (the JSON → Visuals mapping, the scope lookups).
# The part that is not is the whole point of a theme: that selecting one actually
# repaints the interface. And the scope setting is a claim that can ONLY be made
# about pixels — "Code only" means the syntax colours change while the chrome
# deliberately does not, which no readable state distinguishes from "the theme
# failed to apply".
#
# That distinction is not hypothetical: this app shipped with "Code only" styling
# the tokens but not the code pane's background or gutter, so a themed viewer sat
# next to its own correctly-themed thumbnail looking unthemed.
#
#   gear (27,735) → Preferences (110,629)          close × (789,41)
#   Theme combo (133,175) → Amber CRT (78,225)
#   Styles row y=256: Everything (116) · Code only (200) · App only (277)

info "=== kaleidotron: a theme recolours the chrome, and scope is honoured ==="

park_mouse
# The SORT BAR, not the menu bar. A theme's `colors` block drives accents, and
# the sort bar carries the selected-button highlight — so it moves a lot when a
# theme lands. Measured on the menu bar this assertion reported 119 pixels:
# technically a change, but smaller than the tolerance `assert_regions_same` uses
# to call two regions identical, which is no basis for a claim.
region chrome 60 714 430 26 "the sort bar, which carries the accent colour"

snap chrome untuned
DEFAULT="$SNAP_RESULT"

# ── Apply a theme with the default "Everything" scope ───────────────────────
click 27 735
wait_for 0.8 "gear menu"
click 110 629
wait_for 1.5 "Preferences open"
click 133 175
wait_for 1.0 "theme dropdown open"
kt_click_raw 78 225
wait_for 1.5 "Amber CRT applied"
click 789 41
wait_for 1.2 "Preferences closed"
park_mouse

snap chrome themed
assert_regions_differ "$DEFAULT" "$SNAP_RESULT" \
    "selecting a theme should recolour the chrome"

# ── …now scope it to Code only ─────────────────────────────────────────────
# The same theme stays selected; only what it is allowed to style changes. The
# chrome must fall back to the built-in look — that is the whole meaning of the
# setting, and nothing but the pixels says whether it was honoured.
click 27 735
wait_for 0.8 "gear menu"
click 110 629
wait_for 1.5 "Preferences open"
click 200 256
wait_for 1.5 "scope: Code only"
click 789 41
wait_for 1.2 "Preferences closed"
park_mouse

snap chrome code_only
assert_regions_same "$DEFAULT" "$SNAP_RESULT" \
    "with the scope set to Code only, the chrome should return to the built-in look"

assert_window_exists
info "=== theme test done ==="
