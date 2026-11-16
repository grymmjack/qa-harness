#!/bin/bash
# handwriting-model-download.sh — the first conversion downloads the
# recognition model (about 20 MB, needs the network) and then converts.
# Needs Drawy built with ONNX Runtime. Starts without the model.

info "=== drawy: download the handwriting model, then convert ==="

source "$ADAPTER_TESTS_DIR/../lib/handwriting.sh"

region letter_o 515 295 45 70 "where the O is written (the text is narrower)"

park_mouse
snap letter_o o-empty; EMPTY_O="$SNAP_RESULT"

write_hello
key ctrl+a
wait_for 0.3 "selected"
convert_selection
wait_for 1 "download question"

# Download is the default button
key Return
wait_for 2 "download started"
screenshot handwriting-downloading
wait_for 40 "download and recognition"
park_mouse
screenshot handwriting-downloaded-and-converted

snap letter_o o-converted
assert_regions_same "$EMPTY_O" "$SNAP_RESULT" "after the download the handwriting should be converted" 0
