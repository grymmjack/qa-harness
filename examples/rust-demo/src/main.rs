// qa-demo — a tiny X11 GUI whose ONLY purpose is to be a test target for
// qa-harness. It has three colored buttons and a canvas; clicking a button
// (or pressing R/G/B) fills the canvas with that color, and C clears it. That
// gives the harness clean pixel regions to assert on: click a button, snap the
// canvas before/after, and `assert_regions_differ` proves the click registered.
//
// Deterministic by design: fixed 480x320 window, fixed layout, state → pixels.
// No text rendering (the harness reads pixels, not glyphs), so no font deps.

use minifb::{Key, MouseButton, MouseMode, Window, WindowOptions};

const W: usize = 480;
const H: usize = 320;

const BG: u32 = 0x101418; // window background
const CANVAS_CLEAR: u32 = 0x202830;

const RED: u32 = 0xE0392B;
const GREEN: u32 = 0x2FBF4F;
const BLUE: u32 = 0x2E7DE0;

// Button rects: x, y, w, h, color
const BUTTONS: [(usize, usize, usize, usize, u32); 3] = [
    (10, 10, 140, 60, RED),
    (170, 10, 140, 60, GREEN),
    (330, 10, 140, 60, BLUE),
];
// Canvas rect
const CANVAS: (usize, usize, usize, usize) = (10, 90, 460, 220);

fn fill_rect(buf: &mut [u32], x: usize, y: usize, w: usize, h: usize, color: u32) {
    for row in y..(y + h).min(H) {
        let base = row * W;
        for col in x..(x + w).min(W) {
            buf[base + col] = color;
        }
    }
}

fn hit(mx: usize, my: usize, r: (usize, usize, usize, usize)) -> bool {
    mx >= r.0 && mx < r.0 + r.2 && my >= r.1 && my < r.1 + r.3
}

fn render(buf: &mut [u32], canvas_color: u32) {
    for p in buf.iter_mut() {
        *p = BG;
    }
    for &(x, y, w, h, c) in BUTTONS.iter() {
        fill_rect(buf, x, y, w, h, c);
        // 2px dark inset border so adjacent buttons read as distinct regions
        fill_rect(buf, x, y, w, 2, BG);
        fill_rect(buf, x, y + h - 2, w, 2, BG);
        fill_rect(buf, x, y, 2, h, BG);
        fill_rect(buf, x + w - 2, y, 2, h, BG);
    }
    let (cx, cy, cw, ch) = CANVAS;
    fill_rect(buf, cx, cy, cw, ch, canvas_color);
}

fn main() {
    let mut buf: Vec<u32> = vec![BG; W * H];
    let mut window = Window::new(
        "qa-demo", // the harness matches this window title
        W,
        H,
        WindowOptions {
            resize: false,
            ..WindowOptions::default()
        },
    )
    .expect("failed to open X11 window");

    // ~60 fps cap; harness drives input, so responsiveness matters more than idle cost.
    window.set_target_fps(60);

    let mut canvas_color = CANVAS_CLEAR;
    let mut prev_down = false;

    while window.is_open() && !window.is_key_down(Key::Escape) && !window.is_key_down(Key::Q) {
        // Mouse: fill the canvas with a button's color on the PRESS edge.
        let down = window.get_mouse_down(MouseButton::Left);
        if down && !prev_down {
            if let Some((mx, my)) = window.get_mouse_pos(MouseMode::Discard) {
                let (mx, my) = (mx as usize, my as usize);
                for &(x, y, w, h, c) in BUTTONS.iter() {
                    if hit(mx, my, (x, y, w, h)) {
                        canvas_color = c;
                    }
                }
            }
        }
        prev_down = down;

        // Keyboard: R/G/B select, C clears — lets the harness test the key verb too.
        for key in window.get_keys_pressed(minifb::KeyRepeat::No) {
            match key {
                Key::R => canvas_color = RED,
                Key::G => canvas_color = GREEN,
                Key::B => canvas_color = BLUE,
                Key::C => canvas_color = CANVAS_CLEAR,
                _ => {}
            }
        }

        render(&mut buf, canvas_color);
        window
            .update_with_buffer(&buf, W, H)
            .expect("failed to update window");
    }
}
