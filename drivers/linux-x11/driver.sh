#!/usr/bin/env bash
# linux-x11 driver — the ONLY OS-specific layer. Input via xdotool (XTEST),
# capture via spectacle (Wayland) / scrot (X11 & Xvfb), window bounds via
# xwininfo, offscreen via Xvfb. Bodies port from DRAW/QA/draw-qa.sh (noted per
# function). The core and adapters call ONLY these driver_* verbs.
#
# Contract implemented here: see ARCHITECTURE.md → "The driver interface".

# ── input (screen coords already resolved by the adapter) ────────────────────
driver_input_move()   { xdotool mousemove -- "$1" "$2"; }
driver_input_button() { # down|up|click  1|2|3
    case "$1" in
        down)  xdotool mousedown "$2" ;;
        up)    xdotool mouseup   "$2" ;;
        click) xdotool click     "$2" ;;
    esac
}
# key/type: PORT the SDL2-safe chord handling (hold mods, tap base) from draw-qa.sh
driver_input_key()    { xdotool key --clearmodifiers -- "$1"; }   # TODO: port chord logic
driver_input_type()   { xdotool type -- "$1"; }
driver_input_scroll() { local n=${2:-1}; local b; [[ "$1" == up ]] && b=4 || b=5; \
                        while ((n--)); do xdotool click "$b"; done; }

# ── capture (full display; core crops regions) ───────────────────────────────
# PORT _capture_client_area's backend selection: WAYLAND_DISPLAY set → spectacle,
# else scrot; QA_CAPTURE overrides; scrot last-ditch fallback.
driver_capture_full() {
    local out=$1 backend="${QA_CAPTURE:-}"
    if [[ -z "$backend" ]]; then
        [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v spectacle &>/dev/null \
            && backend=spectacle || backend=scrot
    fi
    case "$backend" in
        spectacle) setsid spectacle -b -n -f -o "$out" 2>/dev/null ;;
        scrot)     scrot "$out" 2>/dev/null ;;
        *)         "$backend" "$out" 2>/dev/null ;;
    esac
    [[ -s "$out" ]] || scrot "$out" 2>/dev/null
}

# ── target / lifecycle ───────────────────────────────────────────────────────
# → "X Y W H". Degrade: title → pid → geometry. PORT _update_win_pos math.
driver_window_bounds_by_title() {
    local wid; wid=$(xdotool search --name "$1" 2>/dev/null | head -1) || return 1
    [[ -n "$wid" ]] || return 1
    eval "$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null)"
    echo "${X:-0} ${Y:-0} ${WIDTH:-0} ${HEIGHT:-0}"
}
driver_offscreen_available() { command -v xvfb-run &>/dev/null && command -v Xvfb &>/dev/null; }
# PORT the self-wrap: WAYLAND_DISPLAY unset, QA_IN_XVFB guard, screen res.
driver_run_offscreen() {
    local res="${QA_XVFB_RES:-1920x1080}"
    env -u WAYLAND_DISPLAY xvfb-run -a --server-args="-screen 0 ${res}x24" "$@"
}
