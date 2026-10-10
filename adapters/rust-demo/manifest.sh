#!/usr/bin/env bash
# rust-demo adapter — adapter #2, proving the linux-x11 driver + core run against
# a second app in a second language with NO viewport model (unlike DRAW). This is
# the whole integration: ~30 lines, because the demo is a plain window-relative
# GUI. See examples/rust-demo/ for the app.

# ── 1. Identity ──────────────────────────────────────────────────────────────
ADAPTER_NAME="rust-demo"
# Tests live beside this manifest.
ADAPTER_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests"
ADAPTER_APP_ROOT="${QA_HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/examples/rust-demo"

_RD_BIN="${QA_HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/examples/rust-demo/target/release/qa-demo"
_RD_TITLE="qa-demo"

# ── 2. Launch / quit ─────────────────────────────────────────────────────────
adapter_launch() {
    local timeout=${1:-15}
    [[ -x "$_RD_BIN" ]] || { echo "rust-demo: build it first: (cd examples/rust-demo && cargo build --release)" >&2; return 1; }
    "$_RD_BIN" >/dev/null 2>"${QA_RD_STDERR:-/dev/null}" &
    ADAPTER_PID=$!
    # Wait for the window to appear (title match), up to timeout.
    local t=0
    while (( t < timeout * 10 )); do
        xdotool search --name "$_RD_TITLE" >/dev/null 2>&1 && return 0
        # portable 0.1s wait without foreground sleep restrictions
        read -rt 0.1 <> <(:) 2>/dev/null || true
        t=$(( t + 1 ))
    done
    echo "rust-demo: window '$_RD_TITLE' did not appear within ${timeout}s" >&2
    return 1
}

adapter_quit() {
    [[ -n "${ADAPTER_PID:-}" ]] && kill "$ADAPTER_PID" 2>/dev/null
    # reap stragglers by name (belt and suspenders)
    pkill -x qa-demo 2>/dev/null || true
    ADAPTER_PID=""
}

# ── 3. Window match — by title (no window id needed) ─────────────────────────
adapter_window_bounds() {
    driver_window_bounds_by_title "$_RD_TITLE" "${ADAPTER_PID:-}"
}

# ── 4. Logical → screen — window-relative, 1:1 (the DEFAULT; no viewport) ─────
# This is the whole point of adapter #2: a plain app needs no geometry model, so
# logical coords are just window-origin offsets. Contrast DRAW's viewport×scale.
adapter_to_screen() {
    local lx=$1 ly=$2 wx wy _w _h
    read -r wx wy _w _h < <(adapter_window_bounds)
    echo "$(( wx + lx )) $(( wy + ly ))"
}

# ── 5. Blessed config — none (the demo has no config) ────────────────────────
ADAPTER_CONFIG=""
adapter_ensure_config() { : ; }

# ── 6. Lifecycle hooks ───────────────────────────────────────────────────────
adapter_is_alive()     { [[ -n "${ADAPTER_PID:-}" ]] && kill -0 "$ADAPTER_PID" 2>/dev/null; }
adapter_crashlog_dir() { echo ""; }          # no crash log

# Focus/raise the window before input & capture. Under a WM-less Xvfb (the
# offscreen/CI path) nothing sets input focus, so keystrokes and even clicks
# never reach the window until we XSetInputFocus it — hence windowfocus --sync.
# (SDL2 apps like DRAW grab focus on creation; a plain minifb window does not.)
_rd_wid() { xdotool search --name "$_RD_TITLE" 2>/dev/null | head -1; }
adapter_focus() {
    local w; w=$(_rd_wid); [[ -n "$w" ]] || return 0
    xdotool windowfocus --sync "$w" 2>/dev/null || xdotool windowfocus "$w" 2>/dev/null || true
    xdotool windowraise "$w" 2>/dev/null || true
}
adapter_pre_input()    { adapter_focus; }    # focus before every dispatched click/key
adapter_park_window()  { : ; }               # not needed; bounds come from xdotool
