#!/usr/bin/env bash
# core/assert.sh — the core value: region-based VISUAL assertions, plus the named
# region registry that lets a human confirm the harness looks where they think.
#
# All portable. Bodies ported from DRAW/QA/draw-qa.sh. Pixels always come from the
# driver (driver_capture_full) and are cropped here; the ImageMagick AE metric is
# QuantumRange-normalized so a "1 pixel differs" reads as 1 on any IM build.
#
# Public API tests use:
#   region NAME LX LY LW LH [desc]   declare a named logical rect (+ description)
#   snap   NAME [label]              capture that region → a snap file
#   assert_regions_differ A B [msg]  FAIL if two snaps are pixel-identical
#   assert_regions_same   A B [msg]  FAIL if two snaps differ beyond tol

# ── seam helpers ─────────────────────────────────────────────────────────────
# Lightweight focus before a capture (no cursor jiggle). Optional adapter hook.
_qa_focus()     { command -v adapter_focus     >/dev/null 2>&1 && adapter_focus; }
# Wake the app before dispatched input (may jiggle the cursor). Optional hook.
_qa_pre_input() { command -v adapter_pre_input >/dev/null 2>&1 && adapter_pre_input; }

# _qa_scale → "SX SY": physical screen px per 1 logical px, derived from the one
# place logical→screen is decided (the adapter). For DRAW this is DISPLAY_SCALE;
# for a 1:1 adapter it is 1. Keeps the crop math app-agnostic in the core.
_qa_scale() {
    local ox oy x1 y1 sx sy
    read -r ox oy < <(adapter_to_screen 0 0)
    read -r x1 y1 < <(adapter_to_screen 1 1)
    sx=$(( x1 - ox )); sy=$(( y1 - oy ))
    [[ $sx -lt 1 ]] && sx=1
    [[ $sy -lt 1 ]] && sy=1
    echo "$sx $sy"
}

# ── capture orchestration (pixels come from the driver; core crops) ──────────
# Capture the app's client area and save to $1. Full-display grab (driver) then
# crop to the adapter's window rect. Ported from draw-qa.sh _capture_client_area
# — the spectacle/scrot backend choice now lives in driver_capture_full.
_capture_client_area() {
    local outfile=$1
    local tmp; tmp="$(mktemp --suffix=.png 2>/dev/null || echo "/tmp/qa-cap-$$-${RANDOM}.png")"
    local wx wy ww wh
    read -r wx wy ww wh < <(adapter_window_bounds)
    dbg "capture: crop=${ww}x${wh}+${wx}+${wy}"
    if ! driver_capture_full "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    dbg "capture: fullscreen=$(identify -format '%wx%h' "$tmp" 2>/dev/null)"
    convert "$tmp" -crop "${ww}x${wh}+${wx}+${wy}" +repage "$outfile" 2>/dev/null
    rm -f "$tmp"
    [[ -f "$outfile" ]]
}

# screenshot "label" — capture the whole client area. Sets SNAP_RESULT.
screenshot() {
    local label=${1:-"shot"}
    local ts; ts=$(date '+%H%M%S%3N')
    SNAP_RESULT="$SCREENSHOTS_DIR/${label}-${ts}.png"
    _qa_focus
    sleep 0.15   # let the compositor finish compositing the frame
    if _capture_client_area "$SNAP_RESULT"; then
        info "Screenshot → $(basename "$SNAP_RESULT")"
    else
        warn "screenshot failed for '$label'"
        SNAP_RESULT=""
    fi
}

# snap_region X Y W H label — capture a logical-pixel region of the app window.
# Two-step crop: fullscreen → client area → sub-region. Sets SNAP_RESULT.
snap_region() {
    local vx=$1 vy=$2 vw=$3 vh=$4 label=${5:-"snap"}
    SNAP_RESULT="$SCREENSHOTS_DIR/_snap_${label}_$$.png"
    local wintmp="/tmp/qa-win-$$.png"

    # Sub-region offsets (logical px → physical px within the client area).
    local sx sy
    read -r sx sy < <(_qa_scale)
    local rx=$(( vx * sx )) ry=$(( vy * sy )) rw=$(( vw * sx )) rh=$(( vh * sy ))

    dbg "snap_region vp=($vx,$vy ${vw}x${vh}) → px=($rx,$ry ${rw}x${rh}) label=$label"

    _qa_focus
    sleep 1

    if _capture_client_area "$wintmp"; then
        dbg "snap_region client_area=$(identify -format '%wx%h' "$wintmp" 2>/dev/null) sub-crop=${rw}x${rh}+${rx}+${ry}"
        convert "$wintmp" -crop "${rw}x${rh}+${rx}+${ry}" +repage "$SNAP_RESULT" 2>/dev/null
        # Remember where this snap looked so a failed assert / --calibrate can
        # re-capture and outline exactly this box.
        if [[ -s "$SNAP_RESULT" ]]; then
            SNAP_RECT["$SNAP_RESULT"]="$rx $ry $rw $rh"
            [[ -n "$CURRENT_REGION" ]] && SNAP_REGION["$SNAP_RESULT"]="$CURRENT_REGION"
        fi
        if [[ ${DUMP_SNAPS:-0} -eq 1 && -s "$SNAP_RESULT" ]]; then
            SNAP_SEQ=$(( SNAP_SEQ + 1 ))
            local d="$SNAP_DUMP_DIR/${CURRENT_TEST:-test}-${SNAP_SEQ}_${label}"
            cp -f "$SNAP_RESULT" "${d}.png" 2>/dev/null
            convert "$wintmp" -stroke red -fill none -strokewidth 3 \
                -draw "rectangle ${rx},${ry} $((rx+rw)),$((ry+rh))" "${d}-where.png" 2>/dev/null
            info "  📸 dumped ${CURRENT_TEST:-test}-${SNAP_SEQ}_${label}.png (region @ vp ${vx},${vy} ${vw}x${vh})"
        fi
        rm -f "$wintmp"
    else
        dbg "snap_region _capture_client_area FAILED"
        SNAP_RESULT=""
    fi
}

# ── named region registry ─────────────────────────────────────────────────────
declare -A REGION_RECT    # name -> "vx vy vw vh" (logical pixels)
declare -A REGION_DESC    # name -> human description (shown on -where overlays)
declare -A SNAP_RECT      # snap-file path -> "rx ry rw rh" (physical px, for -where)
declare -A SNAP_REGION    # snap-file path -> region name (for -where labels)
CURRENT_REGION=""         # region of the snap in flight (set by snap(), read by snap_region)

# In --calibrate mode, render the just-declared region outlined (green) + labeled
# on the current app frame, so a human confirms placement BEFORE trusting a run.
_calibrate_region() {
    local name=$1 vx vy vw vh
    read -r vx vy vw vh <<< "${REGION_RECT[$name]}"
    local sx sy
    read -r sx sy < <(_qa_scale)
    local rx=$(( vx * sx )) ry=$(( vy * sy )) rw=$(( vw * sx )) rh=$(( vh * sy ))
    local ly=$(( ry > 26 ? ry - 8 : ry + rh + 22 ))
    local out="$CALIBRATE_DIR/${CURRENT_TEST:-test}-${name}.png" wintmp="/tmp/qa-cal-$$.png"
    mkdir -p "$CALIBRATE_DIR"
    _qa_focus; sleep 0.25
    if _capture_client_area "$wintmp"; then
        convert "$wintmp" -stroke '#00ff66' -fill none -strokewidth 3 \
            -draw "rectangle ${rx},${ry} $(( rx + rw )),$(( ry + rh ))" \
            -stroke none -fill '#00ff66' -pointsize 22 \
            -annotate "+$(( rx + 4 ))+${ly}" "$name" \
            "$out" 2>/dev/null
        rm -f "$wintmp"
    fi
    [[ -f "$out" ]] && info "  📐 calibrate '$name' → $(basename "$out")${REGION_DESC[$name]:+  (${REGION_DESC[$name]})}"
}

# region NAME VX VY VW VH [DESCRIPTION...]
region() {
    local name=$1 vx=$2 vy=$3 vw=$4 vh=$5
    REGION_RECT["$name"]="$vx $vy $vw $vh"
    REGION_DESC["$name"]="${*:6}"
    dbg "region '$name' = vp($vx,$vy ${vw}x${vh})"
    [[ ${CALIBRATE:-0} -eq 1 ]] && _calibrate_region "$name"
}

# snap NAME [LABEL] — snap a registered region (LABEL defaults to the region name).
snap() {
    local name=$1 label=${2:-$1}
    if [[ -z "${REGION_RECT[$name]:-}" ]]; then
        fail "snap: unknown region '$name' — declare it first with: region $name x y w h"
        SNAP_RESULT=""; return 1
    fi
    CURRENT_REGION="$name"
    # rect is intentionally word-split into 4 positional args
    # shellcheck disable=SC2086
    snap_region ${REGION_RECT[$name]} "$label"
    CURRENT_REGION=""
}

# ── AE metric calibration ─────────────────────────────────────────────────────
# Raw AE units per differing pixel — calibrated at startup by _calibrate_ae.
AE_UNIT=1

# _ae_number "compare output" — first numeric token, scientific-notation aware.
# ImageMagick prints large counts as "1.47491e+09"; a naive ^[0-9]+ grep would
# truncate that to "1", turning a whole-image difference into a 1-pixel result.
_ae_number() {
    awk '{
        for (i = 1; i <= NF; i++) {
            gsub(/[()]/, "", $i)
            if ($i ~ /^[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/) { printf "%.0f", $i + 0; exit }
        }
        print "0"
    }' <<< "$1"
}

# Measure what one differing pixel reports as. ImageMagick 7 HDRI builds scale the
# AE metric by QuantumRange (a 1-pixel difference reads as 65535), so calibrate
# instead of hardcoding — Q8/Q16/HDRI builds differ.
_calibrate_ae() {
    local t; t=$(mktemp -d)
    if magick -size 4x4 xc:black "$t/a.png" 2>/dev/null && \
       magick "$t/a.png" -fill white -draw 'point 1,1' "$t/b.png" 2>/dev/null; then
        local raw n
        raw=$(compare -metric AE "$t/a.png" "$t/b.png" /dev/null 2>&1 || true)
        n=$(_ae_number "$raw")
        [[ "$n" -ge 1 ]] 2>/dev/null && AE_UNIT=$n
    fi
    rm -rf "$t"
    dbg "AE calibration: 1 differing pixel reports as $AE_UNIT"
    [[ "$AE_UNIT" -ne 1 ]] && info "AE metric scaled by ${AE_UNIT}× on this ImageMagick build — normalising"
    return 0
}

# _parse_ae "compare output" — differing pixels as a plain integer.
_parse_ae() {
    local n; n=$(_ae_number "$1")
    echo $(( n / AE_UNIT ))
}

# On a failed region assertion, re-capture the window and write a copy with the
# region outlined in red + its name/description logged — so a human can see at a
# glance WHERE the harness looked. Ported from draw-qa.sh _emit_where_on_fail.
_emit_where_on_fail() {
    local f1=$1 f2=$2 src rect region rx ry rw rh
    for src in "$f1" "$f2"; do [[ -n "${SNAP_RECT[$src]:-}" ]] && break; done
    rect="${SNAP_RECT[$src]:-}"
    [[ -z "$rect" ]] && return   # raw snap with no recorded rect — nothing to draw
    read -r rx ry rw rh <<< "$rect"
    region="${SNAP_REGION[$src]:-}"
    local tag="${CURRENT_TEST:-test}"; [[ -n "$region" ]] && tag="${tag}_${region}"
    local out="$SCREENSHOTS_DIR/FAIL-${tag}-$$.png" wintmp="/tmp/qa-fail-$$.png"
    if _capture_client_area "$wintmp"; then
        convert "$wintmp" -stroke red -fill none -strokewidth 3 \
            -draw "rectangle ${rx},${ry} $(( rx + rw )),$(( ry + rh ))" "$out" 2>/dev/null
        rm -f "$wintmp"
    fi
    if [[ -f "$out" ]]; then
        local note="region '${region:-?}'"
        [[ -n "$region" && -n "${REGION_DESC[$region]:-}" ]] && note="$note — ${REGION_DESC[$region]}"
        warn "  ↳ where it looked: $(basename "$out")  ($note)"
    fi
}

# assert_regions_differ file1 file2 msg
# Fail if two region snapshots are pixel-identical (action had no visual effect).
assert_regions_differ() {
    local f1=$1 f2=$2 msg=${3:-"region changed"}
    if [[ ! -f "$f1" ]] || [[ ! -f "$f2" ]]; then
        fail "$msg — snapshot file missing (f1=$(basename "$f1") f2=$(basename "$f2"))"
        return
    fi
    local diff_output diff_count
    diff_output=$(compare -metric AE -fuzz 2% "$f1" "$f2" /dev/null 2>&1 || true)
    diff_count=$(_parse_ae "$diff_output")
    info "  [diff] raw='$diff_output' count='${diff_count:-?}' f1=$(basename "$f1") f2=$(basename "$f2")"
    if [[ "${diff_count:-0}" -gt 0 ]] 2>/dev/null; then
        pass "$msg (${diff_count} pixels differ)"
    else
        fail "$msg — regions are identical (action had no effect?)"
        _emit_where_on_fail "$f1" "$f2"
    fi
}

# assert_regions_same file1 file2 msg [tolerance]
# Fail if two region snapshots differ beyond tolerance (default 1500 pixels).
assert_regions_same() {
    local f1=$1 f2=$2 msg=${3:-"region unchanged"} tolerance=${4:-1500}
    if [[ ! -f "$f1" ]] || [[ ! -f "$f2" ]]; then
        fail "$msg — snapshot file missing (f1=$(basename "$f1") f2=$(basename "$f2"))"
        return
    fi
    local diff_output diff_count
    diff_output=$(compare -metric AE -fuzz 2% "$f1" "$f2" /dev/null 2>&1 || true)
    diff_count=$(_parse_ae "$diff_output")
    info "  [diff] raw='$diff_output' count='${diff_count:-?}' tol=$tolerance f1=$(basename "$f1") f2=$(basename "$f2")"
    if [[ "${diff_count:-0}" -le "$tolerance" ]] 2>/dev/null; then
        pass "$msg (${diff_count:-0} pixels differ, within tolerance $tolerance)"
    else
        fail "$msg — regions differ by ${diff_count} pixels (unexpected change?)"
        _emit_where_on_fail "$f1" "$f2"
    fi
}

# ── z-order / hit-target assertions ───────────────────────────────────────────
# assert_cursor_on_top X Y [MSG] — verify the app's pointer/cursor is drawn ON TOP
# at logical (X,Y). Snap a small box there with the pointer parked away (baseline),
# then hover onto (X,Y) and snap again: the cursor must change those pixels. If the
# box is UNCHANGED, the cursor is being drawn UNDER whatever is at (X,Y) — the
# classic "cursor buried beneath a floating window / overlay" z-order bug. This is
# the generic guard for render-order-vs-input-order seams; point it at any
# overlapping overlay (a floating window, a panel edge, a popup).
assert_cursor_on_top() {
    local x=$1 y=$2 msg=${3:-"cursor should render on top at ($x,$y)"} half=6
    park_mouse
    snap_region $(( x - half )) $(( y - half )) $(( half * 2 )) $(( half * 2 )) "curtop-base"
    local base="$SNAP_RESULT"
    hover "$x" "$y"
    snap_region $(( x - half )) $(( y - half )) $(( half * 2 )) $(( half * 2 )) "curtop-cur"
    assert_regions_differ "$base" "$SNAP_RESULT" "$msg"
}

# ── window / process assertions (delegate app specifics to adapter hooks) ─────
# assert_window_title EXPECTED_SUBSTR
assert_window_title() {
    local expected=$1 actual
    actual=$(adapter_window_title 2>/dev/null || echo "")
    if [[ "$actual" == *"$expected"* ]]; then
        pass "window title contains '$expected'"
    else
        fail "window title: expected substring '$expected', got '$actual'"
    fi
}

# assert_window_exists — fail if the app window is no longer available.
assert_window_exists() {
    if adapter_is_alive; then
        pass "app window exists"
    else
        fail "app window has closed unexpectedly"
    fi
}

# assert_no_crash — check the app process is still alive.
assert_no_crash() {
    if adapter_is_alive; then
        pass "app process alive"
    else
        fail "app process has died"
    fi
}
