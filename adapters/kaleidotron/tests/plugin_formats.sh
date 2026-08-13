#!/bin/bash
# plugin_formats.sh — the format PLUGINS decode and paint.
#
# The five plugins (source, PDF, audio, 3D, video) all ship OFF, so none of their
# formats appeared anywhere in this suite until now — the single largest gap in
# its coverage. Each is also the kind of path most likely to rot silently: three
# of them shell out to or link against something external, and all five are
# skipped entirely unless a flag is on.
#
# Every tile here is REAL output, not a placeholder:
#   PDF    page 1 rendered by poppler/pdfium
#   video  a frame grabbed by ffmpeg
#   3D     a CPU z-buffer rasterisation — no GPU, which is exactly why the
#          thumbnailer can do it at all
#   audio  a decoded peak envelope, device-free (Xvfb has no sound device)
#   font   glyphs rasterised through ab_glyph
#   PSD    the flattened composite
#
# When the external tool is missing the app paints a LABELLED PLACEHOLDER rather
# than failing, and a placeholder is "not blank" — so these assert on colour too.
# That is the same trap that let a .tga which could never decode sit here looking
# green.
#
# Layout in fixtures-plugins (6 files, one row): centres x = 130, 290, 450, 610,
# 770, 930; thumbnail regions at y 70.

info "=== kaleidotron: the format plugins decode and paint ==="

park_mouse
kt_goto "$_KT_PLUGINS"
# These are the heaviest decode paths in the app — poppler spawning, an ffmpeg
# frame grab, a mesh load plus rasterisation — so give the thumbnailer room.
wait_for 4.0 "the heavy decoders finish"
park_mouse

region blank  70 420 120 100 "empty background below the single row"
region pdf    70  70 120 100 "01-doc.pdf — page 1"
region video 230  70 120 100 "02-clip.mp4 — a grabbed frame"
region model 390  70 120 100 "03-model.obj — CPU-rasterised"
region audio 550  70 120 100 "04-tone.wav — waveform"
region font  710  70 120 100 "05-font.ttf — glyph preview"
region psd   870  70 120 100 "06-layered.psd — flattened composite"

snap blank
BLANK="$SNAP_RESULT"

for fmt in pdf video model audio font psd; do
    snap "$fmt"
    assert_regions_differ "$BLANK" "$SNAP_RESULT" \
        "$fmt should paint a tile (identical to blank = the plugin never decoded)"
    eval "SNAP_$fmt=\$SNAP_RESULT"
done

# Colour, so a labelled placeholder or a spinner cannot pass for real output.
kt_assert_dominant "$SNAP_video" b "the video frame is mostly blue — a placeholder tile is not"
kt_assert_dominant "$SNAP_audio" g "the waveform is drawn in the format accent colour"
kt_assert_dominant "$SNAP_psd"   b "the PSD composite is a blue field"

# …and they are not all the same placeholder.
assert_regions_differ "$SNAP_pdf"  "$SNAP_model" \
    "the PDF page and the 3D render should not paint identically"
assert_regions_differ "$SNAP_font" "$SNAP_audio" \
    "the font preview and the waveform should not paint identically"

assert_window_exists
info "=== plugin_formats test done ==="
