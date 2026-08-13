#!/bin/bash
# fileops.sh — file operations repaint the listing, and undo really restores.
#
# The operations are ordinary filesystem calls; what is worth testing end to end
# is the loop around them — that the grid re-scans and repaints after each one,
# and that Ctrl+Z restores a trashed file rather than merely popping an entry off
# an undo stack. `assert_regions_same` after the undo is the strong form of that
# claim: not "a file came back" but "the listing is pixel-identical to before".
#
# Safe to run because the app is pointed at a per-launch COPY of the fixtures in
# the sandbox, never the originals in the repository — isolation added after this
# suite was caught writing rating xattrs onto the repo's own fixtures.
#
# Menu coordinates are read off calibration captures. On a file tile right-clicked
# at (130,122): Move to trash sits at (180,381). On empty space right-clicked at
# (700,600): New folder sits at (746,637).

info "=== kaleidotron: file operations repaint, and Ctrl+Z restores ==="

park_mouse
region row1 60 50 1000 165 "the first row of tiles"

snap row1 before
BEFORE="$SNAP_RESULT"

# ── Trash the first file ────────────────────────────────────────────────────
right_click 130 122
wait_for 0.8 "context menu on 01-red.png"
click 180 381
wait_for 1.8 "moved to trash, listing re-scanned"
park_mouse

snap row1 after_trash
assert_regions_differ "$BEFORE" "$SNAP_RESULT" \
    "trashing a file should remove it and re-lay-out the row"

# ── …and undo brings it back, exactly ───────────────────────────────────────
key ctrl+z
wait_for 1.8 "undo — the file is restored from the trash"
park_mouse

snap row1 after_undo
assert_regions_same "$BEFORE" "$SNAP_RESULT" \
    "Ctrl+Z should restore the trashed file and the listing with it"

# ── New folder ──────────────────────────────────────────────────────────────
# Folders sort first, so a new one is unmistakable: every tile shifts along.
right_click 700 600
wait_for 0.8 "context menu on empty space"
click 746 637
wait_for 1.2 "folder created, name in an inline editor"
key Return
wait_for 1.8 "name committed, listing re-scanned"
park_mouse

snap row1 after_new_folder
assert_regions_differ "$BEFORE" "$SNAP_RESULT" \
    "creating a folder should repaint the listing (folders sort first)"

assert_window_exists
info "=== fileops test done ==="
