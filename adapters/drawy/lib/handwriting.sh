#!/bin/bash
# Pen-writing helpers for the handwriting tests (sourced, not run).

# pen_stroke x1 y1 x2 y2 ... — one pen stroke through the points
pen_stroke() {
    mouse_down "$1" "$2"; shift 2
    while (( $# >= 2 )); do hover "$1" "$2"; sleep 0.03; shift 2; done
    mouse_up
}

# write_hello — HELLO with the pen, letters 60px tall, from (300,300) to about (552,360)
write_hello() {
    key p
    local Y=300 X pts a
    X=300; pen_stroke $X $Y $X $((Y+60)); pen_stroke $((X+36)) $Y $((X+36)) $((Y+60)); pen_stroke $X $((Y+30)) $((X+36)) $((Y+30))
    X=354; pen_stroke $((X+36)) $Y $X $Y $X $((Y+60)) $((X+36)) $((Y+60)); pen_stroke $X $((Y+30)) $((X+27)) $((Y+30))
    X=408; pen_stroke $X $Y $X $((Y+60)) $((X+36)) $((Y+60))
    X=462; pen_stroke $X $Y $X $((Y+60)) $((X+36)) $((Y+60))
    X=516; pts=""
    for a in $(seq 0 15 360); do
        pts+=" $(python3 -c "import math;print(round($X+18+18*math.cos(math.radians($a))), round($Y+30+30*math.sin(math.radians($a))))")"
    done
    pen_stroke $pts
    key s
}

# convert_selection — right-click and choose Convert Handwriting to Text
# (the fourth entry: Copy, Paste, Delete, Convert Handwriting to Text)
convert_selection() {
    right_click 700 600
    wait_for 0.8 "context menu"
    click 812 676
}
