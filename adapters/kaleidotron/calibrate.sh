#!/usr/bin/env bash
# calibrate.sh — capture kaleidotron's window OFFSCREEN, to measure coordinates
# for new tests without putting a window on anyone's screen.
#
# Writing a region test means knowing where things are, and the obvious way to
# find out — launch the app and look — takes over the developer's display. This
# does the same thing inside Xvfb: launch in the QA sandbox, optionally drive it
# with xdotool, screenshot the window, and leave a PNG to open.
#
#   ./calibrate.sh out.png                          # just the initial grid
#   ./calibrate.sh out.png 'key t' 'sleep 0.5'      # after some input
#   ./calibrate.sh out.png 'mousemove 130 122' 'click 1'
#
# Each argument after the output file is an xdotool command, run in order against
# the app window, with window-relative coordinates for mousemove. `sleep N` is
# handled here rather than passed to xdotool.
set -uo pipefail

OUT="${1:?usage: calibrate.sh OUT.png [xdotool cmd...]}"; shift || true
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KT_ROOT="${KALEIDOTRON_ROOT:-$HOME/git/kaleidotron}"
KT_BIN="$KT_ROOT/target/release/kaleidotron"
FIXTURES="${KT_FIXTURES:-$HERE/fixtures}"
SANDBOX=/tmp/kaleidotron-cal-home
DISP="${CAL_DISPLAY:-:97}"
RES="${CAL_RES:-1400x900x24}"

[[ -x "$KT_BIN" ]] || { echo "build it: (cd $KT_ROOT && cargo build --release)" >&2; exit 1; }

rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"/{config,data,cache}
# Any settings.json placed here by the caller is preserved — that is how a test
# needing a non-default app state (a format plugin on, say) gets calibrated.
[[ -n "${CAL_SETTINGS:-}" ]] && { mkdir -p "$SANDBOX/data/kaleidotron"; cp "$CAL_SETTINGS" "$SANDBOX/data/kaleidotron/settings.json"; }

cleanup() {
    [[ -n "${KT_PID:-}"  ]] && kill "$KT_PID"  2>/dev/null
    [[ -n "${WM_PID:-}"  ]] && kill "$WM_PID"  2>/dev/null
    [[ -n "${XVFB_PID:-}" ]] && kill "$XVFB_PID" 2>/dev/null
}
trap cleanup EXIT

# Refuse to reuse a display someone else owns — starting a second Xvfb on a live
# :N fails, and the app would then fall back to whatever DISPLAY resolves to.
if DISPLAY="$DISP" xdpyinfo >/dev/null 2>&1; then
    echo "$DISP is already in use — set CAL_DISPLAY to a free one" >&2; exit 1
fi
Xvfb "$DISP" -screen 0 "$RES" >/dev/null 2>&1 & XVFB_PID=$!
sleep 1
# openbox matches what the driver does offscreen: it assigns input focus, which
# a bare X server does not, and undecorates so geometry matches the real window.
DISPLAY="$DISP" openbox --config-file "$HERE/../../drivers/linux-x11/openbox-rc.xml" >/dev/null 2>&1 & WM_PID=$!
sleep 1

# `env -u WAYLAND_DISPLAY` is LOAD-BEARING, not hygiene. kaleidotron is winit, and
# winit prefers Wayland whenever WAYLAND_DISPLAY is set — it will ignore DISPLAY
# entirely and open a window on the developer's REAL compositor, while every
# xdotool search against the Xvfb display finds nothing and this script reports
# "window never appeared". Confirmed the hard way. WINIT_UNIX_BACKEND=x11 is the
# belt to that braces.
env -u WAYLAND_DISPLAY \
    DISPLAY="$DISP" WINIT_UNIX_BACKEND=x11 HOME="$SANDBOX" \
    XDG_CONFIG_HOME="$SANDBOX/config" XDG_DATA_HOME="$SANDBOX/data" XDG_CACHE_HOME="$SANDBOX/cache" \
    "$KT_BIN" --folder "$FIXTURES" >/dev/null 2>/tmp/kt-cal-stderr.log & KT_PID=$!

for _ in $(seq 1 100); do
    WID=$(DISPLAY="$DISP" xdotool search --pid "$KT_PID" --name kaleidotron 2>/dev/null | head -1)
    [[ -n "$WID" ]] && break
    sleep 0.1
done
[[ -n "${WID:-}" ]] || { echo "window never appeared; stderr:"; cat /tmp/kt-cal-stderr.log; exit 1; }
sleep 1.5   # first frame: fonts, thumbnail decode

read -r WX WY WW WH < <(DISPLAY="$DISP" xdotool getwindowgeometry --shell "$WID" |
    sed -n 's/^X=\(.*\)/\1/p;s/^Y=\(.*\)/\1/p;s/^WIDTH=\(.*\)/\1/p;s/^HEIGHT=\(.*\)/\1/p' | paste -sd' ')
echo "window ${WW}x${WH} at +${WX}+${WY}"

DISPLAY="$DISP" xdotool windowfocus --sync "$WID" 2>/dev/null || true
DISPLAY="$DISP" xdotool windowraise "$WID" 2>/dev/null || true

for cmd in "$@"; do
    case "$cmd" in
        sleep*) sleep "${cmd#sleep }" ;;
        # Window-relative coords, like the adapter's logical→screen map.
        mousemove*)
            set -- $cmd
            DISPLAY="$DISP" xdotool mousemove $(( WX + $2 )) $(( WY + $3 ))
            ;;
        *) DISPLAY="$DISP" xdotool $cmd ;;
    esac
    sleep 0.25
done
sleep 0.6

DISPLAY="$DISP" import -window "$WID" "$OUT" 2>/dev/null ||
    DISPLAY="$DISP" xwd -id "$WID" | xwdtopnm 2>/dev/null | pnmtopng > "$OUT"
echo "wrote $OUT"
[[ -s /tmp/kt-cal-stderr.log ]] && { echo "--- app stderr ---"; cat /tmp/kt-cal-stderr.log; }
exit 0
