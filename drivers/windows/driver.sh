#!/usr/bin/env bash
# drivers/windows/driver.sh — the Windows driver (Git Bash): the same functions
# as the X11 driver, over qa-io.exe (drivers/windows/qa-io.cs, SendInput / Win32).
#
# Runs INSIDE the logged-in desktop session - an SSH session has no desktop.
# Start runs with drivers/windows/qa-run (a Scheduled Task as the desktop user,
# "run only when logged on"). Coordinates are PHYSICAL pixels (qa-io is
# DPI-aware). No offscreen mode: a run drives the real screen, mouse, keyboard.
# drivers/windows/bin holds Git Bash shims: pgrep (via ps -W) and the
# ImageMagick legacy names (convert / compare / identify -> magick), because
# Windows has its own unrelated convert.exe.

QA_IO="${QA_IO:-/c/qa-runner/bin/qa-io.exe}"
_WIN_DRV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$_WIN_DRV_DIR/bin:$PATH"
for _im in /c/qa-runner/imagemagick /c/Program\ Files/ImageMagick*; do [[ -x "$_im/magick.exe" ]] && export PATH="$PATH:$_im"; done

_winpath() { cygpath -w "$1" 2>/dev/null || echo "$1"; }

driver_check_deps() {
    local missing=() cmd
    [[ -x "$QA_IO" ]] || missing+=("qa-io.exe ($QA_IO - run drivers/windows/setup.sh)")
    command -v magick &>/dev/null || missing+=("ImageMagick (winget install ImageMagick.ImageMagick)")
    for cmd in convert compare identify pgrep; do command -v "$cmd" &>/dev/null || missing+=("$cmd"); done
    if [[ ${#missing[@]} -gt 0 ]]; then echo "Missing: ${missing[*]}" >&2; return 1; fi
    return 0
}

# ── input (physical screen pixels) ───────────────────────────────────────────
driver_input_move()   { "$QA_IO" move "$1" "$2"; }
driver_input_button() {
    case "$1" in
        down)  "$QA_IO" down "$2" ;;
        up)    "$QA_IO" up "$2" ;;
        click) "$QA_IO" click "$2" ;;
    esac
}
driver_input_button_move() {
    case "$1" in
        down) "$QA_IO" seq down "$2" move "$3" "$4" ;;
        up)   "$QA_IO" up "$2" ;;
    esac
}
driver_input_key()      { "$QA_IO" key "$1"; }
driver_input_type()     { "$QA_IO" type "$1"; }
driver_input_scroll()   { "$QA_IO" scroll "$1" "${2:-1}"; }
driver_input_key_hold() {
    case "$1" in
        down) "$QA_IO" keydown "$2" ;;
        up)   "$QA_IO" keyup "$2" ;;
    esac
}
driver_input_move_rel() { "$QA_IO" moverel "$1" "$2"; }
driver_input_seq()      { "$QA_IO" seq "$@"; }

# ── capture: the primary screen ──────────────────────────────────────────────
driver_capture_full() { "$QA_IO" capture "$(_winpath "$1")" && [[ -s "$1" ]]; }

# ── windows (HWND as a decimal number) ───────────────────────────────────────
driver_window_find()     { "$QA_IO" find "${1:-}" "$2" 2>/dev/null | tr -d '\r'; }
driver_window_title()    { "$QA_IO" title "$1" 2>/dev/null | tr -d '\r'; }
driver_window_activate() { "$QA_IO" activate "$1" 2>/dev/null; return 0; }
driver_window_bounds()   { "$QA_IO" client "$1" 2>/dev/null | tr -d '\r'; }   # the CLIENT area
driver_window_key()      { "$QA_IO" activate "$1" 2>/dev/null; "$QA_IO" key "$2"; }

# A Git Bash $! is an MSYS pid; qa-io wants the Windows pid of the window owner.
_winpid() { local w; w=$(ps -W 2>/dev/null | awk -v p="$1" '$1 == p {print $4; exit}'); echo "${w:-$1}"; }

driver_window_bounds_by_title() {
    local title=$1 pid=${2:-} wid=""
    [[ -n "$pid" ]] && wid=$(driver_window_find "$(_winpid "$pid")" "$title")
    [[ -z "$wid" ]] && wid=$(driver_window_find "" "$title")
    [[ -z "$wid" ]] && return 1
    driver_window_bounds "$wid"
}
driver_detect_decoration_height() { echo 0; }   # client origin already below the title bar

driver_offscreen_available() { return 1; }
driver_run_offscreen() { echo "Windows has no offscreen mode" >&2; return 1; }
