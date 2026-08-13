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
_KT_FIXTURES_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures"

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
    mkdir -p "$_KT_SANDBOX/data/kaleidotron"
    # The blessed config. Only three things are pinned, and each removes a source
    # of drift rather than expressing a preference:
    #
    #   plugin_code   ON  — source/text is a format PLUGIN and ships OFF, so .bas
    #                       fixtures would not even be listed. Tests that need it
    #                       must still call kt_refresh (see below).
    #   git_enabled   OFF — the fixtures live inside a git repo, so tiles would
    #                       carry a git badge whose colour depends on whether the
    #                       fixtures happen to be committed.
    #   osd_enabled   OFF — the metadata OSD fades in over the viewer for several
    #                       seconds after every open. A fading overlay under a
    #                       region diff is a race, and turning it off is far more
    #                       robust than timing around it.
    #
    # Deliberately NOT pinned: thumb_size, ui_zoom, theme. They are already at
    # their defaults in a wiped sandbox, and setting thumb_size in particular
    # RESIZES EVERY TILE and invalidates every calibrated coordinate in the suite.
    cat > "$_KT_SANDBOX/data/kaleidotron/settings.json" <<'JSON'
{
  "plugins": { "plugin_code": true },
  "paths":   { "git_enabled": false },
  "viewer":  { "osd_enabled": false }
}
JSON

    # The FIXTURES are copied into the sandbox too, and the app is pointed at the
    # copy — the XDG dirs are not the only place this app writes.
    #
    # A star rating on an on-disk file is stored as a `user.baloo.rating` XATTR on
    # that file (the KDE/Baloo scheme, so it interoperates with Gwenview). So a
    # run of the rating test wrote a rating onto the fixture in the repository,
    # where it survived the sandbox wipe: later runs then started from a
    # pre-rated tile, and a stray keypress in an early draft of the viewer test
    # left a permanent 1-star on 01-red.png. Isolating the XDG dirs is not enough
    # when the app's state model includes the files themselves.
    #
    # Copying also means a test may freely rename, trash or create files.
    rm -rf "$_KT_FIXTURES"
    mkdir -p "$_KT_FIXTURES"
    # -L dereferences, --no-preserve=xattr drops any rating that leaked onto the
    # source before this was fixed, so a stale xattr cannot resurrect itself.
    cp -L --no-preserve=xattr "$_KT_FIXTURES_SRC"/* "$_KT_FIXTURES"/ 2>/dev/null || true
}

# Where the app is actually pointed: a throwaway copy, never the repo's originals.
_KT_FIXTURES="$_KT_SANDBOX/fixtures"

# ── 3. Launch / quit ─────────────────────────────────────────────────────────
adapter_launch() {
    local timeout=${1:-15}
    [[ -x "$_KT_BIN" ]] || {
        echo "kaleidotron: build it first: (cd $_KT_ROOT && cargo build --release)" >&2
        return 1
    }
    # HOME as well as the XDG vars: `directories` falls back to $HOME when an XDG
    # var is unset, and some paths (rfd dialogs, ~/.config) read HOME directly.
    #
    # WAYLAND_DISPLAY is unset whenever we are targeting an X display. kaleidotron
    # is winit, and winit PREFERS WAYLAND whenever WAYLAND_DISPLAY is set: it will
    # ignore DISPLAY and open a real window on the developer's actual compositor,
    # while every xdotool search against the X display finds nothing. The driver's
    # offscreen wrapper already unsets it, so this is belt-and-braces for anyone
    # invoking the adapter outside that wrapper — but it is the difference between
    # "invisible" and "a window appears on someone's screen mid-run", so it is
    # asserted here too rather than assumed of the caller.
    env -u WAYLAND_DISPLAY \
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

# ── 5b. kt_refresh — re-scan the current folder from disk ───────────────────
# F5. No longer needed to make settings.json apply: kaleidotron used to scan the
# launch folder BEFORE reading settings.json, so a plugin enabled in that file
# left its formats missing from the grid until the user refreshed. The QA suite
# hit that immediately and it was fixed upstream — the listing now honours
# settings.json on the first frame, which `formats.sh` asserts directly.
#
# Kept for what it is actually for: a test that changes something on disk and
# needs the listing to catch up.
kt_refresh() {
    key F5
    wait_for 1.0 "re-scan the folder from disk"
}

# ── 5c. kt_hover — move the pointer without clicking ────────────────────────
# The core's input verbs all click, drag or type; there is no "just hover". But
# hover IS behaviour in this app — the grid rates the tile under the cursor, and
# a hovered tile highlights and can start playing an animation — so a test needs
# to place the pointer and assert on the result. This is the `_abs` pattern from
# ARCHITECTURE.md: a test dropping to a raw driver call gets its screen coords
# from the adapter's own logical->screen helper, by name.
kt_hover() {
    local sx sy
    read -r sx sy <<< "$(adapter_to_screen "$1" "$2")"
    driver_input_move "$sx" "$sy"
    sleep 0.1
}

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
