#!/bin/bash
# formats.sh — every decoder family paints a real, distinct thumbnail.
#
# This is the coverage a unit test structurally cannot give. `cargo test` proves
# each decoder turns bytes into a correct `PixImage`; it stops there. It cannot
# prove the tile that lands on screen was decoded, uploaded to a texture and
# painted — a format can regress to a blank tile, a placeholder, or the wrong
# decoder's output with every unit test still green. And kittest can't see it
# either: custom-painted tiles carry no accessibility label.
#
# So: assert each tile is (a) not blank, and (b) not identical to its neighbours.
# Six formats, six painted results, all through the real thumbnailer.
#
# Grid layout (default thumb size, window-relative):
#   row 1 y 55..210 — tile n spans x = 62+(n-1)*160, 137 wide; thumb inset ~8px
#   row 2 y 223..378
# so a thumbnail-only region is (62+(n-1)*160+8, 70|238, 120x100).

info "=== kaleidotron: every format paints a distinct thumbnail ==="

# NO refresh here, deliberately. The .bas fixture is gated behind the source-code
# plugin, which the blessed settings.json enables — and it must be listed on the
# FIRST frame. kaleidotron used to read settings.json only after scanning the
# launch folder, so a plugin enabled in that file silently did nothing until the
# user pressed F5 or navigated. The `bas` assertion below is what pins the fix:
# if the ordering regresses, that tile is blank and this test fails.
#
# Any hover leaves a highlight (and, in the table, a tooltip) inside a region, so
# every baseline here is taken with the pointer parked off the content.
park_mouse

region blank    70 420 120 100 "empty background below the grid — the not-blank reference"
region png_flat 70  70 120 100 "01-red.png — plain RGB via the image crate"
region alpha   710  70 120 100 "05-alpha.png — transparency, drawn over the checkerboard"
region gif     870  70 120 100 "06-anim.gif — animated GIF, first frame"
region pcx      70 238 120 100 "07-indexed.pcx — the palette-preserving hand-written decoder"
region ans     230 238 120 100 "08-art.ans — CP437 text-mode art rasterised by ansi.rs"
region bas     390 238 120 100 "09-code.bas — source rasterised with syntax colour by code.rs"

snap blank
BLANK="$SNAP_RESULT"

# Each format must paint SOMETHING. Compared against a same-sized patch of empty
# background: `compare` only diffs the overlap of mismatched sizes, so a region
# pair of different dimensions would report a meaningless count and pass.
for fmt in png_flat alpha gif pcx ans bas; do
    snap "$fmt"
    assert_regions_differ "$BLANK" "$SNAP_RESULT" \
        "$fmt should paint a thumbnail (identical to blank = decoded to nothing)"
    eval "SNAP_$fmt=\$SNAP_RESULT"
done

# …and they must not all be the same thing. A placeholder tile, or one decoder
# silently handling another's extension, shows up here and nowhere else: every
# per-format assertion above still passes if all six render the same grey box.
assert_regions_differ "$SNAP_png_flat" "$SNAP_pcx" \
    "the PCX tile should differ from the PNG tile (same placeholder = wrong decoder)"
assert_regions_differ "$SNAP_ans" "$SNAP_bas" \
    "text-mode art and syntax-highlighted source should not paint identically"
assert_regions_differ "$SNAP_alpha" "$SNAP_gif" \
    "the transparent PNG and the GIF should not paint identically"

# Colour, not just "not blank". A thumbnail that has not decoded yet paints a
# grey SPINNER, which passes every differs-from-blank check above — that is
# exactly how a .tga that could never decode sat in this suite looking green.
kt_assert_dominant "$SNAP_png_flat" r "01-red.png should actually be red, not a spinner"
kt_assert_dominant "$SNAP_pcx"      r "the PCX tile should carry its decoded colour, not a spinner"

assert_window_exists
info "=== formats test done ==="
