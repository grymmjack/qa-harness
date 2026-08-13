#!/bin/bash
# transparency.sh — what shows THROUGH a transparent pixel is actually painted.
#
# The backdrop (a checkerboard, or a solid colour) is drawn into the image's rect
# before the art blits over it. Nothing in-process can tell you it happened: the
# decoded PixImage is identical either way, and if the backdrop silently stopped
# painting, transparent areas would simply show the viewer background and every
# unit test would still pass.
#
# The assertion is therefore comparative and cannot be faked: a transparent area
# INSIDE the image must not look like the viewport OUTSIDE it. Identical means
# the backdrop is missing.

info "=== kaleidotron: the transparency backdrop is painted ==="

park_mouse
# 05-alpha.png — a magenta disc on transparency — is row 1, position 5.
click 770 122
wait_for 1.2 "05-alpha.png opens"

# The fixture draws 1:1 at the viewport centre: x 512..640, y 316..444. Its
# corners are transparent (the disc does not reach them).
region inside  516 320 22 22 "a transparent corner INSIDE the image"
region outside 470 320 22 22 "plain viewport, just OUTSIDE the image"

snap inside  through_the_image
INSIDE="$SNAP_RESULT"
snap outside plain_viewport
assert_regions_differ "$INSIDE" "$SNAP_RESULT" \
    "a transparent pixel should show the backdrop, not the plain viewer background"

assert_window_exists
info "=== transparency test done ==="
