#!/usr/bin/env bash
# linux-x11 driver — the ONLY OS-specific layer. Input via xdotool (XTEST),
# capture via spectacle (Wayland) / scrot (X11 & Xvfb), window bounds via
# xwininfo, offscreen via Xvfb. Bodies ported from DRAW/QA/draw-qa.sh (noted per
# function). The core and adapters call ONLY these driver_* verbs.
#
# Contract implemented here: see ARCHITECTURE.md → "The driver interface".

# ── dependency check ─────────────────────────────────────────────────────────
# xwininfo supplies the client-area origin every click and capture is measured
# from. Without it the xdotool fallback reports the frame on a reparenting WM and
# silently offsets the entire suite — so treat it as required, not optional.
driver_check_deps() {
    local missing=() cmd
    for cmd in xdotool scrot xwininfo convert compare; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing dependencies: ${missing[*]}" >&2
        echo "Install with: sudo apt install ${missing[*]}" >&2
        return 1
    fi
    return 0
}

# ── input (screen coords already resolved by the adapter) ────────────────────
driver_input_move()   { xdotool mousemove -- "$1" "$2"; }
driver_input_button() { # down|up|click  1|2|3
    case "$1" in
        down)  xdotool mousedown "$2" ;;
        up)    xdotool mouseup   "$2" ;;
        click) xdotool click     "$2" ;;
    esac
}

# driver_input_key <combo> — send ONE key combo (the caller loops over several).
#
# Ported from draw-qa.sh key(). Does NOT use --window: xdotool without --window
# uses the XTEST extension which generates real key events that SDL2's
# SDL_GetKeyboardState (and _KEYDOWN) can see. With --window it uses XSendEvent
# which doesn't update physical keyboard state — breaking all modifier combos.
#
# For combos with modifiers (ctrl+, shift+, alt+, super+), hold modifiers via
# keydown, sleep so the app's _KEYDOWN polling registers them, tap the base key,
# then release. Without this, xdotool's microsecond press/release finishes before
# the app's next frame poll.
driver_input_key() {
    local combo=$1
    if [[ "$combo" == *"+"* ]]; then
        # Split modifier combo: ctrl+shift+n → mods=(ctrl shift) base=n
        local IFS='+' parts=($combo)
        local base="${parts[-1]}"
        local mods=("${parts[@]:0:${#parts[@]}-1}")
        # Hold modifiers one at a time so the polling loop registers each
        local m
        for m in "${mods[@]}"; do
            xdotool keydown "$m"
            sleep 0.06   # hold each modifier ~3-4 frames at 59fps
        done
        sleep 0.06   # let the app poll the full modifier state
        # Press and release the base key while modifiers are held.
        # Hold 200ms so that even at 13fps idle (~77ms/frame) it spans 2+ frames
        xdotool keydown "$base"
        sleep 0.20
        xdotool keyup "$base"
        sleep 0.04
        # Release modifiers in reverse order
        local i
        for (( i=${#mods[@]}-1; i>=0; i-- )); do
            xdotool keyup "${mods[$i]}"
        done
    else
        # keydown/sleep/keyup instead of 'xdotool key' so _KEYDOWN-polling sees
        # the key held for at least 2 idle frames
        xdotool keydown "$combo"
        sleep 0.10
        xdotool keyup "$combo"
    fi
    sleep 0.05
}

driver_input_type()   { xdotool type --clearmodifiers --delay 30 -- "$1"; }
driver_input_scroll() { # up|down [ticks]
    local n=${2:-1} b
    [[ "$1" == up ]] && b=4 || b=5
    while (( n-- > 0 )); do xdotool click "$b"; done
}

# ── capture (full display; core crops regions) ───────────────────────────────
# Backend selection (learned the hard way — neither tool is right in both worlds):
#   • Real Wayland session (WAYLAND_DISPLAY set): scrot returns an all-black
#     frame, so use spectacle (Wayland backend). setsid keeps the compositor from
#     stealing keyboard focus from the app; no --fork so we block until the
#     capture is on disk (avoids overlapping-capture races).
#   • Pure X11 / offscreen Xvfb (WAYLAND_DISPLAY unset): scrot captures the actual
#     $DISPLAY reliably. spectacle here reaches the *real* desktop through the xdg
#     portal and grabs the WRONG screen — silently making every region diff
#     compare a static wrong frame. This is the CI / shared-computer path.
# Override with QA_CAPTURE=scrot|spectacle|<cmd that takes an output path>.
driver_capture_full() {
    local out=$1 backend="${QA_CAPTURE:-}"
    rm -f "$out"
    if [[ -z "$backend" ]]; then
        if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v spectacle &>/dev/null; then
            backend=spectacle
        else
            backend=scrot
        fi
    fi
    case "$backend" in
        spectacle) setsid spectacle -b -n -f -o "$out" 2>/dev/null ;;
        scrot)     scrot "$out" 2>/dev/null ;;
        *)         "$backend" "$out" 2>/dev/null ;;
    esac
    [[ -s "$out" ]] || scrot "$out" 2>/dev/null   # last-ditch fallback
    [[ -s "$out" ]]
}

# ── target / lifecycle ───────────────────────────────────────────────────────
# driver_window_bounds_by_title <title> [pid] → "X Y W H".
# X/Y are the CLIENT-area origin from xwininfo's "Absolute upper-left" (which is
# reparenting-aware — the authoritative answer, and what every click and capture
# offset is measured from). Degrades to xdotool geometry. Ported from
# draw-qa.sh _update_win_pos. Match by pid+title first so other app instances
# don't interfere, then title alone.
driver_window_bounds_by_title() {
    local title=$1 pid=${2:-} wid=""   # wid MUST init: it's read at the title fallback
                                       # even when no pid is given (set -u safe)
    if [[ -n "$pid" ]]; then
        wid=$(xdotool search --pid "$pid" --name "$title" 2>/dev/null | head -1)
    fi
    [[ -z "$wid" ]] && wid=$(xdotool search --name "$title" 2>/dev/null | head -1)
    [[ -z "$wid" ]] && return 1
    local info ax ay w h
    info=$(xwininfo -id "$wid" 2>/dev/null)
    ax=$(awk '/Absolute upper-left X/ {print $NF}' <<< "$info")
    ay=$(awk '/Absolute upper-left Y/ {print $NF}' <<< "$info")
    w=$(awk '/Width:/  {print $NF}' <<< "$info")
    h=$(awk '/Height:/ {print $NF}' <<< "$info")
    if [[ -z "$ax" || -z "$ay" ]]; then
        eval "$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null)"
        ax=${X:-0}; ay=${Y:-0}; w=${WIDTH:-0}; h=${HEIGHT:-0}
    fi
    echo "$ax $ay ${w:-0} ${h:-0}"
}

# Window decoration height. Always 0: xwininfo's "Absolute upper-left" already
# points at the client-area origin on a reparenting WM, so there is no title bar
# left to skip. Ported from draw-qa.sh _detect_decoration_height. Override with
# DECORATION_H=<physical px> for a WM where xwininfo reports the frame instead.
driver_detect_decoration_height() { echo 0; }

driver_offscreen_available() { command -v xvfb-run &>/dev/null && command -v Xvfb &>/dev/null; }

# driver_run_offscreen <cmd...> — run a command under a virtual X display.
# WAYLAND_DISPLAY MUST be unset, or spectacle captures the real desktop and every
# region diff compares a static wrong frame (capture-backend rule). The Xvfb
# screen must match what the app expects (an app that derives its size from the
# screen needs the right res). Ported from draw-qa.sh's Xvfb self-wrap.
driver_run_offscreen() {
    local res="${QA_XVFB_RES:-}"
    if [[ -z "$res" ]]; then
        command -v xdotool &>/dev/null && res=$(xdotool getdisplaygeometry 2>/dev/null) && res="${res// /x}"
        [[ -z "$res" ]] && res="1920x1080"
    fi
    env -u WAYLAND_DISPLAY xvfb-run -a --server-args="-screen 0 ${res}x24" "$@"
}
