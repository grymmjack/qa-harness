#!/usr/bin/env bash
# adapter.template.sh — the ENTIRE integration surface for one app.
#
# Copy this to  adapters/<yourapp>/manifest.sh  and fill in the six sections.
# The core sources this file, then calls the functions/vars it defines. Nothing
# app-specific lives in core/ or drivers/ — only here.
#
# Contract: define the variables and shell functions below. Anything marked
# OPTIONAL may be omitted; the core has a sane default. Coordinates your tests use
# are LOGICAL; `adapter_to_screen` is the one place logical→screen is decided.

# ── 1. Identity ──────────────────────────────────────────────────────────────
ADAPTER_NAME="myapp"          # report title / project name
ADAPTER_TESTS_DIR="tests"     # dir of *.sh test files, relative to this manifest
# For bin/qa-dash (all optional):
ADAPTER_APP_ROOT=""           # the app's checkout - the dashboard shows its git branch
# ADAPTER_KNOWN_FAILURES=...  # "test-name  reason" per line; default: known-failures.txt beside the tests folder
# ADAPTER_TARGET_FILE=...     # the dashboard's "needs to pass" set; default: qa-target.txt beside the tests folder

# ── 2. Launch / quit ─────────────────────────────────────────────────────────
# adapter_launch <timeout_s> → start the app, export ADAPTER_PID, block until the
# window is up (use target.window_wait from the driver). Return non-zero on fail.
adapter_launch() {
    local timeout=${1:-15}
    : # e.g.  "$APP_BIN" --config "$ADAPTER_CONFIG" &  ADAPTER_PID=$!
    :         # then wait for the window to appear via the driver's target verbs
}

# adapter_quit → stop the app cleanly (and kill -9 stragglers). Idempotent.
adapter_quit() {
    : # e.g.  [[ -n "$ADAPTER_PID" ]] && kill "$ADAPTER_PID" 2>/dev/null
}

# ── 3. Window match (NO stable window id required) ───────────────────────────
# Return the app's window rect on screen as: "X Y W H".  Match however you can:
# by title, then pid, then "the one fullscreen-ish window". The core never needs
# a persistent window id — it works entirely from this rect.
adapter_window_bounds() {
    : # e.g.  driver_window_bounds_by_title "MyApp"
}

# ── 4. Logical → screen mapping (the seam) ───────────────────────────────────
# Tests pass logical coords; convert to absolute screen pixels here. The default
# (window-relative, 1:1) suits most apps. Override for display-scaled apps (e.g.
# DRAW multiplies by DISPLAY_SCALE and offsets by a viewport origin).
# Prints: "SX SY"
adapter_to_screen() {
    local lx=$1 ly=$2
    read -r wx wy _ _ < <(adapter_window_bounds)
    echo "$(( wx + lx )) $(( wy + ly ))"
}

# ── 5. Blessed config (OPTIONAL) ─────────────────────────────────────────────
# If the app reads a config, point it at an ISOLATED, pinned one so runs are
# deterministic and never touch the user's real settings. Re-assert each run.
ADAPTER_CONFIG=""             # path passed to the app; "" if none
adapter_ensure_config() { : ; }   # write/re-assert the blessed config

# ── 6. Lifecycle hooks ───────────────────────────────────────────────────────
# adapter_is_alive → 0 if the app is still up (pid/health). Used by crash checks.
adapter_is_alive() { [[ -n "$ADAPTER_PID" ]] && kill -0 "$ADAPTER_PID" 2>/dev/null; }

# adapter_park_window (OPTIONAL) → move+resize the window to a known desktop rect
# via a WM hotkey, so coords are deterministic even with no window id and window
# size/resize tests become possible. DRAW binds Meta+Home for this.
adapter_park_window() { : ; }

# adapter_crashlog_dir (OPTIONAL) → where the app writes crash reports, so the
# core can detect a trapped runtime error after a test. "" = none.
adapter_crashlog_dir() { echo ""; }

# adapter_pre_input (OPTIONAL) → run once before each dispatched key/click. Some
# apps drop input while idle; a tiny cursor jiggle wakes them (DRAW's wake hook).
adapter_pre_input() { : ; }
