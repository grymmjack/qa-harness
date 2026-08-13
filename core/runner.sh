#!/usr/bin/env bash
# core/runner.sh — the portable runner. Owns logging/tally, the region-diff
# assertions (core/assert.sh), the test-facing input aliases (core/input.sh),
# ETA, live status, per-run results + report, run isolation/cache, run
# modes/consent, and the CLI. Knows nothing about any app or OS — it calls
# driver_* verbs and adapter_* facts. Bodies ported from DRAW/QA/draw-qa.sh.
#
# NOTE: no set -e — (( N++ )) returns 1 when N=0 and would kill the script.

# core/assert.sh and core/input.sh live beside this file.
# shellcheck source=/dev/null
[[ -f "${QA_HARNESS_ROOT:-.}/core/assert.sh" ]] && source "${QA_HARNESS_ROOT}/core/assert.sh"
# shellcheck source=/dev/null
[[ -f "${QA_HARNESS_ROOT:-.}/core/input.sh"  ]] && source "${QA_HARNESS_ROOT}/core/input.sh"

# ── output locations (kept inside the toolkit) ───────────────────────────────
RESULTS_DIR="${QA_RESULTS_DIR:-${QA_HARNESS_ROOT:-.}/results}"
SCREENSHOTS_DIR="$RESULTS_DIR/screenshots"
CALIBRATE_DIR="$RESULTS_DIR/calibrate"
SNAP_DUMP_DIR="$RESULTS_DIR/snapshots"

# Resolve the adapter's tests dir (absolute, or relative to the manifest dir).
TESTS_DIR="${ADAPTER_TESTS_DIR:-tests}"
[[ "$TESTS_DIR" != /* ]] && TESTS_DIR="${QA_ADAPTER_DIR:-.}/$TESTS_DIR"

PROJECT_NAME="${QA_PROJECT:-${ADAPTER_NAME:-QA}}"

# ── state / tally ─────────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0
KEEP_OPEN=0
FAIL_FAST=0
VERBOSE=0
RERUN_PASSED=0
CALIBRATE=0
ETA=0
REPORT=0
DUMP_SNAPS=${DUMP_SNAPS:-0}
MODE=""                # "" = auto (offscreen if Xvfb) | ask | offscreen | onscreen
EFFECTIVE_MODE=""
LAST_FAIL_MSG=""       # first failure reason of the current test → report "notes"
LOG_FILE=""
RESULTS_TSV=""         # per-run structured results (name<TAB>result<TAB>secs<TAB>notes)
CURRENT_TEST=""
SNAP_SEQ=0
PASSED_CACHE="$RESULTS_DIR/passed.txt"
DURATIONS_FILE="$RESULTS_DIR/durations.tsv"
STATUS_JSON="$RESULTS_DIR/status.json"
STATUS_TXT="$RESULTS_DIR/status.txt"

# ── colours ──────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"

# ── logging + tally ───────────────────────────────────────────────────────────
log()  { echo -e "$*"; [[ -n "$LOG_FILE" ]] && echo -e "$*" >> "$LOG_FILE"; }
info() { log "${CYAN}  »${RESET} $*"; }
dbg()  { [[ $VERBOSE -eq 1 ]] && { echo -e "${YELLOW}  ◦${RESET} $*" >&2; [[ -n "$LOG_FILE" ]] && echo -e "${YELLOW}  ◦${RESET} $*" >> "$LOG_FILE"; }; }
pass() { log "${GREEN}  ✓ PASS${RESET} — $*"; PASS=$(( PASS + 1 )); }
fail() {
    log "${RED}  ✗ FAIL${RESET} — $*"; FAIL=$(( FAIL + 1 ))
    [[ -z "$LAST_FAIL_MSG" ]] && LAST_FAIL_MSG="$*"   # keep the first failure as the report note
    if [[ $FAIL_FAST -eq 1 ]]; then
        log "${RED}  ✗ --fail-fast: stopping on first failure${RESET}"
        adapter_quit
        exit 1
    fi
}
warn() { log "${YELLOW}  ! WARN${RESET} — $*"; }
skip() { log "${YELLOW}  ~ SKIP${RESET} — $*"; SKIP=$(( SKIP + 1 )); }

# ── crash-report detection (via the adapter's crash-log dir) ─────────────────
# Some apps survive a runtime error (DRAW's FatalError stashes it and RESUME
# NEXTs), so the process stays up and assert_no_crash still passes. The only
# trace is a report file. Snapshot before each test, diff after.
_crash_snapshot() {
    CRASH_LOG_DIR="$(adapter_crashlog_dir 2>/dev/null || echo "")"
    [[ -z "$CRASH_LOG_DIR" ]] && { CRASH_N_BEFORE=0; CRASH_B_BEFORE=0; return; }
    mkdir -p "$CRASH_LOG_DIR" 2>/dev/null
    CRASH_N_BEFORE=$(ls -1 "$CRASH_LOG_DIR" 2>/dev/null | wc -l)
    CRASH_B_BEFORE=$(cat "$CRASH_LOG_DIR"/*.log 2>/dev/null | wc -c)
}

# Fails if a crash report appeared OR grew since _crash_snapshot.
assert_no_crash_log() {
    local label="${1:-no runtime errors trapped}"
    [[ -z "${CRASH_LOG_DIR:-}" ]] && { pass "$label"; return; }
    local n b
    n=$(ls -1 "$CRASH_LOG_DIR" 2>/dev/null | wc -l)
    b=$(cat "$CRASH_LOG_DIR"/*.log 2>/dev/null | wc -c)
    if [[ "$n" -gt "${CRASH_N_BEFORE:-0}" ]]; then
        fail "$label — new crash report: $(ls -1t "$CRASH_LOG_DIR" 2>/dev/null | head -1)"
    elif [[ "$b" -gt "${CRASH_B_BEFORE:-0}" ]]; then
        fail "$label — crash report grew ${CRASH_B_BEFORE:-0} -> $b bytes (error trapped)"
    else
        pass "$label"
    fi
}

# ── ETA (per-test duration history) ───────────────────────────────────────────
_record_duration() {
    mkdir -p "$RESULTS_DIR"
    printf '%s\t%s\n' "$1" "$2" >> "$DURATIONS_FILE"
}

# _record_result NAME RESULT SECS NOTES → one TSV row for THIS run (report source).
#   RESULT ∈ pass | fail | skip | cached.  Tabs/newlines in NOTES are flattened.
_record_result() {
    [[ -z "$RESULTS_TSV" ]] && return
    local notes=${4//$'\t'/ }; notes=${notes//$'\n'/ }
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$notes" >> "$RESULTS_TSV"
}

# _eta_for NAME [DEFAULT] → estimated seconds (median of the last ~10 runs).
_eta_for() {
    local name=$1 def=${2:-20} med=""
    if [[ -f "$DURATIONS_FILE" ]]; then
        med=$(awk -F'\t' -v n="$name" '
            $1==n { a[c++]=$2 }
            END {
                if (c==0) exit
                s=(c>10)?c-10:0; m=0
                for (i=s;i<c;i++) v[m++]=a[i]
                for (i=0;i<m;i++) for (j=i+1;j<m;j++) if (v[j]+0<v[i]+0){t=v[i];v[i]=v[j];v[j]=t}
                print (m%2) ? v[int(m/2)] : int((v[int(m/2)-1]+v[int(m/2)])/2)
            }' "$DURATIONS_FILE")
    fi
    [[ -n "$med" ]] && echo "$med" || echo "$def"
}

# _fmt_secs N → "m:ss"
_fmt_secs() { printf '%d:%02d' $(( $1 / 60 )) $(( $1 % 60 )); }

# ── Live status (queryable while a suite runs) ────────────────────────────────
# _write_status <phase> <i> <total> <curname> <elapsed_s> <remaining_s>
_write_status() {
    local phase=$1 i=$2 total=$3 curname=$4 elapsed=$5 remaining=$6
    mkdir -p "$RESULTS_DIR"
    local now_epoch eta_epoch eta_clock
    now_epoch=$(date +%s)
    eta_epoch=$(( now_epoch + remaining ))
    eta_clock=$(date -d "@$eta_epoch" '+%H:%M:%S' 2>/dev/null || echo "")
    printf '{"phase":"%s","current":%d,"total":%d,"test":"%s","passed":%d,"failed":%d,"skipped":%d,"elapsed_s":%d,"remaining_s":%d,"eta_epoch":%d,"eta_clock":"%s","updated":%d}\n' \
        "$phase" "$i" "$total" "$curname" "$PASS" "$FAIL" "$SKIP" \
        "$elapsed" "$remaining" "$eta_epoch" "$eta_clock" "$now_epoch" \
        > "$STATUS_JSON.tmp" && mv -f "$STATUS_JSON.tmp" "$STATUS_JSON"
    { printf 'phase      %s\n'            "$phase"
      printf 'progress   %d/%d  %s\n'     "$i" "$total" "$curname"
      printf 'results    %d passed  %d failed  %d skipped\n' "$PASS" "$FAIL" "$SKIP"
      printf 'elapsed    %s\n'            "$(_fmt_secs "$elapsed")"
      printf 'remaining  ~%s\n'           "$(_fmt_secs "$remaining")"
      printf 'eta        ~%s\n'           "${eta_clock:-?}"
    } > "$STATUS_TXT.tmp" && mv -f "$STATUS_TXT.tmp" "$STATUS_TXT"
    log "PROGRESS ${i}/${total} test=${curname} passed=${PASS} failed=${FAIL} elapsed=${elapsed}s remaining=${remaining}s eta=${eta_clock:-?} phase=${phase}"
}

# _suffix_eta START0 → sum of _TEST_ETA[] from 0-based START0 to end (seconds).
_suffix_eta() {
    local s=0 j
    for (( j=$1; j<${#_TEST_ETA[@]}; j++ )); do s=$(( s + ${_TEST_ETA[j]:-0} )); done
    echo "$s"
}

# ── test runner ───────────────────────────────────────────────────────────────
run_test_file() {
    local test_file=$1
    local name; name=$(basename "$test_file" .sh)
    CURRENT_TEST="$name"
    LAST_FAIL_MSG=""
    SNAP_SEQ=0
    if [[ $DUMP_SNAPS -eq 1 ]]; then mkdir -p "$SNAP_DUMP_DIR"; rm -f "$SNAP_DUMP_DIR/${name}-"*.png 2>/dev/null; fi
    log ""
    log "${CYAN}━━━ $name ━━━${RESET}"

    # Check passed-test cache (skip unless --rerun-passed)
    if [[ $RERUN_PASSED -eq 0 ]] && grep -qxF "$name" "$PASSED_CACHE" 2>/dev/null; then
        skip "$name — already passed (use --rerun-passed to re-run)"
        _record_result "$name" cached 0 "already passed (cache)"
        return
    fi

    # Check for SKIP marker: first non-shebang comment starting with "# SKIP:"
    local skip_reason
    skip_reason=$(sed -n '2,5{ s/^# SKIP: *//p; }' "$test_file" | head -1)
    if [[ -n "$skip_reason" ]]; then
        skip "$name — $skip_reason"
        log "  ${YELLOW}  Run manually: bin/qa --adapter <adapter> $TESTS_DIR/$name.sh${RESET}"
        _record_result "$name" skip 0 "$skip_reason"
        return
    fi

    # Track failures before this test; time the whole thing for ETA history.
    local fail_before=$FAIL
    local _t0=$SECONDS

    # Each test is atomic: fresh app instance. Re-assert the blessed cfg first —
    # the previous test's app may have written its live config back over it.
    adapter_ensure_config
    # Optional adapter hook: derive per-test launch options from the test file
    # (e.g. DRAW's `# QA-OPTIONS:` → --option overrides) before the app starts.
    if declare -F adapter_pre_launch >/dev/null; then adapter_pre_launch "$test_file"; fi
    _crash_snapshot
    adapter_launch 15
    # Source directly in the current shell — pid/wid/counters all shared.
    # shellcheck disable=SC1090
    source "$test_file"
    # Trapped runtime errors leave the app running, so this is the only automatic
    # signal that something raised during the test.
    assert_no_crash_log "$name — no runtime errors trapped"
    adapter_quit
    local _dur=$(( SECONDS - _t0 ))
    _record_duration "$name" "$_dur"
    log "${GREEN}  ► $name: done (${_dur}s)${RESET}"

    # Record in passed cache if no new failures
    if [[ $FAIL -eq $fail_before ]]; then
        mkdir -p "$RESULTS_DIR"
        echo "$name" >> "$PASSED_CACHE"
        _record_result "$name" pass "$_dur" ""
    else
        _record_result "$name" fail "$_dur" "$LAST_FAIL_MSG"
    fi
}

# ── emergency stop ────────────────────────────────────────────────────────────
_qa_stop() {
    echo "Stopping any running QA session..."
    local _me=$$ _pp=${PPID:-0} _cfg_base _killed=0 pid
    _cfg_base="$(basename "${ADAPTER_CONFIG:-}")"
    # 1) Other harness instances (not this --stop invocation or its shell).
    for pid in $(pgrep -f "bin/qa" 2>/dev/null); do
        [[ "$pid" == "$_me" || "$pid" == "$_pp" ]] && continue
        kill "$pid" 2>/dev/null && { echo "  killed harness  $pid"; _killed=1; }
    done
    # 2) The app the harness launched (identified by the blessed config in argv).
    if [[ -n "$_cfg_base" ]]; then
        for pid in $(pgrep -f "$_cfg_base" 2>/dev/null); do
            [[ "$pid" == "$_me" ]] && continue
            kill "$pid" 2>/dev/null && { echo "  killed app      $pid"; _killed=1; }
        done
    fi
    # 3) The input driver + screenshot tool the harness spawns.
    for pid in $(pgrep -x xdotool 2>/dev/null);   do kill "$pid" 2>/dev/null && _killed=1; done
    for pid in $(pgrep -x spectacle 2>/dev/null); do kill "$pid" 2>/dev/null && _killed=1; done
    sleep 0.4
    # 4) Escalate any survivors.
    if [[ -n "$_cfg_base" ]]; then
        for pid in $(pgrep -f "$_cfg_base" 2>/dev/null); do [[ "$pid" == "$_me" ]] && continue; kill -9 "$pid" 2>/dev/null; done
    fi
    for pid in $(pgrep -x xdotool 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
    [[ "$_killed" -eq 1 ]] && echo "Done — QA session stopped." || echo "Nothing running to stop."
}

_qa_help() {
    cat <<'HELP'
qa — a portable, driver/adapter GUI QA harness.

Usage:  bin/qa --adapter <adapter> [--driver linux-x11] [flags] [tests…]

Selecting tests:
  (none)                        Run every test in the adapter's tests dir
  path/to/test.sh …             Run one or several named test files (globs work)
  --list                        List available tests, then exit

Estimate & report:
  --eta [tests]                 Dry run: print per-test + total ETA, then exit
  --report [tests]              Open the rendered HTML report when the run ends
  --status [--json]             Show a running suite's progress + finish time

Run mode (shared-screen consent):
  --mode M                      M = offscreen | onscreen | ask
  --offscreen                   Invisible run under Xvfb (default when available)
  --onscreen                    Drive the real screen (warns + shows ETA first)

Debugging:
  --rerun-passed                Re-run tests that previously passed
  --keep-open                   Don't close the app after tests (debugging)
  --fail-fast                   Stop on first failure
  --verbose                     Show every mouse/key action
  --dump-snaps                  Save every compared region + a -where overlay
  --calibrate T                 Outline+label every region() in test T

Maintenance & emergency:
  --reset                       Clear the passed-test cache
  --reset-cfg                   Rebuild the blessed adapter config
  --stop                        EMERGENCY STOP a running QA session

Env: QA_XVFB_RES=WxH  QA_PROJECT=name  QA_CAPTURE=tool  QA_RESULTS_DIR=dir
HELP
}

# Remove ONLY dead runs' PNG frames from a shared screenshots dir. Snapshots and
# FAIL frames embed the runner PID (…_<PID>.png / …-<PID>.png); a run already in
# flight has that PID alive. An indiscriminate `rm *.png` at startup would delete a
# concurrently-running run's in-flight frames — and the victim's asserts then fail
# like app bugs ("regions identical", "could not read colour"), not like
# interference. So keep any file whose embedded PID is still alive; delete the rest
# (genuinely stale frames from finished/dead runs, plus non-PID cruft). This is the
# per-run isolation that makes two adapters (or two of the same) run in parallel
# safely off one shared dir; QA_RESULTS_DIR gives each run its own dir outright.
_qa_clean_dead_snaps() {
    local dir=$1 f base pid
    [[ -d "$dir" ]] || return 0
    shopt -s nullglob
    for f in "$dir"/*.png; do
        base=${f##*/}
        pid=${base%.png}; pid=${pid##*[-_]}   # trailing …<sep><PID>.png
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            continue   # a live run owns this frame — never touch it
        fi
        rm -f "$f" 2>/dev/null
    done
    shopt -u nullglob
}

# ── entrypoint ────────────────────────────────────────────────────────────────
qa_main() {
    local -a QA_ARGS=("$@")

    # Parse flags
    local _want_mode=0 arg
    for arg in "$@"; do
        if [[ $_want_mode -eq 1 ]]; then MODE="$arg"; _want_mode=0; continue; fi
        [[ "$arg" == "--keep-open" ]]    && KEEP_OPEN=1
        [[ "$arg" == "--fail-fast" ]]    && FAIL_FAST=1
        [[ "$arg" == "--verbose" ]]      && VERBOSE=1
        [[ "$arg" == "--rerun-passed" ]] && RERUN_PASSED=1
        [[ "$arg" == "--dump-snaps" ]]   && DUMP_SNAPS=1
        [[ "$arg" == "--calibrate" ]]    && { CALIBRATE=1; RERUN_PASSED=1; }
        [[ "$arg" == "--eta" ]]          && ETA=1
        [[ "$arg" == "--report" ]]       && REPORT=1
        [[ "$arg" == "--mode" ]]         && { _want_mode=1; continue; }
        [[ "$arg" == --mode=* ]]         && MODE="${arg#--mode=}"
        [[ "$arg" == "--offscreen" ]]    && MODE="offscreen"
        [[ "$arg" == "--onscreen" ]]     && MODE="onscreen"
        # Pass DRAW's own developer mode through (input conflict audit → inputs.log)
        [[ "$arg" == "--developer" ]]    && DRAW_EXTRA_ARGS="--developer"
    done

    mkdir -p "$RESULTS_DIR" "$SCREENSHOTS_DIR"
    _qa_clean_dead_snaps "$SCREENSHOTS_DIR"   # PID-scoped: never wipe a live run's frames
    [[ $CALIBRATE -eq 1 ]] && { mkdir -p "$CALIBRATE_DIR"; rm -f "$CALIBRATE_DIR"/*.png 2>/dev/null; }
    LOG_FILE="$RESULTS_DIR/run-$(date '+%Y%m%d-%H%M%S').log"
    RESULTS_TSV="${LOG_FILE%.log}.tsv"   # structured results paired with this run's log

    # ── CLI subcommands that exit ─────────────────────────────────────────────
    case "${1:-}" in
        --stop|--abort|--kill)
            _qa_stop; exit 0 ;;
        --list)
            echo "Available tests:"
            for f in "$TESTS_DIR"/*.sh; do echo "  $(basename "$f" .sh)"; done
            exit 0 ;;
        --status)
            if [[ "${2:-}" == "--json" || "${2:-}" == "json" ]]; then
                [[ -f "$STATUS_JSON" ]] && cat "$STATUS_JSON" || { echo '{"phase":"none"}'; exit 1; }
            else
                [[ -f "$STATUS_TXT" ]] && cat "$STATUS_TXT" || { echo "No run status yet (nothing has run in this results dir)."; exit 1; }
            fi
            exit 0 ;;
        --reset)
            rm -f "$PASSED_CACHE"; echo "Passed-test cache cleared."; exit 0 ;;
        --reset-cfg)
            rm -f "${ADAPTER_CONFIG:-}"; adapter_ensure_config; exit 0 ;;
        --help|-h)
            _qa_help; exit 0 ;;
    esac

    # ── Run mode: offscreen (Xvfb) vs onscreen (real-screen takeover) ─────────
    local _have_xvfb=0; driver_offscreen_available && _have_xvfb=1
    EFFECTIVE_MODE="$MODE"
    [[ -z "$EFFECTIVE_MODE" ]] && { [[ $_have_xvfb -eq 1 ]] && EFFECTIVE_MODE=offscreen || EFFECTIVE_MODE=onscreen; }
    # Already inside our own Xvfb re-exec → we ARE offscreen; never recurse.
    [[ -n "${QA_IN_XVFB:-}" ]] && EFFECTIVE_MODE=offscreen

    if [[ "$EFFECTIVE_MODE" == ask ]]; then
        if [[ $_have_xvfb -eq 0 ]]; then
            EFFECTIVE_MODE=onscreen
        elif [[ -t 0 ]]; then
            printf '» Run [O]ffscreen (invisible, Xvfb) or on[s]creen (drives your real screen)? [O/s] ' >&2
            read -r _ans
            [[ "$_ans" =~ ^[sS] ]] && EFFECTIVE_MODE=onscreen || EFFECTIVE_MODE=offscreen
        else
            EFFECTIVE_MODE=offscreen
        fi
    fi

    if [[ "$EFFECTIVE_MODE" == offscreen && $_have_xvfb -eq 0 && -z "${QA_IN_XVFB:-}" ]]; then
        warn "offscreen requested but Xvfb/xvfb-run not found — falling back to onscreen"
        EFFECTIVE_MODE=onscreen
    fi

    # Re-run under Xvfb for a truly invisible run (skip for --eta: a dry-run
    # estimate never launches anything). WAYLAND_DISPLAY is unset by the driver.
    if [[ "$EFFECTIVE_MODE" == offscreen && -z "${QA_IN_XVFB:-}" && $ETA -eq 0 ]]; then
        echo "» Offscreen: launching under Xvfb — nothing appears on your screen." >&2
        export QA_IN_XVFB=1
        driver_run_offscreen "${QA_SELF:-$0}" \
            --adapter "${QA_ADAPTER_ARG:?}" --driver "${QA_DRIVER_ARG:-linux-x11}" \
            "${QA_ARGS[@]}"
        exit $?
    fi

    command -v driver_check_deps >/dev/null 2>&1 && { driver_check_deps || exit 1; }
    _calibrate_ae
    trap 'adapter_quit' EXIT INT TERM

    # Count cached passes for banner
    local _CACHED_COUNT=0
    [[ -f "$PASSED_CACHE" ]] && _CACHED_COUNT=$(wc -l < "$PASSED_CACHE")

    log "═══════════════════════════════════════════════════"
    log " $PROJECT_NAME QA — $(date '+%Y-%m-%d %H:%M:%S')"
    log " Adapter: ${ADAPTER_NAME:-?}   Config: ${ADAPTER_CONFIG:-none}${DRAW_EXTRA_ARGS:+  Args: $DRAW_EXTRA_ARGS}"
    log " Mode: ${EFFECTIVE_MODE}${QA_IN_XVFB:+ (Xvfb)}"
    if [[ $_CACHED_COUNT -gt 0 ]]; then
        if [[ $RERUN_PASSED -eq 1 ]]; then
            log " Cache: ${_CACHED_COUNT} passed (re-running all)"
        else
            log " Cache: ${_CACHED_COUNT} already passed (--rerun-passed to redo)"
        fi
    fi
    log "═══════════════════════════════════════════════════"

    # Collect test files (skip flags)
    local -a TEST_FILES=()
    for arg in "$@"; do
        [[ "$arg" == --* ]] && continue
        # a bare --mode VALUE token (offscreen/onscreen/ask) is not a file, so the
        # -f guard below naturally skips it.
        [[ -f "$arg" ]] && TEST_FILES+=("$arg")
    done
    if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
        for f in "$TESTS_DIR"/*.sh; do
            [[ -f "$f" ]] && TEST_FILES+=("$f")
        done
    fi

    # ── ETA: estimate this run from per-test duration history ────────────────
    local _ETA_TOTAL=0 _ETA_ROWS="" _nm _e f
    _TEST_ETA=()   # per-test seconds, parallel to TEST_FILES (0 = cached-skip)
    for f in "${TEST_FILES[@]}"; do
        _nm=$(basename "$f" .sh)
        if [[ $RERUN_PASSED -eq 0 ]] && grep -qxF "$_nm" "$PASSED_CACHE" 2>/dev/null; then
            _TEST_ETA+=(0)
            _ETA_ROWS+=$(printf '   %-30s %8s  (cached — skip)\n' "$_nm" "-")
        else
            _e=$(_eta_for "$_nm")
            _TEST_ETA+=("$_e")
            _ETA_TOTAL=$(( _ETA_TOTAL + _e ))
            _ETA_ROWS+=$(printf '   %-30s %8s\n' "$_nm" "$(_fmt_secs "$_e")")
        fi
        _ETA_ROWS+=$'\n'
    done
    local _ETA_DONE; _ETA_DONE=$(date -d "+${_ETA_TOTAL} seconds" '+%H:%M:%S' 2>/dev/null)
    if [[ $CALIBRATE -eq 0 ]]; then
        log ""
        log "${CYAN}ETA — ${#TEST_FILES[@]} test(s), est. total $(_fmt_secs "$_ETA_TOTAL")${_ETA_DONE:+, done ~${_ETA_DONE}}${RESET}"
        [[ $ETA -eq 1 || $VERBOSE -eq 1 ]] && printf '%s' "$_ETA_ROWS"
    fi
    [[ $ETA -eq 1 ]] && exit 0

    # Onscreen runs drive the REAL mouse & keyboard — warn (with ETA) first.
    if [[ "$EFFECTIVE_MODE" == onscreen && -z "${QA_IN_XVFB:-}" ]]; then
        log ""
        log "${YELLOW}⚠ ONSCREEN — the harness will drive your real mouse & keyboard for ~$(_fmt_secs "$_ETA_TOTAL")${_ETA_DONE:+ (done ~${_ETA_DONE})}.${RESET}"
        log "${YELLOW}  Keep your hands off the mouse/keyboard until it finishes. Ctrl-C aborts.${RESET}"
        if [[ "$MODE" != onscreen && -t 0 ]]; then
            printf 'Proceed on the real screen? [y/N] ' >&2
            read -r _go
            [[ "$_go" =~ ^[yY] ]] || { log "Aborted — try --mode offscreen for an invisible run."; exit 130; }
        fi
    fi

    local LAST_TEST_FILE=""
    for f in "${TEST_FILES[@]}"; do LAST_TEST_FILE="$f"; done

    local ORIG_KEEP_OPEN=$KEEP_OPEN
    local RUN_T0=$SECONDS _TOTAL=${#TEST_FILES[@]} _i=0 _name
    _write_status starting 0 "$_TOTAL" "-" 0 "$_ETA_TOTAL"
    for f in "${TEST_FILES[@]}"; do
        if [[ "$f" == "$LAST_TEST_FILE" ]]; then KEEP_OPEN=$ORIG_KEEP_OPEN; else KEEP_OPEN=0; fi
        _name=$(basename "$f" .sh)
        _write_status running $(( _i + 1 )) "$_TOTAL" "$_name" \
            $(( SECONDS - RUN_T0 )) "$(_suffix_eta "$_i")"
        run_test_file "$f"
        _i=$(( _i + 1 ))
        sleep 0.5
    done
    KEEP_OPEN=$ORIG_KEEP_OPEN
    _write_status done "$_TOTAL" "$_TOTAL" "-" $(( SECONDS - RUN_T0 )) 0

    log ""
    log "═══════════════════════════════════════════════════"
    log " Results: ${GREEN}${PASS} passed${RESET}  ${RED}${FAIL} failed${RESET}  ${YELLOW}${SKIP} skipped${RESET}"
    log " Log → $LOG_FILE"
    [[ $CALIBRATE -eq 1 ]] && log " ${CYAN}Calibration frames → $CALIBRATE_DIR${RESET}"
    log "═══════════════════════════════════════════════════"

    # ── Rendered report ──────────────────────────────────────────────────────
    if [[ -s "$RESULTS_TSV" ]] && command -v python3 &>/dev/null && [[ -n "${QA_REPORT_PY:-}" ]]; then
        local REPORT_HTML="$RESULTS_DIR/report.html"
        local REPORT_JUNIT="$RESULTS_DIR/junit.xml"
        if python3 "$QA_REPORT_PY" \
                --project "$PROJECT_NAME" --run "$RESULTS_TSV" \
                --out "$REPORT_HTML" --junit "$REPORT_JUNIT" 2>/dev/null; then
            log " ${CYAN}Report → $REPORT_HTML${RESET}"
            log " ${CYAN}JUnit  → $REPORT_JUNIT${RESET}"
            [[ $REPORT -eq 1 ]] && command -v xdg-open &>/dev/null && xdg-open "$REPORT_HTML" &>/dev/null &
        fi
    fi

    [[ $FAIL -eq 0 ]]
}
