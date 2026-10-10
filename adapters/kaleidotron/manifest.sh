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
ADAPTER_APP_ROOT="$_KT_ROOT"        # the checkout under test (bin/qa-dash shows its branch)
# known failures / dashboard target: known-failures.txt, qa-target.txt beside tests/
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
    #   the plugins   ON  — every format plugin (code, pdf, audio, 3d, video)
    #                       ships OFF, so their fixtures would not even be listed.
    #                       Enabling them here is what makes the plugin formats
    #                       testable at all; the app applies settings.json BEFORE
    #                       the first scan (a bug this suite found and got fixed),
    #                       so they appear on the first frame with no refresh.
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
  "plugins": {
    "plugin_code": true,
    "plugin_pdf": true,
    "plugin_audio": true,
    "plugin_3d": true,
    "plugin_video": true
  },
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
    rm -rf "$_KT_FIXTURES" "$_KT_NAV"
    mkdir -p "$_KT_FIXTURES" "$_KT_NAV"
    # -L dereferences, --no-preserve=xattr drops any rating that leaked onto the
    # source before this was fixed, so a stale xattr cannot resurrect itself.
    # `src/.` not `src/*`: the glob does NOT match dotfiles, and the fixtures carry
    # a `.vscode/tasks.json` that the project-tasks feature is discovered through.
    # With the glob, calibration (which points at the real directory) saw the Run
    # menu and the test (which runs against this copy) did not — the tasks simply
    # were not there.
    cp -RL --no-preserve=xattr "$_KT_FIXTURES_SRC"/. "$_KT_FIXTURES"/ 2>/dev/null || true
    cp -RL --no-preserve=xattr "$_KT_NAV_SRC"/. "$_KT_NAV"/ 2>/dev/null || true
    rm -rf "$_KT_TASKS"; mkdir -p "$_KT_TASKS"
    cp -RL --no-preserve=xattr "$_KT_TASKS_SRC"/. "$_KT_TASKS"/ 2>/dev/null || true
    rm -rf "$_KT_PLUGINS"; mkdir -p "$_KT_PLUGINS"
    cp -RL --no-preserve=xattr "$_KT_PLUGINS_SRC"/. "$_KT_PLUGINS"/ 2>/dev/null || true
}

# Where the app is actually pointed: a throwaway copy, never the repo's originals.
_KT_FIXTURES="$_KT_SANDBOX/fixtures"

# A SECOND fixture set, holding the things a navigation test needs: a subfolder
# and an archive. Kept out of the main folder on purpose — folders and archives
# sort FIRST (dirs-first is on by default and lives in eframe storage, not
# settings.json, so it cannot be pinned from the blessed config), so putting them
# beside the images would shift every tile and invalidate the coordinates in all
# the other tests. Tests reach it with `kt_goto`.
_KT_NAV_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures-nav"
_KT_NAV="$_KT_SANDBOX/fixtures-nav"

# A THIRD set, for the format PLUGINS (PDF, video, 3D, audio, fonts, PSD). Also
# kept separate, for the same coordinate-stability reason — and because these are
# the heaviest decode paths, so a test that does not need them should not pay for
# them on every launch.
_KT_PLUGINS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures-plugins"
_KT_PLUGINS="$_KT_SANDBOX/fixtures-plugins"

# A FOURTH set, carrying a `.vscode/tasks.json`. Also separate, and for a reason
# worth recording: a discovered tasks.json adds a "▶ Tasks" entry to the TOP of
# every file's context menu, which shifted every other entry down ~30px and broke
# the calibrated coordinates in `fileops` and `compare`. A fixture that changes
# the shape of a menu cannot live in the folder other tests measure.
_KT_TASKS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures-tasks"
_KT_TASKS="$_KT_SANDBOX/fixtures-tasks"

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

# ── 5d. kt_goto — navigate to an absolute path via the breadcrumb path editor ─
# The ✎ button at the left of the breadcrumb bar swaps it for a text field. This
# is how a test reaches a folder that is not reachable by clicking a tile — the
# navigation fixtures live outside the browsed folder precisely so they cannot
# disturb its layout.
kt_goto() {
    click 69 33
    wait_for 0.4 "path editor open"
    # The field opens PRE-FILLED with the current folder and focused, so typing
    # appends to it and Enter then navigates to a path that does not exist —
    # silently leaving the app exactly where it was. Select-all first so the typed
    # path replaces rather than extends it.
    key ctrl+a
    type_text "$1"
    key Return
    wait_for 1.5 "navigated to $1"
}

# ── 5d2. kt_mouse_nav — the back/forward thumb buttons ──────────────────────
# The core's input verbs cover buttons 1-3 (left/middle/right); the browser-style
# side buttons are 8 and 9 and have no verb, so this is another `_abs`-pattern
# drop to a raw driver call. kaleidotron binds them to its folder history.
# ── 5d3. kt_ctrl_wheel — a modifier held ACROSS a wheel gesture ─────────────
# Ctrl+wheel is kaleidotron's thumbnail-size zoom, and it cannot be assembled
# from the core verbs. Two reasons, both learned by getting it wrong:
#   * `scroll_up` takes LOGICAL COORDS (x y), not a tick count — `scroll_up 4`
#     silently scrolls at x=4 rather than four notches;
#   * every core input verb calls `adapter_pre_input` first, which focuses the
#     window, and that drops a modifier held by a separate `xdotool keydown`.
# So the whole gesture goes to xdotool in ONE invocation, with nothing in between
# to disturb the held key.
#
# This also exercises something a mocked input could not: egui pre-classifies
# Ctrl+wheel as a ZOOM event, so it never appears in the scroll deltas at all.
kt_ctrl_wheel() {   # x y up|down [ticks]
    local lx=$1 ly=$2 dir=$3 ticks=${4:-3} sx sy btn args=()
    read -r sx sy <<< "$(adapter_to_screen "$lx" "$ly")"
    [[ "$dir" == up ]] && btn=4 || btn=5
    adapter_focus
    args=(mousemove "$sx" "$sy" keydown ctrl)
    while (( ticks-- > 0 )); do args+=(click "$btn"); done
    args+=(keyup ctrl)
    xdotool "${args[@]}"
    sleep 0.3
}

# ── 5d4. kt_click_raw — click WITHOUT the focus/raise that precedes core input ─
# Every core input verb calls `adapter_pre_input` first, which does
# `windowfocus --sync` + `windowraise`. That is exactly right for ordinary input
# under a WM-less Xvfb — and wrong once a POPUP is open, because raising the
# window can dismiss it, so the click then lands on whatever is underneath.
# Use this for the second click of an open-menu-then-choose gesture.
kt_click_raw() {
    local sx sy
    read -r sx sy <<< "$(adapter_to_screen "$1" "$2")"
    xdotool mousemove "$sx" "$sy" click 1
    sleep 0.25
}

kt_mouse_back()    { xdotool click 8; sleep 0.2; }
kt_mouse_forward() { xdotool click 9; sleep 0.2; }

# ── 5e. kt_assert_dominant — assert which channel a region is mostly made of ──
# The core asserts that two regions DIFFER; it has no vocabulary for what a
# region actually looks like. Some claims need that: the binary text-mode
# formats store raw VGA attribute bytes, where 4 is RED — but 4 is BLUE in the
# ANSI SGR ordering used by .ans, and mixing the two silently swaps red and blue
# across a whole piece (the historical MULTI-13.BIN bug). "It changed" cannot
# catch that; "it is red" can.
#
# Averages the region to a single pixel and compares channels. Reports through
# the core's pass/fail so it lands in the run's tally like any other assertion.
kt_assert_dominant() {
    local png=$1 want=$2 msg=$3 margin=${4:-12} r g b got hi lo
    read -r r g b < <(magick "$png" -resize 1x1\! -format '%[fx:int(255*r)] %[fx:int(255*g)] %[fx:int(255*b)]' info: 2>/dev/null)
    [[ -z "${r:-}" ]] && { fail "$msg — could not read the region's colour"; return 1; }
    if   (( r >= g && r >= b )); then got=r; hi=$r
    elif (( g >= r && g >= b )); then got=g; hi=$g
    else got=b; hi=$b
    fi
    lo=$r; (( g < lo )) && lo=$g; (( b < lo )) && lo=$b
    # A near-grey region has no dominant channel, and the comparison above would
    # pick one anyway on a rounding difference. This is not pedantry: a thumbnail
    # that has not decoded yet paints a grey SPINNER, which is emphatically "not
    # blank" — so a plain differs-from-blank check passes on a tile that never
    # rendered. Two of these fixtures span forever and were passing exactly that
    # way, which is how a real decoder bug (.tga has no magic bytes, so it could
    # never decode at all) sat here unnoticed.
    if (( hi - lo < margin )); then
        fail "$msg — region is near-grey (rgb ${r},${g},${b}), which is what an undecoded, still-spinning tile looks like"
        return 1
    fi
    if [[ "$got" == "$want" ]]; then
        pass "$msg (mean rgb ${r},${g},${b} — ${want} dominates)"
    else
        fail "$msg — expected ${want} to dominate, got ${got} (mean rgb ${r},${g},${b})"
    fi
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
