#!/bin/bash
# threed.sh — a 3D model opens in the interactive viewer and orbiting repaints it.
#
# The renderer here is a hand-written CPU z-buffer rasteriser, and the reason it
# exists at all is that the thumbnailer has no GPU context — which is also why it
# can be tested under Xvfb with no GPU at all. Nothing about it is observable in
# process: the camera is a few floats, and whether those floats produced a
# different picture is only visible as pixels.
#
# Toolbar (window coords, calibrated):
#   Textured checkbox (206, 61)   Wireframe checkbox (280, 61)
#   Reset view        (90, 39)

info "=== kaleidotron: the 3D viewer renders and orbits ==="

park_mouse
kt_goto "$_KT_PLUGINS"
wait_for 3.0 "the heavy decoders finish"

click 450 122
wait_for 3.0 "03-model.obj opens in the 3D viewer"

region model 420 240 320 300 "the middle of the viewport, across the model"
region ref   420 600 320 100 "empty viewport below the model"

snap model rendered
FRONT="$SNAP_RESULT"
snap ref
assert_regions_differ "$FRONT" "$SNAP_RESULT" \
    "the model should be rasterised into the viewport"

# Orbit. A drag rotates the camera, so a differently-lit set of faces must appear
# — the strongest available evidence that the rasteriser re-ran.
drag 580 390 760 300
wait_for 1.5 "orbited"
snap model orbited
assert_regions_differ "$FRONT" "$SNAP_RESULT" \
    "dragging should orbit the camera and re-render"
ORBITED="$SNAP_RESULT"

# Wireframe is an OVERLAY composed on top of the shaded surface, still depth
# tested — so it must change the picture without replacing it.
click 280 61
wait_for 1.5 "wireframe on"
snap model wireframe
assert_regions_differ "$ORBITED" "$SNAP_RESULT" \
    "the wireframe overlay should change the render"
WIREFRAMED="$SNAP_RESULT"

# Reset view returns the camera to where it started, so the picture must come
# back — allowing for the wireframe still being on, this is asserted as a change
# away from the wireframed-and-orbited frame rather than an exact restore.
click 90 39
wait_for 1.5 "view reset"
snap model reset
assert_regions_differ "$WIREFRAMED" "$SNAP_RESULT" \
    "Reset view should move the camera back to its starting angle"

assert_window_exists
info "=== threed test done ==="
