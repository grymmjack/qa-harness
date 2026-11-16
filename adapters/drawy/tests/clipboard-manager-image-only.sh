#!/bin/bash
# clipboard-manager-image-only.sh — a clipboard manager (Klipper) may take the
# clipboard over and offer only the PNG Drawy rendered. Pasting that back into
# Drawy must still give the original objects, not a picture.

info "=== drawy: paste is native even after a clipboard manager keeps only the image ==="

region panel 10 255 180 240 "properties panel: stroke to opacity"
region corners 10 595 180 45 "properties panel: corner type"
TMP_PNG=$(mktemp --suffix=.png)

key r
drag 220 220 400 380
key s
click 900 650
drag 190 190 430 410
wait_for 0.3 "original selected"
park_mouse
snap panel panel-original; ORIGINAL="$SNAP_RESULT"
snap corners corners-original; ORIGINAL_CORNERS="$SNAP_RESULT"

key ctrl+c
wait_for 0.3 "copied"

# act like Klipper: take the clipboard over and serve only the image
xclip -selection clipboard -t image/png -o > "$TMP_PNG"
xclip -quiet -selection clipboard -t image/png -i "$TMP_PNG" >/dev/null 2>&1 &
XCLIP_PID=$!
wait_for 0.5 "clipboard taken over"
TARGETS=$(xclip -selection clipboard -t TARGETS -o 2>/dev/null | tr '\n' ' ')
info "clipboard now offers: $TARGETS"
if [[ "$TARGETS" == *x-drawy-clipboard* ]]; then
    fail "the simulated clipboard manager should have dropped the native format"
fi

hover 800 500
key ctrl+v
wait_for 0.5 "pasted"
park_mouse
snap panel panel-pasted
assert_regions_same "$ORIGINAL" "$SNAP_RESULT" "the pasted item should still be a rectangle" 0
snap corners corners-pasted
assert_regions_same "$ORIGINAL_CORNERS" "$SNAP_RESULT" "the pasted item should have a corner type, like a rectangle" 0

kill "$XCLIP_PID" 2>/dev/null
rm -f "$TMP_PNG"
