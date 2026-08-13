#!/bin/bash
# formats2.sh — the second half of the decoder matrix paints, too.
#
# Companion to formats.sh, split only so one launch does not have to cover
# fourteen fixtures. Same reasoning: `cargo test` proves each decoder produces a
# correct PixImage and stops there — it cannot prove the tile that lands on
# screen was decoded, uploaded and painted. A format can regress to a blank tile,
# a placeholder, or another decoder's output with every unit test still green.
#
# These are the formats with no external dependency, so they run anywhere:
# resvg (.svg), the image crate's bmp/tga/qoi/ico, and the two BINARY text-mode
# decoders. The plugin-gated ones (PDF, audio, 3D, video) are deliberately out of
# scope — see the coverage inventory in README.md.
#
# Grid layout: tile n of row r spans x = 62+(n-1)*160, 137 wide;
#   row 1 y 55..210 (thumb region y 70), row 2 y 223..378 (thumb y 238),
#   row 3 y 391..546 (thumb y 406).

info "=== kaleidotron: the rest of the decoder matrix paints ==="

park_mouse

region blank   70 570 120 100 "empty background below the grid — the not-blank reference"
region svg    550 238 120 100 "10-vector.svg — rasterised by resvg"
region bmp    710 238 120 100 "11-bitmap.bmp"
region tga    870 238 120 100 "12-targa.tga"
region qoi     70 406 120 100 "13-quite.qoi"
region ico    230 406 120 100 "14-icon.ico"
region bin    390 406 120 100 "15-attr.bin — raw char/attr pairs"
region xbin   550 406 120 100 "16-xbin.xb — XBin container"

snap blank
BLANK="$SNAP_RESULT"

for fmt in svg bmp tga qoi ico bin xbin; do
    snap "$fmt"
    assert_regions_differ "$BLANK" "$SNAP_RESULT" \
        "$fmt should paint a thumbnail (identical to blank = decoded to nothing)"
    eval "SNAP_$fmt=\$SNAP_RESULT"
done

# …and they are not all the same placeholder. Every per-format check above still
# passes if all seven render an identical grey box, so cross-check a few pairs
# that exercise genuinely different code paths.
assert_regions_differ "$SNAP_svg" "$SNAP_bmp" \
    "the vector rasteriser and the bitmap decoder should not paint identically"
assert_regions_differ "$SNAP_qoi" "$SNAP_ico" \
    "QOI and ICO should not paint identically"
assert_regions_differ "$SNAP_bin" "$SNAP_xbin" \
    "the raw .bin and the XBin container should not paint identically"

# And each tile must be the COLOUR its fixture is, not merely non-blank. This is
# the check that matters: an undecoded thumbnail paints a grey spinner, which is
# "different from blank" and sailed through the assertions above — that is how a
# .tga that could never decode at all (no magic bytes, so the format could not be
# guessed) sat here looking green.
kt_assert_dominant "$SNAP_tga"  b "the TGA tile should be its blue field, not a spinner"
kt_assert_dominant "$SNAP_bmp"  r "the BMP tile should be its orange-red field"
kt_assert_dominant "$SNAP_qoi"  g "the QOI tile should be its green field"
# The binary text-mode formats store RAW VGA ATTRIBUTE bytes, where 4 is red and
# 2 is green — but in the ANSI SGR ordering used by .ans those same indices are
# BLUE and green. Handing a binary decoder the SGR palette silently swaps red and
# blue across an entire piece (the MULTI-13.BIN bug). "It changed" cannot catch
# that; "it is red" can.
kt_assert_dominant "$SNAP_bin"  r "15-attr.bin uses VGA attribute 4 — it must render RED, not blue"
kt_assert_dominant "$SNAP_xbin" g "16-xbin.xb uses VGA attribute 2 — it must render GREEN"

assert_window_exists
info "=== formats2 test done ==="
