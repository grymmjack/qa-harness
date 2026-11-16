#!/bin/bash
# clipboard-text-editing.sh — while editing text, Ctrl+X cuts the selected text
# and keeps the text box (the canvas Cut action must not delete the whole item).

info "=== drawy: Ctrl+X inside a text box cuts text, not the box ==="

region text 300 280 200 60 "where the text is typed"

park_mouse
snap text text-empty; EMPTY="$SNAP_RESULT"

key t
click 300 300
wait_for 0.5 "editing"
type_text "hello"
key ctrl+a
key ctrl+x
wait_for 0.3 "cut"
# still editing the same box: typing goes into it
type_text "bye"
wait_for 0.3 "typed"
park_mouse
snap text text-after
assert_regions_differ "$EMPTY" "$SNAP_RESULT" "the text box should survive Ctrl+X and receive the new text"
