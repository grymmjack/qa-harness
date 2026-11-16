#!/usr/bin/env bash
# drawy adapter — KDE Drawy (Qt6/KF6 whiteboard), built and run inside a podman
# container because it needs newer Qt/KF6 than the host has. The container shares
# the host's /tmp/.X11-unix, so the app draws on whatever X display the core is
# using (normally the offscreen Xvfb) while input and capture stay on the host.
#
# Setup (once):
#   podman run -d --name drawy-build --userns=keep-id \
#       -v ~/git/drawy:/src -v /tmp/.X11-unix:/tmp/.X11-unix:ro -w /src <image> sleep infinity
#   podman exec drawy-build cmake --build /src/build-arch
#
# Coordinates: logical = window-client-relative = canvas view pixels. At the
# default zoom (100%) and scroll offset (0,0) that is also the world (canvas)
# coordinate, so tests can reason about grid positions directly.
#
# Per-test settings: a test may declare lines such as
#   # QA-DRAWYRC: Grid/SnapToGrid=true
# which are written into the isolated drawyrc before launch (group/key=value).
#
# Drawy's data (e.g. the handwriting recognition model) lives in an isolated,
# empty data dir too. A test that needs the model declares
#   # QA-DRAWY-MODEL: installed
# and it is copied in from $DRAWY_ROOT/.cache/models before launch.

ADAPTER_NAME="drawy"
ADAPTER_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests"
ADAPTER_APP_ROOT="${DRAWY_ROOT:-$HOME/git/drawy}"

_DW_CONTAINER="${DRAWY_CONTAINER:-drawy-build}"
_DW_BIN="${DRAWY_BIN:-/src/build-arch/bin/drawy}"
_DW_CFG_DIR="/tmp/drawy-qa-config"          # inside the container
_DW_DATA_DIR="/tmp/drawy-qa-data"           # inside the container
_DW_MODEL="PP-OCRv6_rec_small.onnx"
_DW_WIN_W=1500
_DW_WIN_H=900
_DW_EXTRA_RC=""                              # filled by adapter_pre_launch

_dw_exec() { podman exec "$_DW_CONTAINER" "$@"; }
_dw_wait() { read -rt "$1" <> <(:) 2>/dev/null || true; }
_dw_wid()  { xdotool search --class '^drawy$' 2>/dev/null | tail -1; }

# ── 2. Launch / quit ─────────────────────────────────────────────────────────
adapter_launch() {
    local timeout=${1:-15}
    _dw_exec test -x "$_DW_BIN" || { echo "drawy: build it first ($_DW_BIN missing in $_DW_CONTAINER)" >&2; return 1; }

    # Hand the X cookie to the container as a wildcard entry: the container's
    # hostname differs from ours, so a host-bound entry would not match.
    _dw_exec rm -f /tmp/qa-xauth
    if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
        xauth -f "$XAUTHORITY" nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' \
            | podman exec -i "$_DW_CONTAINER" xauth -f /tmp/qa-xauth nmerge - 2>/dev/null
    fi

    podman exec -d -e DISPLAY="$DISPLAY" -e XAUTHORITY=/tmp/qa-xauth -e XDG_CONFIG_HOME="$_DW_CFG_DIR" -e XDG_DATA_HOME="$_DW_DATA_DIR" \
        -e QT_QPA_PLATFORM=xcb -e QT_LOGGING_RULES='*.debug=false' \
        "$_DW_CONTAINER" bash -c "exec $_DW_BIN > /tmp/drawy-qa.log 2>&1"

    local t=0 wid=""
    while (( t < timeout * 10 )); do
        wid=$(_dw_wid); [[ -n "$wid" ]] && break
        _dw_wait 0.1; t=$(( t + 1 ))
    done
    [[ -n "$wid" ]] || { echo "drawy: window did not appear within ${timeout}s" >&2; return 1; }

    # Pin the geometry so every coordinate in the tests is deterministic.
    xdotool windowsize "$wid" "$_DW_WIN_W" "$_DW_WIN_H" windowmove "$wid" 0 0 2>/dev/null
    _dw_wait 1.5
    ADAPTER_PID=launched
    adapter_focus
}

adapter_quit() {
    _dw_exec pkill -f "$_DW_BIN" 2>/dev/null || true
    local t=0
    while _dw_exec pgrep -f "$_DW_BIN" >/dev/null 2>&1 && (( t < 30 )); do _dw_wait 0.1; t=$(( t + 1 )); done
    _dw_exec pkill -9 -f "$_DW_BIN" 2>/dev/null || true
    ADAPTER_PID=""
}

# ── 3. Window match ──────────────────────────────────────────────────────────
adapter_window_bounds() {
    local wid info ax ay w h
    wid=$(_dw_wid); [[ -n "$wid" ]] || return 1
    info=$(xwininfo -id "$wid" 2>/dev/null)
    ax=$(awk '/Absolute upper-left X/ {print $NF}' <<< "$info")
    ay=$(awk '/Absolute upper-left Y/ {print $NF}' <<< "$info")
    w=$(awk '/Width:/  {print $NF}' <<< "$info")
    h=$(awk '/Height:/ {print $NF}' <<< "$info")
    echo "${ax:-0} ${ay:-0} ${w:-0} ${h:-0}"
}

# ── 4. Logical → screen: window-relative, 1:1 ────────────────────────────────
adapter_to_screen() {
    local lx=$1 ly=$2 wx wy _w _h
    read -r wx wy _w _h < <(adapter_window_bounds)
    echo "$(( wx + lx )) $(( wy + ly ))"
}

# ── 5. Blessed config: isolated, rewritten before every test ─────────────────
ADAPTER_CONFIG="$_DW_CFG_DIR/drawyrc"
adapter_pre_launch() {
    # collect "# QA-DRAWYRC: Group/Key=value" lines from the test file
    _DW_EXTRA_RC=$(sed -n 's/^# QA-DRAWYRC: *//p' "$1")
    # a fresh data dir every test; the model only if the test asks for it
    _dw_exec rm -rf "$_DW_DATA_DIR"
    _dw_exec mkdir -p "$_DW_DATA_DIR/drawy/handwriting"
    if grep -q '^# QA-DRAWY-MODEL: *installed' "$1"; then
        _dw_exec cp "/src/.cache/models/$_DW_MODEL" "$_DW_DATA_DIR/drawy/handwriting/" \
            || echo "drawy: $_DW_MODEL missing from .cache/models" >&2
    fi
    # the runner re-asserts the config before calling this hook, so write it
    # again now that this test's settings are known
    adapter_ensure_config
}
adapter_ensure_config() {
    # Defaults keep runs deterministic: no autosave restore prompt, grid off.
    local rc="[AutoSave]
AutoSaveEnabled=false
[Grid]
ShowGrid=false
SnapToGrid=false
GridSize=20
"
    local line group kv
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        group=${line%%/*}; kv=${line#*/}
        rc+="[$group]
$kv
"
    done <<< "$_DW_EXTRA_RC"
    _dw_exec bash -c "rm -rf '$_DW_CFG_DIR' && mkdir -p '$_DW_CFG_DIR'"
    printf '%s' "$rc" | podman exec -i "$_DW_CONTAINER" bash -c "cat > '$ADAPTER_CONFIG'"
}

# ── 6. Lifecycle hooks ───────────────────────────────────────────────────────
adapter_is_alive()     { _dw_exec pgrep -f "$_DW_BIN" >/dev/null 2>&1; }
adapter_crashlog_dir() { echo ""; }
adapter_focus() {
    local w; w=$(_dw_wid); [[ -n "$w" ]] || return 0
    xdotool windowactivate --sync "$w" 2>/dev/null || xdotool windowfocus "$w" 2>/dev/null || true
}
adapter_pre_input()    { adapter_focus; }
adapter_park_window()  { : ; }
