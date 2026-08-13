#!/usr/bin/env bash
# adapters/draw/manifest.sh — the DRAW adapter (reference).
#
# The ENTIRE app-specific integration surface for DRAW (a QB64-PE pixel editor).
# The core sources this after the driver, then calls the adapter_* facts below.
# Everything here is ported from DRAW/QA/draw-qa.sh — only the calls that cross
# the seam (capture → driver, geometry math kept app-local) were adapted.
#
# QB64-PE exposes no stable window id, so we match by title "DRAW v" + pid.

# ── DRAW locations ───────────────────────────────────────────────────────────
DRAW_ROOT="${DRAW_ROOT:-/home/grymmjack/git/DRAW}"
DRAW_BIN="$DRAW_ROOT/DRAW.run"

# ── 1. Identity ──────────────────────────────────────────────────────────────
ADAPTER_NAME="${QA_PROJECT:-DRAW}"          # report title / project name
ADAPTER_TESTS_DIR="$DRAW_ROOT/QA/tests"     # absolute — DRAW's tests live in its repo

WINDOW_TITLE="DRAW v"
DRAW_PID=""
DRAW_WID=""
DRAW_EXTRA_ARGS="${DRAW_EXTRA_ARGS:-}"
# Per-test DRAW --option overrides, computed from a test file's `# QA-OPTIONS:`
# line by adapter_pre_launch. Reset each test so options never leak forward.
DRAW_TEST_OPTIONS=""

# ── QA config isolation ───────────────────────────────────────────────────────
# DRAW is always launched with --config DRAW.qa.cfg, so runs are deterministic
# and never read or write the user's own DRAW.cfg. See draw-qa.sh for the why.
QA_CFG="$DRAW_ROOT/QA/DRAW.qa.cfg"

# Deterministic geometry — every value the coordinate maths below depends on must
# be explicit here; a 0 means "auto-detect" to DRAW and breaks the model.
# UI_SCALE MUST stay 0 (SCREEN_init only honors an explicit SCREEN_WIDTH/HEIGHT in
# pure Auto mode); with a UI_SCALE master set, DRAW re-derives the viewport from
# desktop/scale and the model below stops matching.
_qa_cfg_overrides() {
    cat <<'OVERRIDES'
UI_SCALE=0
DISPLAY_SCALE=2
TOOLBAR_SCALE=2
SCREEN_WIDTH=958
SCREEN_HEIGHT=514
LAYER_PANEL_WIDTH=100
LAYERS_PANEL_DOCK_EDGE=LEFT
TOOLBOX_DOCK_EDGE=RIGHT
DEFAULT_CANVAS_SIZE_W=320
DEFAULT_CANVAS_SIZE_H=200
DEFAULT_PALETTE=ANSI32 (32)
PALETTE_CHIP_WIDTH=16
PALETTE_CHIP_HEIGHT=8
PALETTE_MAX_CHIPS_PER_ROW=32
PALETTE_MAX_ROWS=3
PALETTE_MIN_ROWS=1
SOUNDS_ENABLED=FALSE
MUSIC_ENABLED=FALSE
OVERRIDES
}

# Build DRAW.qa.cfg from DRAW.cfg.default with the overrides above applied.
# Re-asserts the overrides on EVERY call (startup + before each test launch) — it
# does NOT cache-and-skip. DRAW's CONFIG_save writes its live config back to the
# --config file on exit, which can flip a pinned override, and a cached cfg would
# make that clobbered value sticky. Ported from draw-qa.sh _ensure_qa_cfg.
adapter_ensure_config() {
    if [[ ! -f "$DRAW_ROOT/DRAW.cfg.default" ]]; then
        echo "ERROR: $DRAW_ROOT/DRAW.cfg.default not found — cannot build QA config" >&2
        exit 1
    fi
    local existed=0; [[ -f "$QA_CFG" ]] && existed=1
    cp "$DRAW_ROOT/DRAW.cfg.default" "$QA_CFG"
    local line key val
    while IFS= read -r line; do
        key=${line%%=*}
        val=${line#*=}
        if grep -q "^${key}=" "$QA_CFG"; then
            sed -i "s|^${key}=.*|${key}=${val}|" "$QA_CFG"
        else
            echo "$line" >> "$QA_CFG"
        fi
    done < <(_qa_cfg_overrides)
    [[ $existed -eq 0 ]] && echo "Created QA config: $QA_CFG"
}
ADAPTER_CONFIG="$QA_CFG"

# Build the cfg now, at source-time, so the geometry block below can read it.
adapter_ensure_config
DRAW_CFG="$QA_CFG"

# ── parse DRAW.cfg ────────────────────────────────────────────────────────────
_cfg() { [[ -n "$DRAW_CFG" ]] && grep -m1 "^${1}=" "$DRAW_CFG" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]'; }

# ${x:-1} is NOT enough — it only substitutes when x is unset/empty, and DRAW
# writes a literal 0 to mean "auto-detect". A zero scale collapses every click
# onto the window origin and crops captures to 0x0.
_num_or() {
    local v=$1 fallback=$2
    [[ "$v" =~ ^[0-9]+$ ]] && [[ "$v" -gt 0 ]] && { echo "$v"; return; }
    echo "$fallback"
}

DISPLAY_SCALE=$(_num_or "$(_cfg DISPLAY_SCALE)" 1)

# Window decoration height — detected after window creation (always 0 here; see
# driver_detect_decoration_height). Override with DECORATION_H=22.
DECORATION_H=${DECORATION_H:-0}

VIEWPORT_W=$(_num_or "$(_cfg SCREEN_WIDTH)" 904)
VIEWPORT_H=$(_num_or "$(_cfg SCREEN_HEIGHT)" 510)
LAYER_PANEL_W=$(_num_or "$(_cfg LAYER_PANEL_WIDTH)" 100)
LAYERS_DOCK=$(_cfg LAYERS_PANEL_DOCK_EDGE); LAYERS_DOCK=${LAYERS_DOCK:-LEFT}
TOOLBOX_DOCK=$(_cfg TOOLBOX_DOCK_EDGE);    TOOLBOX_DOCK=${TOOLBOX_DOCK:-RIGHT}
TOOLBAR_SCALE=$(_num_or "$(_cfg TOOLBAR_SCALE)" 2)
CANVAS_W=$(_num_or "$(_cfg DEFAULT_CANVAS_SIZE_W)" 320)
CANVAS_H=$(_num_or "$(_cfg DEFAULT_CANVAS_SIZE_H)" 200)

# Derived chrome sizes (internal viewport pixels, matching DRAW's layout constants)
MENU_BAR_H=12
STATUS_H=11

# Bottom chrome band below the canvas — a CONSERVATIVE reservation, NOT the real
# palette strip. It only has to be >= the actual chrome so the canvas work area
# never overlaps it. Do NOT use PAL_Y to click a palette chip.
PALETTE_H=30

# Palette-name dropdown button — the click target that opens the palette menu.
PAL_NAME_X_OFFSET=80   # from the right edge
PAL_NAME_Y=$(( VIEWPORT_H - STATUS_H - 6 ))  # ≈497, inside the strip's 491..502 band
TOOLBAR_W=$(( 47 * TOOLBAR_SCALE + 2 ))   # TB_COLS*TB_BTN_W*TB + gaps + 2
TOOLBAR_H=$(( 83 * TOOLBAR_SCALE ))        # TB_ROWS*TB_BTN_H*TB + gaps
ORGANIZER_H=$(( 32 * TOOLBAR_SCALE ))      # 3 rows × 10 × TB + 2 gaps × TB

# Convenience aliases used by tests
VP_W=$VIEWPORT_W
VP_H=$VIEWPORT_H

# Canvas work area in viewport pixels
if [[ "$LAYERS_DOCK" == "LEFT" ]]; then
    WORK_LEFT=$LAYER_PANEL_W
    WORK_RIGHT=$(( VIEWPORT_W - TOOLBAR_W ))
else
    WORK_LEFT=$TOOLBAR_W
    WORK_RIGHT=$(( VIEWPORT_W - LAYER_PANEL_W ))
fi
WORK_TOP=$MENU_BAR_H
WORK_BOTTOM=$(( VIEWPORT_H - STATUS_H - PALETTE_H ))
WORK_W=$(( WORK_RIGHT - WORK_LEFT ))
WORK_H=$(( WORK_BOTTOM - WORK_TOP ))

# Canvas top-left within work area (centred)
CANVAS_OFFSET_X=$(( WORK_LEFT + (WORK_W - CANVAS_W) / 2 ))
CANVAS_OFFSET_Y=$(( WORK_TOP  + (WORK_H - CANVAS_H) / 2 ))

# Centre of the canvas in viewport pixels
CANVAS_CX=$(( CANVAS_OFFSET_X + CANVAS_W / 2 ))
CANVAS_CY=$(( CANVAS_OFFSET_Y + CANVAS_H / 2 ))

# ── panel geometry (viewport pixels) for test snap regions ────────────────────
if [[ "$TOOLBOX_DOCK" == "RIGHT" ]]; then
    TB_X=$(( VIEWPORT_W - TOOLBAR_W ))
else
    TB_X=0
fi
TB_Y=$MENU_BAR_H
TB_W=$TOOLBAR_W
TB_H=$TOOLBAR_H

if [[ "$LAYERS_DOCK" == "LEFT" ]]; then
    LP_X=0
else
    LP_X=$(( VIEWPORT_W - LAYER_PANEL_W ))
fi
# LAYER_PANEL_render sets panelY% = 0 — anchored to the TOP of the window.
LP_Y=0
LP_W=$LAYER_PANEL_W
LP_H=$(( VIEWPORT_H - MENU_BAR_H - STATUS_H - PALETTE_H ))

# Aliases used by new-layer.sh
LAYER_PANEL_X=$LP_X
LAYER_PANEL_Y=$LP_Y
LAYER_PANEL_H=$LP_H

# Palette strip position & size
PAL_X=0
PAL_Y=$(( VIEWPORT_H - STATUS_H - PALETTE_H ))
PAL_W=$VIEWPORT_W
PAL_H=$PALETTE_H

# Absolute click target for the palette-name dropdown button
PAL_NAME_X=$(( VIEWPORT_W - PAL_NAME_X_OFFSET ))

# ── window position (client-area origin, via the driver) ─────────────────────
WIN_ABS_X=""
WIN_ABS_Y=""

# Refresh cached window position. Delegates the xwininfo math to the driver; the
# driver returns the reparenting-aware client-area origin. Ported from
# draw-qa.sh _update_win_pos.
_update_win_pos() {
    local ax ay w h
    read -r ax ay w h < <(driver_window_bounds_by_title "$WINDOW_TITLE" "$DRAW_PID")
    if [[ -n "$ax" && -n "$ay" ]]; then
        WIN_ABS_X=$ax
        WIN_ABS_Y=$ay
    else
        WIN_ABS_X=0
        WIN_ABS_Y=0
    fi
}

# ── 4. Logical → screen mapping (the seam) ───────────────────────────────────
# Ported from draw-qa.sh _abs. DECORATION_H skips the title bar so (0,0) maps to
# the client-area origin; each logical pixel is DISPLAY_SCALE physical pixels.
adapter_to_screen() {
    [[ -z "$WIN_ABS_X" ]] && _update_win_pos
    echo $(( WIN_ABS_X + $1 * DISPLAY_SCALE )) $(( WIN_ABS_Y + DECORATION_H + $2 * DISPLAY_SCALE ))
}
# DRAW's tests call `_abs vx vy` directly when they drop to raw xdotool for
# multi-step gestures (pan, hold-key drags, mid-drag key taps). Expose it under
# that name — same as draw_focus below. Without this the tests get empty coords
# ("" ""), the gesture is a no-op, and every _abs-using test fails "regions
# identical". (Missed in the initial port; found dogfooding the full suite.)
_abs() { adapter_to_screen "$@"; }

# ── 3. Window match — returns the CLIENT rect: "X Y W H" (physical px) ────────
# X/Y = client origin; W/H = viewport × DISPLAY_SCALE (what the core crops to for
# a full-window capture, matching draw-qa.sh _capture_client_area).
adapter_window_bounds() {
    _update_win_pos
    echo "$WIN_ABS_X" "$(( WIN_ABS_Y + DECORATION_H ))" \
         "$(( VIEWPORT_W * DISPLAY_SCALE ))" "$(( VIEWPORT_H * DISPLAY_SCALE ))"
}

# ── focus (lightweight — used by capture; no cursor jiggle) ──────────────────
# Ported from draw-qa.sh draw_focus. Also exposed to tests under that name.
draw_focus() {
    [[ -z "$DRAW_WID" ]] && return
    if ! xdotool getwindowname "$DRAW_WID" &>/dev/null; then
        local new_wid
        new_wid=$(xdotool search --pid "$DRAW_PID" --name "$WINDOW_TITLE" 2>/dev/null | head -1)
        [[ -n "$new_wid" ]] && DRAW_WID="$new_wid"
    fi
    xdotool windowactivate --sync "$DRAW_WID" 2>/dev/null
    xdotool windowfocus --sync "$DRAW_WID" 2>/dev/null
    sleep 0.05
}
adapter_focus() { draw_focus; }

# ── 6. pre-input hook (wake DRAW from idle before each dispatched input) ──────
# Ported from draw-qa.sh wake_draw. DRAW drops to 13fps when idle and can miss a
# modifier combo mid-chord; a 1px cursor jiggle sets FRAME_IDLE% = FALSE, keeping
# it at active fps long enough for the key event to register. Exposed to tests as
# wake_draw AND wired as the core's adapter_pre_input hook.
wake_draw() {
    _update_win_pos
    draw_focus
    local ax ay
    read -r ax ay <<< "$(adapter_to_screen 50 60)"
    xdotool mousemove "$ax" "$ay"
    xdotool mousemove_relative -- 1 0
    sleep 0.03
    xdotool mousemove_relative -- -1 0
    sleep 0.03
}
# Before each dispatched input, match the ORIGINAL draw-qa.sh: its click/drag/key/
# type_text did `draw_focus` only — a lightweight window focus, NOT a cursor
# jiggle. wake_draw (mouse move-to-park + jiggle) is a SEPARATE helper tests call
# explicitly before an idle-sensitive combo. Wiring wake_draw as the per-input
# hook made every key first move+jiggle the cursor, which perturbed mode-sensitive
# combos (text ctrl+u underline, polygon ctrl+z undo) → "regions identical".
adapter_pre_input() {
    draw_focus
    # Jiggle the cursor IN PLACE (±1px, nets to zero — no reposition) so DRAW's
    # idle detector (FRAME_IDLE% via a mouseMoved% event) wakes and the following
    # input isn't dropped. This is the best of both: it wakes like wake_draw but,
    # unlike wake_draw, it does NOT move the cursor to a park spot — that absolute
    # move is what perturbed mode-sensitive combos (text Ctrl+U, polygon Ctrl+Z).
    # Plain draw_focus alone (no jiggle) left DRAW idle, so drag-paint tests
    # (edit-stroke-selection, layer-group-auto-layer) dropped their stroke.
    xdotool mousemove_relative -- 1 0 2>/dev/null
    xdotool mousemove_relative -- -1 0 2>/dev/null
}

# canvas_focus [restore_key] — give DRAW focus by clicking the canvas centre with
# the Move tool (non-destructive), then optionally restore the prior tool. NOT
# selection-neutral once groups are involved — after selecting a layer, prefer
# `key <tool>`. Ported from draw-qa.sh. Uses the core input aliases key/click.
canvas_focus() {
    local restore_key=${1:-""}
    key v            # Move tool — non-destructive click
    sleep 0.05
    click "$CANVAS_CX" "$CANVAS_CY"
    sleep 0.1
    if [[ -n "$restore_key" ]]; then
        key "$restore_key"
        sleep 0.05
    fi
}

# ── 2. Launch / quit ─────────────────────────────────────────────────────────
# adapter_pre_launch <test_file> — runner hook, called before the per-test launch.
# Lets a test request DRAW --option overrides for its OWN launch via a magic line:
#     # QA-OPTIONS: GROUP_DRAW_AUTO_LAYER=TRUE TOOLTIPS_DISABLED=FALSE
# Turns each KEY=VALUE into a "--option KEY=VALUE" arg (DRAW's CLI override, which
# beats the .cfg). This is how a test flips a config option WITHOUT the fragile
# edit-cfg-then-relaunch dance (a mid-test relaunch disturbs window/click state).
# DRAW_TEST_OPTIONS is reset every call so options never leak into the next test.
adapter_pre_launch() {
    local test_file=$1
    DRAW_TEST_OPTIONS=""
    [[ -f "$test_file" ]] || return 0
    local line kv
    line=$(grep -m1 -E '^[[:space:]]*#[[:space:]]*QA-OPTIONS:' "$test_file" 2>/dev/null)
    [[ -n "$line" ]] || return 0
    line=${line#*QA-OPTIONS:}
    for kv in $line; do
        [[ "$kv" == *=* ]] && DRAW_TEST_OPTIONS+=" --option $kv"
    done
    [[ -n "$DRAW_TEST_OPTIONS" ]] && info "Per-test DRAW options:${DRAW_TEST_OPTIONS}"
}

# Ported from draw-qa.sh draw_launch. Exposed to tests under that name too.
draw_launch() {
    local timeout=${1:-15}
    if [ ! -x "$DRAW_BIN" ]; then
        echo "ERROR: $DRAW_BIN not found or not executable" >&2
        exit 1
    fi
    info "Launching DRAW (--config $(basename "$QA_CFG"))..."
    # Launch from DRAW_ROOT, not QA/. DRAW never CHDIRs and resolves some assets
    # against the current directory ("./ASSETS/..."), so running elsewhere breaks
    # palette .GPL previews and friends.
    ( cd "$DRAW_ROOT" && exec "$DRAW_BIN" --config "$QA_CFG" $DRAW_EXTRA_ARGS $DRAW_TEST_OPTIONS ) &
    DRAW_PID=$!

    info "Waiting for window (up to ${timeout}s) — PID=$DRAW_PID"
    local i=0
    while [[ $i -lt $(( timeout * 2 )) ]]; do
        DRAW_WID=$(xdotool search --pid "$DRAW_PID" --name "$WINDOW_TITLE" 2>/dev/null | head -1)
        [[ -n "$DRAW_WID" ]] && break
        sleep 0.5
        i=$(( i + 1 ))
    done

    if [[ -z "$DRAW_WID" ]]; then
        echo "ERROR: DRAW window never appeared after ${timeout}s" >&2
        exit 1
    fi
    info "Window found: WID=$DRAW_WID"
    draw_focus
    sleep 0.3
    info "Positioning window (Meta+Home)..."
    xdotool windowactivate --sync "$DRAW_WID" 2>/dev/null
    xdotool windowfocus --sync "$DRAW_WID" 2>/dev/null
    sleep 0.2
    xdotool key --delay 50 super+Home
    sleep 0.5   # let the WM finish the window animation
    _update_win_pos
    info "Window position: ${WIN_ABS_X},${WIN_ABS_Y}"
    if [[ "$DECORATION_H" -eq 0 ]]; then
        DECORATION_H=$(driver_detect_decoration_height)
    fi
    info "Decoration height: ${DECORATION_H}px"
    _verify_geometry_model
    sleep 0.3
}
adapter_launch() { draw_launch "$@"; }

# adapter_park_window → move+resize the DRAW window to a known desktop rect.
# DRAW binds Meta+Home for this (also done inside draw_launch).
adapter_park_window() {
    [[ -z "$DRAW_WID" ]] && return
    xdotool windowactivate --sync "$DRAW_WID" 2>/dev/null
    xdotool key --delay 50 super+Home
    sleep 0.5
    _update_win_pos
}

# Cross-check the cfg-derived coordinate model against the real window. If the
# window disagrees, every assertion silently degrades into "compare two
# full-desktop screenshots" (which passes for the wrong reason). Fail loudly.
# Ported from draw-qa.sh _verify_geometry_model.
_verify_geometry_model() {
    eval "$(xdotool getwindowgeometry --shell "$DRAW_WID" 2>/dev/null)"
    local win_w=${WIDTH:-0} win_h=${HEIGHT:-0}
    local want_w=$(( VIEWPORT_W * DISPLAY_SCALE ))
    local want_h=$(( VIEWPORT_H * DISPLAY_SCALE ))
    local dw=$(( win_w - want_w )); [[ $dw -lt 0 ]] && dw=$(( -dw ))
    local dh=$(( win_h - want_h )); [[ $dh -lt 0 ]] && dh=$(( -dh ))
    if [[ $dw -le 4 && $dh -le 4 ]]; then
        info "Geometry model OK: ${win_w}x${win_h} (viewport ${VIEWPORT_W}x${VIEWPORT_H} @ ${DISPLAY_SCALE}x)"
        return 0
    fi
    echo "ERROR: window geometry does not match the QA coordinate model." >&2
    echo "       window   = ${win_w}x${win_h}" >&2
    echo "       expected = ${want_w}x${want_h} (${VIEWPORT_W}x${VIEWPORT_H} @ ${DISPLAY_SCALE}x)" >&2
    echo "       config   = $DRAW_CFG" >&2
    echo "       Clicks and screenshot crops would be wrong; refusing to run." >&2
    adapter_quit
    exit 1
}

# Ported from draw-qa.sh draw_quit. Honours --keep-open via KEEP_OPEN (core sets
# it). Exposed to tests under that name too.
draw_quit() {
    if [[ "${KEEP_OPEN:-0}" -eq 1 ]]; then
        info "Keeping DRAW open (--keep-open). Close it manually."
        return
    fi
    if [[ -n "$DRAW_PID" ]] && kill -0 "$DRAW_PID" 2>/dev/null; then
        info "Closing DRAW (PID $DRAW_PID)..."
        xdotool key --window "$DRAW_WID" ctrl+q 2>/dev/null || true
        sleep 0.5
        if kill -0 "$DRAW_PID" 2>/dev/null; then
            kill "$DRAW_PID" 2>/dev/null || true
        fi
        DRAW_PID=""
        DRAW_WID=""
    fi
}

# draw_settle — block (bounded) until NO "DRAW v" window is mapped. Call it
# between draw_quit and draw_launch in a test that relaunches with a BLANK
# document (which appears fast enough to race the outgoing instance's still-dying
# window). DRAW/SDL2 sets no _NET_WM_PID, so the relaunch's title search can't
# tell the two apart and binds the stale one → every input misses the canvas.
#
# This is OPT-IN, not baked into draw_quit, on purpose: forcing every quit to
# wait for the old instance to fully die reproducibly breaks the NEXT instance's
# first Ctrl+S save (file-draw-roundtrip) — DRAW's startup is sensitive to the
# quit→launch overlap. A file-loading relaunch is slow enough that the old window
# is already gone, so those tests must NOT call this and keep the overlap.
draw_settle() {
    local i=0
    while [[ $i -lt 60 ]] && [[ -n "$(xdotool search --name "$WINDOW_TITLE" 2>/dev/null)" ]]; do
        sleep 0.1; i=$(( i + 1 ))
    done
}
adapter_quit() { draw_quit; }

# ── lifecycle hooks used by the core's crash/window assertions ───────────────
# adapter_is_alive → 0 if DRAW is still up. Refreshes a stale WID from the pid so
# the window-title assertion keeps working after e.g. a capture invalidates it.
adapter_is_alive() {
    [[ -n "$DRAW_PID" ]] || return 1
    kill -0 "$DRAW_PID" 2>/dev/null || return 1
    if [[ -n "$DRAW_WID" ]] && ! xdotool getwindowname "$DRAW_WID" &>/dev/null; then
        local new_wid
        new_wid=$(xdotool search --pid "$DRAW_PID" --name "$WINDOW_TITLE" 2>/dev/null | head -1)
        [[ -n "$new_wid" ]] && DRAW_WID="$new_wid"
    fi
    return 0
}

# adapter_window_title → the app window's current title (for assert_window_title).
adapter_window_title() {
    adapter_is_alive >/dev/null 2>&1
    xdotool getwindowname "$DRAW_WID" 2>/dev/null || echo ""
}

# adapter_crashlog_dir → where DRAW writes crash reports. DRAW survives a runtime
# error (FatalError stashes it and RESUME NEXTs), leaving only a report here.
adapter_crashlog_dir() { echo "$HOME/Desktop/DRAW-log/DRAW-crash-logs"; }
