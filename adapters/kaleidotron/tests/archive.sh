#!/bin/bash
# archive.sh — a .zip browses as a folder, and its contents really paint.
#
# The mount machinery (extract to a temp dir, keep the archive path as the
# display identity) is model-level and testable in process. What is not is the
# result: that entering the archive paints TILES DECODED FROM INSIDE IT. A mount
# that succeeds and shows an empty grid, or one whose thumbnails never resolve,
# looks identical to a working one from the inside.
#
# The two members are deliberately saturated and different colours, so the
# assertions can be about what is on screen rather than merely that it changed.

info "=== kaleidotron: a .zip browses as a folder and its contents paint ==="

park_mouse
kt_goto "$_KT_NAV"

region grid  60 50 700 170 "the tiles"
region one   70 70 120 100 "the archive's first member once mounted"
region two  230 70 120 100 "…and its second"
region blank 70 570 120 100 "empty background BELOW the last grid row. y=570, not 420: the folder grew to three rows and the old reference sat on a tile, tile-sized"

snap grid outside
OUTSIDE="$SNAP_RESULT"

# tile 1 is bundle.zip — a plain click mounts and enters it.
click 130 122
wait_for 2.0 "bundle.zip mounted and entered"
park_mouse

snap grid inside
assert_regions_differ "$OUTSIDE" "$SNAP_RESULT" \
    "entering an archive should repaint the grid with its members"

snap blank
BLANK="$SNAP_RESULT"
snap one
assert_regions_differ "$BLANK" "$SNAP_RESULT" \
    "the archive's first member should paint a thumbnail"
# …and it is the member's own colour, not a spinner. An unresolved thumbnail
# paints a grey arc, which passes the differs-from-blank check above.
kt_assert_dominant "$SNAP_RESULT" r "zipped-one.png is magenta — red should lead, not grey"
snap two
assert_regions_differ "$BLANK" "$SNAP_RESULT" \
    "…and so should the second"
kt_assert_dominant "$SNAP_RESULT" g "zipped-two.png is cyan — green should lead over red"

key BackSpace
wait_for 1.5 "back out of the archive"
park_mouse
snap grid back_outside
assert_regions_same "$OUTSIDE" "$SNAP_RESULT" \
    "leaving the archive should restore the parent listing exactly"

assert_window_exists
info "=== archive test done ==="
