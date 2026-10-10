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
# driver_window_ready H - once, right after an app's window appears. A GLFW app
# that another process launched (QA Runner) gets keys but NO mouseMoved / wheel
# until it has been deactivated and activated again, and it may not even come to
# the front (the previous app keeps focus). Neither the AX frontmost flag nor
# NSRunningApplication activate fixes it, and Cmd+Tab fails when the app is not
# in the switcher's order. System Events does it every time: Finder to the
# front, then the app. Needs QA Runner allowed to control System Events
# (Privacy & Security > Automation; macOS asks once).
_front_pid() { lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null | sed 's/.*=//'; }
_qa_io_serve() {
    "$QA_IO" stop >/dev/null 2>&1
    ( "$QA_IO" serve >/dev/null 2>&1 & )
    local i; for (( i = 0; i < 40; i++ )); do "$QA_IO" ping 2>/dev/null && return 0; sleep 0.05; done
    echo "warning: qa-io serve did not start - input runs per call (drags may fail)" >&2
}
driver_window_ready() {
    _qa_io_serve      # one process posts all input from here on (see qa-io.c serve())
    local pid i; pid=$("$QA_IO" pid "$1" 2>/dev/null) || return 0
    for i in 1 2 3; do
        osascript >/dev/null 2>&1 <<OSA
tell application "System Events"
    set frontmost of process "Finder" to true
    delay 0.4
    set frontmost of (first process whose unix id is $pid) to true
end tell
OSA
        sleep 0.6
        [[ "$(_front_pid)" == "$pid" ]] && return 0
    done
    # Never send a test's input to whatever else is in front (it would type into
    # the user's editor): give up loudly instead.
    echo "ERROR: could not bring the app to the front (front pid $(_front_pid), app pid $pid) - check Privacy & Security > Automation: QA Runner > System Events" >&2
    return 1
}
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

# physical pixels per point of the main screen (macOS Retina = 2)
driver_backing_scale() { "$QA_IO" scale | cut -d. -f1; }   # 2 on Retina

driver_offscreen_available() { return 1; }
driver_run_offscreen() { echo "macOS has no offscreen mode" >&2; return 1; }
