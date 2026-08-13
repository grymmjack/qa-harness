#!/bin/bash
# text_edit.sh — the code viewer's toolbar does what it says.
#
# The encoding half is the interesting one. DOS-era source is CP437, not UTF-8,
# and kaleidotron auto-detects that and offers a code-page combo to override it.
# The round trip is unit tested as BYTES; what is not covered is that switching
# the combo re-decodes the buffer already on screen and that the glyphs visibly
# change. Reading the same bytes as Latin-1 turns box-drawing characters into
# accented letters — a difference only pixels can report.
#
# Toolbar (window coords, calibrated):
#   ‹ Grid (80,61)  ✎ Edit (280,61)  🔍 Find (420,61)  Wrap (460,61)
#   code page combo (610,61) → UTF-8 (600,86) · CP437 (600,108) · Latin-1 (600,128)
#
# Order matters: Find opens a bar that pushes the text down, so it goes last.

info "=== kaleidotron: Find, Wrap and the code-page combo ==="

park_mouse
# 09-code.bas is row 2, position 3 — the CP437 fixture with a box-drawing banner.
click 450 290
wait_for 1.5 "09-code.bas opens in the text viewer"

region text   100 85 760 200 "the top of the document"
region gutter  60 85  38 200 "the line-number gutter, which Wrap removes"

snap text as_cp437
CP437="$SNAP_RESULT"

# ── Re-read the same bytes as Latin-1 ───────────────────────────────────────
click 610 61
wait_for 0.8 "code-page combo open"
click 600 128
wait_for 1.5 "re-decoded as Latin-1"
snap text as_latin1
assert_regions_differ "$CP437" "$SNAP_RESULT" \
    "reading the same bytes as Latin-1 should change the glyphs on screen"

# …and back. An exact restore is the strong form: the switch re-decodes from the
# retained bytes rather than from something lossy.
click 610 61
wait_for 0.8 "combo open again"
click 600 108
wait_for 1.5 "back to CP437"
snap text back_to_cp437
assert_regions_same "$CP437" "$SNAP_RESULT" \
    "switching back to CP437 should restore the original decode exactly"

# ── Wrap ────────────────────────────────────────────────────────────────────
# The fixture's lines are short, so wrapping re-flows no text — but it DOES drop
# the line-number gutter, because one-row-per-line stops holding once text can
# wrap. So this asserts on the GUTTER alone. Watching the whole document instead
# reported a 41-pixel difference: technically a change, but smaller than the
# tolerance `assert_regions_same` uses to call two regions identical, which is no
# basis for a claim.
snap gutter numbered
NUMBERED="$SNAP_RESULT"
click 460 61
wait_for 1.2 "wrap on"
snap gutter unnumbered
assert_regions_differ "$NUMBERED" "$SNAP_RESULT" \
    "Wrap should drop the line-number gutter"
click 460 61
wait_for 1.2 "wrap off"

# ── Find ────────────────────────────────────────────────────────────────────
click 420 61
wait_for 1.0 "find bar open"
type_text "REM"
wait_for 1.5 "matches highlighted"
snap text with_matches
assert_regions_differ "$CP437" "$SNAP_RESULT" \
    "Find should highlight the matches in the document"

assert_window_exists
info "=== text_edit test done ==="
