#!/bin/bash
# sauce.sh — a SAUCE record reaches the Details pane.
#
# SAUCE is the 128-byte metadata block BBS-era scene art carries at the end of
# the file — title, artist, group, and the canvas hints the decoder uses. The
# parser is unit tested against bytes; what is not covered is that the parsed
# record is surfaced, and surfaced only for art that HAS one.
#
# The claim is comparative, which is what makes it meaningful: the pane must show
# a SAUCE section for the piece that carries a record and NOT for the one that
# does not. A pane that always drew the section, or never did, would pass a
# simpler "did something change" test.
#
# The fixture's record is written by hand (fixtures/19-sauce.ans) rather than by
# a tool, so it pins the real 128-byte layout.
#
# Sorted DESCENDING first so 19-sauce.ans is the first tile: with the Details
# dock open the grid narrows to four columns, and 19 fixtures then push the last
# row below the fold where nothing can hover it.

info "=== kaleidotron: a SAUCE record is surfaced in Details ==="

park_mouse
click 368 727
wait_for 1.5 "sorted descending — 19-sauce.ans leads"
click 27 172
wait_for 1.5 "details dock open"

region sauce 55 565 300 140 "where the SAUCE section is drawn"

# 18-dragon.rip is the second tile and carries no SAUCE record.
kt_hover 590 122
wait_for 2.0 "hovering the RIP, which has no SAUCE"
snap sauce no_record
NO_SAUCE="$SNAP_RESULT"

kt_hover 430 122
wait_for 2.5 "hovering 19-sauce.ans"
snap sauce with_record
assert_regions_differ "$NO_SAUCE" "$SNAP_RESULT" \
    "a piece carrying a SAUCE record should show a SAUCE section"

# …and going back to the record-less piece removes it again, so the section is
# driven by the file rather than left over from whatever was hovered before.
kt_hover 590 122
wait_for 2.0 "back to the RIP"
snap sauce gone_again
assert_regions_same "$NO_SAUCE" "$SNAP_RESULT" \
    "and it should disappear again for a piece without one"

assert_window_exists
info "=== sauce test done ==="
