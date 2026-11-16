#!/bin/bash
# handwriting-model-declined.sh — without the recognition model, converting
# asks to download it; saying no leaves the handwriting as it was.
# Needs Drawy built with ONNX Runtime. Starts without the model.

info "=== drawy: decline the handwriting model download ==="

source "$ADAPTER_TESTS_DIR/../lib/handwriting.sh"

region writing 290 290 270 80 "the handwriting"

write_hello
park_mouse
snap writing writing-drawn; DRAWN="$SNAP_RESULT"

key ctrl+a
wait_for 0.3 "selected"
convert_selection
wait_for 1 "download question"
screenshot handwriting-download-question

key Escape
wait_for 0.5 "question closed"
click 900 650
wait_for 0.3 "deselected"
park_mouse
snap writing writing-after
assert_regions_same "$DRAWN" "$SNAP_RESULT" "declining the download should leave the handwriting alone" 0
