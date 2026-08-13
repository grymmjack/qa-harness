#!/bin/bash
# osd.sh — the metadata OSD fades in on open and fades out again.
#
# The OSD is a painted overlay on a timer: fade in, hold, fade out. It has no
# widget, no accessibility node and no state worth reading — it exists purely as
# pixels over the image, which makes it invisible to every other kind of test.
#
# It is turned OFF in the blessed config on purpose, because a fading overlay
# under a region diff is a race that would destabilise every viewer test. So this
# test turns it on ITSELF through Preferences, which also exercises that the
# setting takes effect without a restart.
#
#   gear (27,735) → Preferences (110,629) → Viewer tab (156,97)
#   "Show metadata overlay on open" (41,296)      close × (789,41)
#
# Default position is Top, and the hold is 3s.

info "=== kaleidotron: the metadata OSD fades in and out ==="

park_mouse
click 27 735
wait_for 0.8 "gear menu"
click 110 629
wait_for 1.5 "Preferences open"
click 156 97
wait_for 1.0 "Viewer section"
click 41 296
wait_for 1.0 "OSD enabled"
click 789 41
wait_for 1.2 "Preferences closed"
park_mouse

region osd 300 60 500 120 "where the OSD panel is drawn, top-centre"

click 130 122
# Move the pointer well clear before anything else: HOVERING THE OSD PINS IT
# OPEN (that is a feature — it is how you stop it fading while you read it), and
# the click that opened the file leaves the pointer inside the panel's rect. The
# first version of this test never saw it fade for exactly that reason.
kt_hover 550 620
wait_for 1.0 "01-red.png opens — the OSD fades in"
snap osd shown
SHOWN="$SNAP_RESULT"
# The claim is about the OSD, so both sides of it must be the VIEWER — comparing
# against the grid instead (as the first version did) differs for the entirely
# unrelated reason that the view changed, and would "pass" with no OSD at all.
region osd_ref 300 300 500 120 "viewer background below the OSD, same size"
snap osd_ref
assert_regions_differ "$SHOWN" "$SNAP_RESULT" \
    "opening a file should draw the metadata OSD over the image"

# Hold is 3s and the fade-out ~0.7s, so by 6s it must be gone. The region then
# shows plain viewer background again — the same thing it showed before the file
# was opened, which is why `before_open` is the right baseline to return to.
wait_for 6.0 "the OSD holds, then fades out"
snap osd faded
assert_regions_differ "$SHOWN" "$SNAP_RESULT" \
    "the OSD should fade out again, leaving the view clean"

assert_window_exists
info "=== osd test done ==="
