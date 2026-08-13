#!/usr/bin/env bash
# kaleidotron adapter — Rust/egui pixel-art browser (~/git/kaleidotron).
#
# Adapter #3. Like rust-demo it is window-relative 1:1 with NO viewport model, so
# the coordinate map is three lines. The one job with real content here is STATE
# ISOLATION: unlike the demo, kaleidotron persists a lot (window geometry, egui
# state, settings.json, a ratings sidecar, a view-history SQLite db), and it does
# so under the XDG dirs. Left alone it would both drift between runs and scribble
# on the developer's real config.
#
# Window matching is unambiguous here: eframe → winit sets _NET_WM_PID and
# WM_CLASS, so `xdotool search --pid` genuinely filters. That means this adapter
# does NOT inherit DRAW's stale-window race (see ARCHITECTURE.md) and needs no
# `settle` helper — but keep the pid in the search so a stray instance of the
# developer's own kaleidotron can never be picked up instead.

# ── 1. Identity ──────────────────────────────────────────────────────────────
ADAPTER_NAME="kaleidotron"
ADAPTER_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests"

_KT_ROOT="${KALEIDOTRON_ROOT:-$HOME/git/kaleidotron}"
_KT_BIN="$_KT_ROOT/target/release/kaleidotron"
# The window title is "kaleidotron — <path> (<zoom>%)" (update_window_title), so
# this is a PREFIX match. xdotool --name takes a regex and matches substrings,
# which is what we want: the path changes as tests navigate.
_KT_TITLE="kaleidotron"
_KT_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures"

# The app's default window size (src/main.rs), and therefore the coordinate space
# every test writes against. Exported so tests can centre things without
# hard-coding, and so a future resize test has something to compare to.
KT_WIN_W=1100
KT_WIN_H=760

# ── 2. Blessed config — a wiped sandbox HOME, re-made every launch ───────────
# kaleidotron writes to eframe's storage_dir (XDG_DATA_HOME/kaleidotron: app.ron,
# settings.json, ratings.json, views.db, themes/, tasks/) and remembers window
# geometry + the last folder. Two consequences for QA:
#   * without isolation a run would inherit the developer's panel layout, theme,
#     thumbnail size and last folder — none of which are the defaults the tests
#     were calibrated against;
#   * and it would WRITE there, so running the suite would rearrange their app.
# Wiping per launch (not per run) is deliberate — the core calls this before
# every test file, which is exactly the "re-assert the blessed config every
# launch" rule in ARCHITECTURE.md. kaleidotron saves its live state on exit, so
# caching the sandbox would let test N's window size leak into test N+1.
_KT_SANDBOX="${QA_RESULTS_DIR:-/tmp}/kaleidotron-qa-home"
ADAPTER_CONFIG="$_KT_SANDBOX"

adapter_ensure_config() {
    rm -rf "$_KT_SANDBOX"
    mkdir -p "$_KT_SANDBOX"/{config,data,cache}
}

# ── 3. Launch / quit ─────────────────────────────────────────────────────────
adapter_launch() {
    local timeout=${1:-15}
    [[ -x "$_KT_BIN" ]] || {
        echo "kaleidotron: build it first: (cd $_KT_ROOT && cargo build --release)" >&2
        return 1
    }
    # HOME as well as the XDG vars: `directories` falls back to $HOME when an XDG
    # var is unset, and some paths (rfd dialogs, ~/.config) read HOME directly.
    HOME="$_KT_SANDBOX" \
    XDG_CONFIG_HOME="$_KT_SANDBOX/config" \
    XDG_DATA_HOME="$_KT_SANDBOX/data" \
    XDG_CACHE_HOME="$_KT_SANDBOX/cache" \
        "$_KT_BIN" --folder "$_KT_FIXTURES" >/dev/null 2>"${QA_KT_STDERR:-/dev/null}" &
    ADAPTER_PID=$!

    local t=0
    while (( t < timeout * 10 )); do
        if xdotool search --pid "$ADAPTER_PID" --name "$_KT_TITLE" >/dev/null 2>&1; then
            # The window being mapped is not the same as it being ready for input:
            # winit maps early, and the first frame (fonts, thumbnail decode) lands
            # a beat later. Without this the first click of a test can land on an
            # unpainted grid and select nothing.
            read -rt 0.6 <> <(:) 2>/dev/null || true
            return 0
        fi
        read -rt 0.1 <> <(:) 2>/dev/null || true
        t=$(( t + 1 ))
    done
    echo "kaleidotron: window '$_KT_TITLE' did not appear within ${timeout}s" >&2
    return 1
}

adapter_quit() {
    [[ -n "${ADAPTER_PID:-}" ]] && kill "$ADAPTER_PID" 2>/dev/null
    ADAPTER_PID=""
    # Deliberately NOT `pkill -x kaleidotron`: the developer runs this app, and a
    # blanket pkill would kill their session's instance mid-edit. The pid is
    # reliable here (winit sets _NET_WM_PID), so it is all we need.
}

# ── 4. Window match — by title, filtered by pid ──────────────────────────────
adapter_window_bounds() {
    driver_window_bounds_by_title "$_KT_TITLE" "${ADAPTER_PID:-}"
}

# ── 5. Logical → screen — window-relative, 1:1 ──────────────────────────────
# Offscreen Xvfb is 1×, and kaleidotron's egui zoom_factor defaults to 1.0 in a
# fresh sandbox, so logical coords are plain window-origin offsets. If an
# onscreen HiDPI run ever comes out scaled, that is where to look: the app has
# its own persisted ui_zoom, which the wiped sandbox pins to the default.
adapter_to_screen() {
    local lx=$1 ly=$2 wx wy _w _h
    read -r wx wy _w _h < <(adapter_window_bounds)
    echo "$(( wx + lx )) $(( wy + ly ))"
}
# Tests that drop to raw driver calls use this name directly — see the `_abs`
# lesson in ARCHITECTURE.md. Keep the alias even if no test uses it yet.
_kt_abs() { adapter_to_screen "$@"; }

# ── 6. Lifecycle hooks ───────────────────────────────────────────────────────
_kt_wid() { xdotool search --pid "${ADAPTER_PID:-0}" --name "$_KT_TITLE" 2>/dev/null | head -1; }

adapter_focus() {
    local w; w=$(_kt_wid); [[ -n "$w" ]] || return 0
    xdotool windowfocus --sync "$w" 2>/dev/null || xdotool windowfocus "$w" 2>/dev/null || true
    xdotool windowraise "$w" 2>/dev/null || true
}
adapter_pre_input()    { adapter_focus; }
adapter_is_alive()     { [[ -n "${ADAPTER_PID:-}" ]] && kill -0 "$ADAPTER_PID" 2>/dev/null; }
adapter_park_window()  { : ; }   # bounds come from xdotool; nothing to park
adapter_crashlog_dir() { echo ""; }   # no crash log; a panic just kills the process
