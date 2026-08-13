#!/bin/bash
# tasks.sh — a project's .vscode/tasks.json is discovered, run, and reported.
#
# The parsing side is thoroughly unit tested (JSONC, platform blocks, variable
# substitution, dependency ordering). What no in-process test covers is the loop
# a person actually uses: that a tasks.json sitting beside the files makes a
# "▶ Run" menu APPEAR, that choosing an entry spawns it, and that its output is
# streamed into a panel — including that a failure is reported as one rather than
# silently swallowed.
#
# The fixture tasks.json is JSONC with a trailing comma on purpose: real
# hand-edited files have both, and `serde_json` rejects both, so the strip has to
# be exercised by a real file and not only by a unit fixture.
#
# The menu groups by `group.kind`, NOT by file order — Build, then Test, then
# Other — so a task without a group lands at the BOTTOM regardless of where it
# sits in the file:
#   ▶ Run (700,61) → Build: "QA: Say hello" (724,99)
#                    Test:  "QA: Fail on purpose" (742,142)
#                    Other: "QA: Env block" (725,186)

info "=== kaleidotron: project tasks are discovered, run and reported ==="

# A separate folder, because a discovered tasks.json adds a "▶ Tasks" entry to
# the top of every file context menu — which shifts every other entry down and
# breaks the calibrated coordinates in `fileops` and `compare`. Only this folder
# carries one.
park_mouse
kt_goto "$_KT_TASKS"
wait_for 1.0 "in the tasks fixture folder"
click 130 122
wait_for 1.5 "09-code.bas opens in the text viewer"

region toolbar 640 50 200 26  "the right end of the toolbar, where ▶ Run appears"
region panel    60 540 1000 170 "the bottom output panel"

snap panel no_panel
NO_PANEL="$SNAP_RESULT"

# The Run menu only exists because a tasks.json was found by walking up from the
# browsed folder — so opening it at all is the discovery assertion.
click 700 61
wait_for 1.0 "Run menu open"
snap toolbar menu_open
MENU="$SNAP_RESULT"

kt_click_raw 724 99
wait_for 2.5 "QA: Say hello ran"
park_mouse

snap panel ran
assert_regions_differ "$NO_PANEL" "$SNAP_RESULT" \
    "running a task should open the output panel and stream its output"
RAN="$SNAP_RESULT"

# The `env` block is kaleidotron's OWN build configuration — the replacement for
# a `${config:}` that used to read VS Code's settings.json. This task both
# SUBSTITUTES ${env:QA_TOOL} into its command line and reads $QA_MODE from the
# environment it was spawned with, so one run proves both halves reach a real
# process.
click 700 61
wait_for 1.0 "Run menu open again"
kt_click_raw 725 186
wait_for 2.5 "QA: Env block ran"
park_mouse
snap panel env_block
assert_regions_differ "$RAN" "$SNAP_RESULT" \
    "the env block should substitute into the command AND reach the process"
RAN="$SNAP_RESULT"

# A failing task must look different from a successful one — the panel reports
# the exit status, so "it ran" and "it worked" are not the same claim.
click 700 61
wait_for 1.0 "Run menu open again"
kt_click_raw 742 142
wait_for 2.5 "QA: Fail on purpose ran and exited 3"
park_mouse

snap panel failed
assert_regions_differ "$RAN" "$SNAP_RESULT" \
    "a failing task should report differently from a successful one"

assert_window_exists
info "=== tasks test done ==="
