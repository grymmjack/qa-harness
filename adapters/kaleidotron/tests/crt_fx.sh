#!/bin/bash
# crt_fx.sh — the CRT post-effects change the pixels.
#
# Scanlines and glow are baked at PAINT time — a tiled scanline texture blitted
# over the viewport, and an additive redraw ring for the bloom. They alter no
# state a test could read back, and they are the sort of thing that silently
# stops working when a blend mode or a draw order changes. Pixels are the only
# possible evidence.
#
# The switches live in the status-bar "CRT" MENU, and clicking one CLOSES the
# popup — so each toggle is open-then-click, never open-click-dismiss (see
# textmode.sh for what that mistake looks like).

info "=== kaleidotron: scanlines and glow change the blit ==="

park_mouse
click 290 290
wait_for 2.0 "08-art.ans opens and plays out"
key Home
wait_for 1.2 "settled at the top"

region art 390 80 320 200 "the rendered art"
snap art plain
PLAIN="$SNAP_RESULT"

_kt_crt() { click 740 748; wait_for 0.7 "CRT menu open"; }

# Scanlines: a slider, so click near the right of its track to turn it well up.
_kt_crt
click 835 640
wait_for 1.2 "scanlines up"
snap art scanlines
assert_regions_differ "$PLAIN" "$SNAP_RESULT" \
    "raising the scanline slider should darken alternating rows"
SCAN="$SNAP_RESULT"

# Glow: a checkbox, luminance-weighted bloom around bright glyphs.
_kt_crt
click 749 682
wait_for 1.5 "glow on"
snap art glow
assert_regions_differ "$SCAN" "$SNAP_RESULT" \
    "enabling glow should bloom the bright pixels"

assert_window_exists
info "=== crt_fx test done ==="
