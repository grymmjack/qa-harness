#!/bin/bash
# rip.sh — RIPscript renders, and the baud player really draws it progressively.
#
# RIP is a VECTOR command stream, not a bitmap: lines, filled polygons, ellipses
# and stroke text executed onto a 640x350 EGA canvas by hand-rolled integer BGI
# primitives. Those primitives are the most painstaking code in the project —
# CLAUDE.md's notes are largely about closing this very dragon's body outline and
# sealing its eye — and their correctness is only ever visible as pixels. The
# golden-scene unit tests compare rasterised buffers; nothing until now checked
# that the result reaches the screen.
#
# The second half is stranger and even less testable in process: kaleidotron can
# replay a RIP at a MODEM BAUD RATE, so you watch it draw the way a caller would
# have in 1993. That is a frame that changes over time from a byte cursor — there
# is no state to assert on, only successive frames.
#
# ── How the player actually behaves (calibrated, not assumed) ───────────────
# A .rip opens FULLY DRAWN with the player at rest (100%), even though the baud
# combo shows a remembered rate. PICKING a rate from the combo is what restarts
# the file and begins the draw. 2400 is used because it is slow enough that a
# mid-draw frame is unambiguous — at 2.5s it is around 20% and the dragon is a
# few faint strokes. Faster rates finish the visible artwork early and leave only
# credits, so a "mid-draw" frame looks identical to the finished one.
#
#   baud combo   (235, 61)      2400 in the dropdown   (210, 150)
#   18-dragon.rip is row 3, position 5 → tile centre (770, 468)

info "=== kaleidotron: RIPscript renders, and replays at baud ==="

park_mouse

region tile      710 406 120 100 "the 18-dragon.rip thumbnail"
region tile_ref  710 570 120 100 "empty background, tile-sized"

snap tile_ref
BLANK="$SNAP_RESULT"
snap tile
assert_regions_differ "$BLANK" "$SNAP_RESULT" \
    "the .rip should rasterise to a thumbnail"
# The dragon is bright green on black — colour, so a spinner cannot pass.
kt_assert_dominant "$SNAP_RESULT" g "the dragon tile should be green, not a spinner"

click 770 468
wait_for 2.5 "18-dragon.rip opens, drawn to completion"

region canvas 350 250 400 250 "the middle of the EGA canvas, across the dragon"
snap canvas complete
COMPLETE="$SNAP_RESULT"
kt_assert_dominant "$COMPLETE" g "the rendered scene should be the green dragon"

# Picking a baud restarts the file and draws it out. At 2400 the scene is only
# beginning after a couple of seconds, so this frame must differ from the
# finished one — which is the whole claim: the player paints a PREFIX of the
# command stream, not the finished image.
click 235 61
wait_for 1.0 "baud dropdown open"
click 210 150
wait_for 2.5 "replaying at 2400 baud — mid-draw"

snap canvas mid_draw
assert_regions_differ "$COMPLETE" "$SNAP_RESULT" \
    "at 2400 baud the scene should still be part-drawn, not the finished frame"

assert_window_exists
info "=== rip test done ==="
