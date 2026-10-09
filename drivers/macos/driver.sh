#!/usr/bin/env bash
# drivers/macos/driver.sh — the macOS driver: the same functions as the X11
# driver, over qa-io (drivers/macos/qa-io.c, CoreGraphics) and screencapture.
#
# Runs INSIDE the logged-in desktop session (window lists and posted events are
# per session; an SSH session sees neither) - start runs with
# drivers/macos/qa-run (it goes through the "QA Runner" app, which holds the
# Accessibility + Screen Recording grants). Coordinates are screen PIXELS (a
# Retina screen has 2 per point; qa-io converts). No offscreen mode: a run
# drives the real screen, mouse and keyboard.

QA_IO="${QA_IO:-$HOME/.qa-runner/bin/qa-io}"

driver_check_deps() {
    local missing=() cmd
    [[ -x "$QA_IO" ]] || missing+=("qa-io ($QA_IO - run drivers/macos/setup.sh)")
    for cmd in screencapture convert compare identify; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing: ${missing[*]}" >&2
        echo "Run drivers/macos/setup.sh (brew install imagemagick, builds qa-io + QA Runner.app)" >&2
        return 1
    fi
    return 0
}

# ── input (screen pixels) ────────────────────────────────────────────────────
driver_input_move()   { "$QA_IO" move "$1" "$2"; }
driver_input_button() { # down|up|click  1|2|3
    case "$1" in
        down)  "$QA_IO" down "$2" ;;
        up)    "$QA_IO" up "$2" ;;
        click) "$QA_IO" click "$2" ;;
    esac
}
driver_input_button_move() { # down|up btn [x y] - press WITH motion (a real drag start)
    case "$1" in
        down) "$QA_IO" seq down "$2" move "$3" "$4" ;;
        up)   "$QA_IO" up "$2" ;;
    esac
}
driver_input_key()      { "$QA_IO" key "$1"; }
driver_input_type()     { "$QA_IO" type "$1"; }
driver_input_scroll()   { "$QA_IO" scroll "$1" "${2:-1}"; }
driver_input_key_hold() { # down|up keyname
    case "$1" in
        down) "$QA_IO" keydown "$2" ;;
        up)   "$QA_IO" keyup "$2" ;;
    esac
}
driver_input_move_rel() { "$QA_IO" moverel "$1" "$2"; }
driver_input_seq()      { "$QA_IO" seq "$@"; }

# ── capture: the main display, in pixels ─────────────────────────────────────
driver_capture_full() { screencapture -x -m -t png "$1" 2>/dev/null && [[ -s "$1" ]]; }

# ── windows ──────────────────────────────────────────────────────────────────
driver_window_find()     { "$QA_IO" find "${1:-}" "$2" 2>/dev/null; }
driver_window_title()    { "$QA_IO" title "$1" 2>/dev/null; }
driver_window_activate() { "$QA_IO" activate "$1" 2>/dev/null; return 0; }
driver_window_bounds()   { "$QA_IO" client "$1" 2>/dev/null; }   # the CLIENT area, as the X11 driver reports it
driver_window_key()      { "$QA_IO" activate "$1" 2>/dev/null; "$QA_IO" key "$2"; }

# driver_window_bounds_by_title <title> [pid] → "X Y W H" of the CLIENT area
# (qa-io client: the frame minus the title bar, whose height qa-io asks AppKit).
driver_window_bounds_by_title() {
    local title=$1 pid=${2:-} wid=""
    [[ -n "$pid" ]] && wid=$(driver_window_find "$pid" "$title")
    [[ -z "$wid" ]] && wid=$(driver_window_find "" "$title")
    [[ -z "$wid" ]] && return 1
    driver_window_bounds "$wid"
}

# The client origin already sits below the title bar, so no extra offset.
driver_detect_decoration_height() { echo 0; }

driver_offscreen_available() { return 1; }
driver_run_offscreen() { echo "macOS has no offscreen mode" >&2; return 1; }
