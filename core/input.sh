#!/usr/bin/env bash
# core/input.sh — the test-facing input aliases. These are the names DRAW's ~97
# tests call (click, drag, key, type_text, scroll_*, park_mouse, wait_for). Each
# takes LOGICAL coords, wakes the app (adapter_pre_input), maps logical→screen
# (adapter_to_screen), and drives the OS through the driver_* verbs. The composite
# click/drag SEQUENCES (the SDL2-safe 1px-drag) live here; the primitives and the
# key-chord logic live in the driver. Ported from DRAW/QA/draw-qa.sh.

# click X Y [button=1] — logical coords.
# Implemented as a 1px drag (down → move 1px → up) because SDL2 reliably processes
# XTEST pointer events that include motion.
click() {
    local x=$1 y=$2 btn=${3:-1} ax ay
    _qa_pre_input
    read -r ax ay <<< "$(adapter_to_screen "$x" "$y")"
    dbg "click vp=($x,$y) abs=($ax,$ay) btn=$btn"
    driver_input_move "$ax" "$ay"
    sleep 0.08
    driver_input_button down "$btn"
    sleep 0.05
    driver_input_move $(( ax + 1 )) "$ay"
    sleep 0.05
    driver_input_button up "$btn"
    sleep 0.1
}

# right_click X Y
right_click() { click "$1" "$2" 3; }

# double_click X Y
double_click() {
    local ax ay
    _qa_pre_input
    read -r ax ay <<< "$(adapter_to_screen "$1" "$2")"
    driver_input_move "$ax" "$ay"; sleep 0.05
    driver_input_button down 1; sleep 0.05
    driver_input_move $(( ax + 1 )) "$ay"; sleep 0.05
    driver_input_button up 1; sleep 0.1
    driver_input_button down 1; sleep 0.05
    driver_input_move $(( ax + 2 )) "$ay"; sleep 0.05
    driver_input_button up 1; sleep 0.1
}

# drag from_x from_y to_x to_y [button=1]
drag() {
    local x1=$1 y1=$2 x2=$3 y2=$4 btn=${5:-1} ax1 ay1 ax2 ay2
    _qa_pre_input
    read -r ax1 ay1 <<< "$(adapter_to_screen "$x1" "$y1")"
    read -r ax2 ay2 <<< "$(adapter_to_screen "$x2" "$y2")"
    dbg "drag vp=($x1,$y1)→($x2,$y2) abs=($ax1,$ay1)→($ax2,$ay2) btn=$btn"
    driver_input_move "$ax1" "$ay1"
    sleep 0.1
    driver_input_button down "$btn"
    driver_input_move $(( ax1 + 1 )) "$ay1"
    sleep 0.05
    driver_input_move "$ax2" "$ay2"
    sleep 0.15
    driver_input_button up "$btn"
    sleep 0.1
}

# scroll_up / scroll_down at logical-pixel coords
scroll_up() {
    local ax ay; read -r ax ay <<< "$(adapter_to_screen "$1" "$2")"
    _qa_pre_input; driver_input_move "$ax" "$ay"; sleep 0.05
    driver_input_scroll up 1; sleep 0.05
}
scroll_down() {
    local ax ay; read -r ax ay <<< "$(adapter_to_screen "$1" "$2")"
    _qa_pre_input; driver_input_move "$ax" "$ay"; sleep 0.05
    driver_input_scroll down 1; sleep 0.05
}

# type text (printable chars only)
type_text() {
    _qa_pre_input
    driver_input_type "$1"
    sleep 0.1
}

# key — send one or more key combos (space-separated).
# Examples: key Return   key ctrl+z   key Escape F1
# The per-combo SDL2-safe chord handling lives in driver_input_key.
key() {
    _qa_pre_input
    dbg "key $*"
    local combo
    for combo in "$@"; do
        driver_input_key "$combo"
    done
    sleep 0.1
}

# Move the cursor to an inert corner so the app's crosshair overlay doesn't appear
# in canvas snap regions. Logical (50,60) is an inert spot for DRAW.
park_mouse() {
    local ax ay
    read -r ax ay <<< "$(adapter_to_screen 50 60)"
    dbg "park_mouse → abs ($ax,$ay)"
    driver_input_move "$ax" "$ay"
    sleep 0.05
}

# wait N seconds with a message
wait_for() {
    local secs=$1 msg=${2:-"settling..."}
    info "Waiting ${secs}s — $msg"
    sleep "$secs"
}
