#!/bin/bash
# textmode.sh — CP437/ANSI art renders, and its display toggles change the pixels.
#
# The scene-art path is the project's reason to exist and the least unit-testable
# part of it: ansi.rs is covered for parsing, but "the glyphs land on screen at
# the right scale" is only observable as pixels. Also covers the navigator
# minimap, which is painted and has no other test.
#
# ── Two app behaviours this test had to be built around ─────────────────────
#
# 1. AN .ans AUTO-PLAYS. Text-mode art opens in the baud-rate player (4800 by
#    default), typing itself out BBS-style and auto-scrolling to follow the
#    cursor. Any snap taken while that runs is racing an animation, and the first
#    version of this test did exactly that — its later assertions compared frames
#    from different playback positions and failed with the art scrolled off
#    screen entirely. `Home` both interrupts playback (any input finishes it
#    instantly) and scrolls back to the top, giving one settled, repeatable
#    frame.
#
# 2. "CRT" IN THE STATUS BAR IS A MENU, NOT A TOGGLE. The switches live inside
#    the popup, and clicking one CLOSES the popup. So each toggle is
#    open-then-click; adding a "dismiss" step re-opens it, and the next click
#    then closes it instead of toggling — which is how an earlier version got two
#    different toggles producing byte-identical results. Escape is no good
#    either: it leaves the VIEWER, not the popup.
#
# There is deliberately no "toggle back and assert it restored" here. It couples
# to that menu-state ordering and was flaky without adding a claim: that a toggle
# changes the pixels is already asserted, once per toggle.

info "=== kaleidotron: ANSI art renders; the CRT toggles change the blit ==="

kt_refresh
park_mouse

# 08-art.ans is row 2, position 2 → tile centre (290, 290).
click 290 290
wait_for 2.0 "08-art.ans opens and plays out at 4800 baud"
key Home
wait_for 1.2 "playback interrupted, scrolled to the top — one settled frame"

region art        390  80 320 200 "the rendered ANSI art"
region art_blank  390 500 320 200 "empty viewport below the art, art-sized"
region mini       965  78 120 200 "the navigator minimap"
region mini_blank 700 500 120 200 "empty viewport, minimap-sized"

# Each "is it painted?" check pairs the region with an equally-sized patch of
# empty viewport — same dimensions, or `compare` diffs only the overlap and the
# assertion is meaningless.
snap art rendered
ART="$SNAP_RESULT"
snap art_blank
assert_regions_differ "$ART" "$SNAP_RESULT" \
    "the ANSI art should be rendered (identical to blank = nothing decoded)"

snap mini minimap
MINI="$SNAP_RESULT"
snap mini_blank
assert_regions_differ "$MINI" "$SNAP_RESULT" \
    "the navigator minimap should be painted for an oversized image"

# The CRT popup and its two switches. The popup opens over the bottom-right and
# does not overlap the art region, so it can be left open across a snap.
_kt_crt() { click 740 748; wait_for 0.7 "CRT menu open"; }

# CRT aspect: a display-only ~1.2x vertical stretch to match non-square VGA
# pixels. It changes no state a test could read — only the blit — so pixels are
# the only possible evidence. On by default, so this turns it OFF.
_kt_crt
click 749 589
wait_for 1.0 "CRT aspect off"
snap art aspect_off
assert_regions_differ "$ART" "$SNAP_RESULT" \
    "toggling CRT aspect should restretch the art vertically"
AFTER_ASPECT="$SNAP_RESULT"

# The 9-dot VGA cell is a stronger claim than a display transform: it is a
# DECODE-time change (the 8px glyph drawn in a 9px cell, the way real VGA text
# mode did), so the texture itself is re-rendered ~12.5% wider. Nothing but
# pixels can show that the re-decode happened.
_kt_crt
click 749 611
wait_for 1.5 "9-dot VGA cell on — the art re-decodes wider"
snap art ninepx
assert_regions_differ "$AFTER_ASPECT" "$SNAP_RESULT" \
    "the 9-dot VGA cell should re-decode the art wider"

assert_window_exists
info "=== textmode test done ==="
