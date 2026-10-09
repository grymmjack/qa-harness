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
# Atomic press/release WITH pointer motion in one XTEST batch. SDL2 reliably
# registers button events that carry motion, so DRAW sees a real drag-start;
# splitting the press and the move into two calls can read as a click without
# motion (e.g. auto-add-layer paint then gets REFUSED). Mirrors draw-qa.sh's
# `xdotool mousedown "$btn" mousemove …`. Used by the core drag verb.
driver_input_button_move() { # down|up  btn  [x y]
    case "$1" in
        down)  xdotool mousedown "$2" mousemove "$3" "$4" ;;
        up)    xdotool mouseup   "$2" ;;
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
# Hold ONE key down, or release it — for modifier-held-during-mouse gestures
# (Ctrl+click, Shift+drag, …). No --window: XTEST so SDL2 sees real physical key
# state (SDL_GetKeyboardState / _KEYDOWN), same reason driver_input_key avoids it.
driver_input_key_hold() { # down|up  <keyname e.g. ctrl shift alt super>
    case "$1" in
        down) xdotool keydown "$2" ;;
        up)   xdotool keyup   "$2" ;;
    esac
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
# ── window handles (the adapter keeps one per app instance) ─────────────────
# driver_window_find PID TITLE → handle ("" = none). With a PID only that
# process's windows match; without one, any window with the title.
driver_window_find() {
    if [[ -n "${1:-}" ]]; then
        xdotool search --pid "$1" --name "$2" 2>/dev/null | head -1
    else
        xdotool search --name "$2" 2>/dev/null | head -1
    fi
}
driver_window_title()    { xdotool getwindowname "$1" 2>/dev/null; }          # H → title (fails if gone)
driver_window_activate() { xdotool windowactivate --sync "$1" 2>/dev/null; xdotool windowfocus --sync "$1" 2>/dev/null; return 0; }
driver_window_ready()    { return 0; }   # macOS-only need (see drivers/macos)
driver_window_bounds() {  # H → "X Y W H" (frame geometry as the WM reports it)
    local X Y WIDTH HEIGHT
    eval "$(xdotool getwindowgeometry --shell "$1" 2>/dev/null)"
    echo "${X:-0} ${Y:-0} ${WIDTH:-0} ${HEIGHT:-0}"
}
driver_window_key() { xdotool key --window "$1" "$2" 2>/dev/null; }          # H COMBO → sent to that window

# ── raw input (screen coords) ────────────────────────────────────────────────
driver_input_move_rel() { xdotool mousemove_relative -- "$1" "$2" 2>/dev/null; }
# driver_input_seq TOKENS… — an input sequence as ONE atomic batch, for timing-
# critical gestures (a key tapped while the mouse moves mid-drag). Neutral
# mini-language: move X Y | moverel DX DY | down B | up B | key K | keydown K | keyup K.
# X11 sends it as a single xdotool call; drivers without batching run it in order.
driver_input_seq() {
    local a=()
    while (( $# )); do
        case "$1" in
            move)    a+=(mousemove "$2" "$3"); shift 3 ;;
            moverel) a+=(mousemove_relative -- "$2" "$3"); shift 3 ;;
            down)    a+=(mousedown "$2"); shift 2 ;;
            up)      a+=(mouseup "$2"); shift 2 ;;
            key)     a+=(key "$2"); shift 2 ;;
            keydown) a+=(keydown "$2"); shift 2 ;;
            keyup)   a+=(keyup "$2"); shift 2 ;;
            *) echo "driver_input_seq: unknown token '$1'" >&2; return 2 ;;
        esac
    done
    xdotool "${a[@]}"
}

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

# physical pixels per point of the main screen (macOS Retina = 2)
driver_backing_scale() { echo 1; }

driver_offscreen_available() { command -v xvfb-run &>/dev/null && command -v Xvfb &>/dev/null; }

# driver_run_offscreen <cmd...> — run a command under a virtual X display.
# WAYLAND_DISPLAY MUST be unset, or spectacle captures the real desktop and every
# region diff compares a static wrong frame (capture-backend rule). The Xvfb
# screen must match what the app expects (an app that derives its size from the
# screen needs the right res). Ported from draw-qa.sh's Xvfb self-wrap.
#
# A lightweight window manager (openbox) is started INSIDE the Xvfb session when
# available. This is HARNESS-WIDE, not per-app: it lives in the driver because a
# WM is an OS/environment concern shared by every adapter. Bare Xvfb has no WM, so
# a dying app window is not reaped promptly and input focus is never assigned —
# which breaks any test that quits+relaunches the app mid-file: the relaunch binds
# the previous instance's still-mapped window (apps like SDL2/QB64-PE set no
# _NET_WM_PID, so xdotool can't tell two same-title windows apart). With a WM the
# old window is torn down and focus follows the new one, so offscreen matches
# onscreen (the default — a real desktop always has a WM).
#
# Knobs (env):
#   QA_OFFSCREEN_WM=none         disable the WM entirely (bare Xvfb, the old
#                                behaviour) — the harness still runs, minus
#                                mid-relaunch reliability.
#   QA_OFFSCREEN_WM=<name>       use a different WM binary (e.g. blackbox, twm).
#                                It is invoked as `<name> --sm-disable [--config-
#                                file <rc>]`; a WM that doesn't take those flags
#                                needs its own launch tweak here.
#   QA_OFFSCREEN_WM_RC=<file>    override the openbox config. The bundled
#                                openbox-rc.xml UNDECORATES every window so region
#                                geometry is pixel-identical to bare Xvfb — the
#                                right default for exact region-diffing. An adapter
#                                that WANTS real title bars / decorations (to test
#                                them) points this at its own rc. Only consumed by
#                                openbox-compatible WMs.
driver_run_offscreen() {
    local res="${QA_XVFB_RES:-}"
    if [[ -z "$res" ]]; then
        command -v xdotool &>/dev/null && res=$(xdotool getdisplaygeometry 2>/dev/null) && res="${res// /x}"
        # no display to copy (over SSH): big enough for a 2x-scaled QA geometry -
        # apps cap their window to a share of the screen (DRAW: 90%), so 1920x1080
        # made DRAW's 958x514@2x window 1728x972 and the run refused to start
        [[ -z "$res" ]] && res="3840x2160"
    fi
    local wm="${QA_OFFSCREEN_WM:-openbox}"
    # Respect a caller-supplied rc; otherwise use the bundled undecorated one.
    local rc="${QA_OFFSCREEN_WM_RC:-${BASH_SOURCE%/*}/openbox-rc.xml}"
    export QA_OFFSCREEN_WM="$wm" QA_OFFSCREEN_WM_RC="$rc"
    # Start the WM inside the just-created Xvfb, then exec the real command in the
    # same X server. $DISPLAY is set by xvfb-run before this inner shell runs.
    env -u WAYLAND_DISPLAY xvfb-run -a --server-args="-screen 0 ${res}x24" \
        bash -c '
            if [ "${QA_OFFSCREEN_WM}" != none ] && command -v "${QA_OFFSCREEN_WM}" >/dev/null 2>&1; then
                if [ -f "${QA_OFFSCREEN_WM_RC}" ]; then
                    "${QA_OFFSCREEN_WM}" --sm-disable --config-file "${QA_OFFSCREEN_WM_RC}" >/dev/null 2>&1 &
                else
                    "${QA_OFFSCREEN_WM}" --sm-disable >/dev/null 2>&1 &
                fi
                # Give the WM a beat to own the root window before the app maps.
                for _i in 1 2 3 4 5 6 7 8 9 10; do
                    xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1 && break
                    sleep 0.1
                done
            fi
            exec "$@"
        ' bash "$@"
}
