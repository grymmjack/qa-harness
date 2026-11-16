#!/bin/bash
# handwriting-to-text.sh — printed handwriting becomes a text box in its place;
# one undo brings the strokes back.
# Needs Drawy built with ONNX Runtime.
# QA-DRAWY-MODEL: installed

info "=== drawy: convert handwriting to text ==="

source "$ADAPTER_TESTS_DIR/../lib/handwriting.sh"

region writing 290 290 270 80 "the handwriting"
region letter_o 515 295 45 70 "where the O is written (the text is narrower)"

park_mouse
snap letter_o o-empty; EMPTY_O="$SNAP_RESULT"

write_hello
park_mouse
snap writing writing-drawn; DRAWN="$SNAP_RESULT"

key ctrl+a
wait_for 0.3 "selected"
convert_selection
wait_for 3 "recognition"
park_mouse
screenshot handwriting-converted

snap writing writing-converted
assert_regions_differ "$DRAWN" "$SNAP_RESULT" "the handwriting should be replaced"
snap letter_o o-converted
assert_regions_same "$EMPTY_O" "$SNAP_RESULT" "the strokes should be gone (the text is narrower than the writing)" 0

key ctrl+z
wait_for 0.5 "undo"
park_mouse
snap writing writing-undone
assert_regions_same "$DRAWN" "$SNAP_RESULT" "one undo should bring the strokes back" 0
