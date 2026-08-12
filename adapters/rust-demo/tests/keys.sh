#!/bin/bash
# keys.sh — keyboard drives the demo too: R/G/B select a color, C clears.
# Proves the driver's key verb (not just mouse) against adapter #2.

info "=== rust-demo: keyboard selects + clears ==="

region canvas 40 120 200 80 "the demo's fill canvas"

# Press R → canvas red.
key r
wait_for 0.3 "R → canvas red"
snap canvas keyed-red
RED_SNAP="$SNAP_RESULT"

# Press C → canvas clears (must differ from the red fill).
key c
wait_for 0.3 "C → canvas cleared"
snap canvas cleared
assert_regions_differ "$RED_SNAP" "$SNAP_RESULT" "C should clear the canvas (differs from red)"
CLEARED="$SNAP_RESULT"

# Press G → canvas green (differs from the cleared state).
key g
wait_for 0.3 "G → canvas green"
snap canvas keyed-green
assert_regions_differ "$CLEARED" "$SNAP_RESULT" "G should fill the canvas (differs from cleared)"

assert_window_exists
info "=== rust-demo keys test done ==="
