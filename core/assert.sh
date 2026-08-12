#!/usr/bin/env bash
# core/assert.sh — the core value: region-based VISUAL assertions, plus the named
# region registry that lets a human confirm the harness looks where they think.
#
# All portable. Bodies port from DRAW/QA/draw-qa.sh. Pixels always come from the
# driver (driver_capture_full) and are cropped here; the ImageMagick AE metric is
# QuantumRange-normalized so a "1 pixel differs" reads as 1 on any IM build.
#
# Public API tests use:
#   region NAME LX LY LW LH [desc]   declare a named logical rect (+ description)
#   snap   NAME [label]              capture that region → a snap file
#   assert_regions_differ A B [tol]  FAIL if two snaps are pixel-identical
#   assert_regions_same   A B [tol]  FAIL if two snaps differ beyond tol
# On failure, auto-emit a "-where" frame with the region boxed in red + its
# name/desc, so the human sees exactly what was compared. --calibrate outlines
# every declared region (green) up front.
#
# SKELETON: signatures below; port the working bodies from draw-qa.sh.

region()               { : ; }   # TODO port: registry + optional --calibrate outline
snap()                 { : ; }   # TODO port: resolve region → snap_region (driver crop)
assert_regions_differ(){ : ; }   # TODO port: AE diff; on fail → _emit_where_on_fail
assert_regions_same()  { : ; }   # TODO port: AE diff; on fail → _emit_where_on_fail
