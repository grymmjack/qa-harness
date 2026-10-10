// qa-io (macOS) - the qa-harness's OS input / window helper for macOS.
//
// Same command line as drivers/windows/qa-io.cs; drivers/macos/driver.sh wraps it.
// Coordinates are SCREEN PIXELS of the main display (what `screencapture` gives),
// converted to points for events and window bounds on a Retina screen.
// Key names are xdotool keysyms (the harness's language): a..z, 0..9, F1..F12,
// Return Escape BackSpace Delete Tab space Home End Prior/Page_Up Next/Page_Down
// Left Right Up Down, punctuation names (slash question grave bracketleft ...),
// modifiers ctrl shift alt super (super = Command).
//
//   qa-io move X Y | moverel DX DY | down B | up B | click B      (B: 1 left, 2 middle, 3 right)
//   qa-io keydown K | keyup K | key COMBO (ctrl+shift+n) | type TEXT
//   qa-io scroll up|down [N]
//   qa-io serve | stop | ping   (one long-lived process posts all input - see serve())
//   qa-io reset                 (forget held buttons / modifiers - kept in ~/.qa-runner/io-state between calls)
//   qa-io find PID TITLE        -> window id ("" pid = any process)
//   qa-io title ID | bounds ID (-> "X Y W H" px, frame) | client ID (frame minus the title bar)
//   qa-io activate ID | pid ID | titlebar (-> px)
//   qa-io seq TOKENS...         (move X Y, moverel DX DY, down B, up B, key K, keydown K, keyup K)
//   qa-io scale                 -> backing scale of the main display
//
// Needs Accessibility (events, activate) and Screen Recording (window titles)
// for the process that runs it - see drivers/macos/README.md.
//
// Build: clang -O2 -o qa-io qa-io.c -framework ApplicationServices -framework CoreFoundation -framework AppKit
#include <ApplicationServices/ApplicationServices.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <signal.h>
#include <errno.h>
#include <stdarg.h>

static double g_scale = 1.0;
static CGEventSourceRef g_src;

static void ms(int n) { usleep((useconds_t)n * 1000); }

static double display_scale(void) {
    CGDirectDisplayID d = CGMainDisplayID();
    CGDisplayModeRef m = CGDisplayCopyDisplayMode(d);
    double s = 1.0;
    if (m) {
        size_t pw = CGDisplayModeGetPixelWidth(m), w = CGDisplayModeGetWidth(m);
        if (w > 0) s = (double)pw / (double)w;
        CGDisplayModeRelease(m);
    }
    return s > 0 ? s : 1.0;
}

static CGPoint px_to_pt(double x, double y) { return CGPointMake(x / g_scale, y / g_scale); }

static CGPoint cur_pt(void) {
    CGEventRef e = CGEventCreate(NULL);
    CGPoint p = CGEventGetLocation(e);
    CFRelease(e);
    return p;
}

// Held buttons and modifiers, kept in a small file between qa-io runs. Each
// call is its own process, and the HID system state only reflects real
// hardware - so without this a move after `down 1` went out as a plain
// mouseMoved (no drag) and a held modifier could drop out of later events.
static unsigned long st_buttons; static CGEventFlags st_flags; static int st_loaded;
static const char *st_path(void) {
    static char p[1024]; const char *h = getenv("HOME");
    snprintf(p, sizeof p, "%s/.qa-runner/io-state", h ? h : "/tmp"); return p;
}
static void st_load(void) {
    if (st_loaded) return;
    st_loaded = 1;
    FILE *f = fopen(st_path(), "r");
    if (f) { unsigned long long fl = 0; if (fscanf(f, "%lu %llu", &st_buttons, &fl) == 2) st_flags = (CGEventFlags)fl; fclose(f); }
}
static void st_save(void) {
    FILE *f = fopen(st_path(), "w");
    if (f) { fprintf(f, "%lu %llu\n", st_buttons, (unsigned long long)st_flags); fclose(f); }
}
static CGEventFlags cur_flags(void) {
    st_load();
    return CGEventSourceFlagsState(kCGEventSourceStateHIDSystemState) | st_flags;
}

// ── keys ─────────────────────────────────────────────────────────────────────
typedef struct { const char *name; int code; int shift; } KeyDef;
static const KeyDef KEYS[] = {
    {"a",0x00,0},{"s",0x01,0},{"d",0x02,0},{"f",0x03,0},{"h",0x04,0},{"g",0x05,0},{"z",0x06,0},{"x",0x07,0},
    {"c",0x08,0},{"v",0x09,0},{"b",0x0B,0},{"q",0x0C,0},{"w",0x0D,0},{"e",0x0E,0},{"r",0x0F,0},{"y",0x10,0},
    {"t",0x11,0},{"1",0x12,0},{"2",0x13,0},{"3",0x14,0},{"4",0x15,0},{"6",0x16,0},{"5",0x17,0},{"equal",0x18,0},
    {"9",0x19,0},{"7",0x1A,0},{"minus",0x1B,0},{"8",0x1C,0},{"0",0x1D,0},{"bracketright",0x1E,0},{"o",0x1F,0},
    {"u",0x20,0},{"bracketleft",0x21,0},{"i",0x22,0},{"p",0x23,0},{"Return",0x24,0},{"Enter",0x24,0},{"l",0x25,0},
    {"j",0x26,0},{"apostrophe",0x27,0},{"k",0x28,0},{"semicolon",0x29,0},{"backslash",0x2A,0},{"comma",0x2B,0},
    {"slash",0x2C,0},{"n",0x2D,0},{"m",0x2E,0},{"period",0x2F,0},{"Tab",0x30,0},{"space",0x31,0},{"grave",0x32,0},
    {"BackSpace",0x33,0},{"Escape",0x35,0},{"Home",0x73,0},{"Prior",0x74,0},{"Page_Up",0x74,0},{"Delete",0x75,0},
    {"End",0x77,0},{"Next",0x79,0},{"Page_Down",0x79,0},{"Left",0x7B,0},{"Right",0x7C,0},{"Down",0x7D,0},{"Up",0x7E,0},
    {"F1",0x7A,0},{"F2",0x78,0},{"F3",0x63,0},{"F4",0x76,0},{"F5",0x60,0},{"F6",0x61,0},{"F7",0x62,0},{"F8",0x64,0},
    {"F9",0x65,0},{"F10",0x6D,0},{"F11",0x67,0},{"F12",0x6F,0},
    // shifted punctuation (xdotool keysym names)
    {"question",0x2C,1},{"greater",0x2F,1},{"less",0x2B,1},{"asterisk",0x1C,1},{"braceleft",0x21,1},
    {"braceright",0x1E,1},{"numbersign",0x14,1},{"plus",0x18,1},{"underscore",0x1B,1},{"colon",0x29,1},
    {"quotedbl",0x27,1},{"exclam",0x12,1},{"at",0x13,1},{"dollar",0x15,1},{"percent",0x17,1},
    {"asciicircum",0x16,1},{"ampersand",0x1A,1},{"parenleft",0x19,1},{"parenright",0x1D,1},{"bar",0x2A,1},
    {"asciitilde",0x32,1},
    {NULL,0,0}
};

typedef struct { const char *name; int code; CGEventFlags mask; } ModDef;
static const ModDef MODS[] = {
    {"ctrl",0x3B,kCGEventFlagMaskControl},{"control",0x3B,kCGEventFlagMaskControl},{"Control_L",0x3B,kCGEventFlagMaskControl},
    {"shift",0x38,kCGEventFlagMaskShift},{"Shift_L",0x38,kCGEventFlagMaskShift},
    {"alt",0x3A,kCGEventFlagMaskAlternate},{"Alt_L",0x3A,kCGEventFlagMaskAlternate},{"option",0x3A,kCGEventFlagMaskAlternate},
    {"super",0x37,kCGEventFlagMaskCommand},{"Super_L",0x37,kCGEventFlagMaskCommand},{"command",0x37,kCGEventFlagMaskCommand},
    {"cmd",0x37,kCGEventFlagMaskCommand},{"meta",0x37,kCGEventFlagMaskCommand},
    {NULL,0,0}
};

static const ModDef *find_mod(const char *n) {
    for (int i = 0; MODS[i].name; i++) if (!strcasecmp(MODS[i].name, n)) return &MODS[i];
    return NULL;
}

// a key name -> code (+ needs shift); single upper-case letters are shift + letter
static int find_key(const char *n, int *code, int *shift) {
    for (int i = 0; KEYS[i].name; i++) if (!strcmp(KEYS[i].name, n)) { *code = KEYS[i].code; *shift = KEYS[i].shift; return 1; }
    if (strlen(n) == 1 && n[0] >= 'A' && n[0] <= 'Z') {
        char lc[2] = { (char)(n[0] - 'A' + 'a'), 0 };
        for (int i = 0; KEYS[i].name; i++) if (!strcmp(KEYS[i].name, lc)) { *code = KEYS[i].code; *shift = 1; return 1; }
    }
    for (int i = 0; KEYS[i].name; i++) if (!strcasecmp(KEYS[i].name, n)) { *code = KEYS[i].code; *shift = KEYS[i].shift; return 1; }
    return 0;
}

static void post_mod(const ModDef *m, int down) {
    CGEventRef e = CGEventCreateKeyboardEvent(g_src, (CGKeyCode)m->code, down);
    CGEventFlags f = cur_flags();
    f = down ? (f | m->mask) : (f & ~m->mask);
    st_flags = down ? (st_flags | m->mask) : (st_flags & ~m->mask); st_save();
    CGEventSetType(e, kCGEventFlagsChanged);
    CGEventSetFlags(e, f);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

static int key_updown(const char *n, int down, CGEventFlags extra) {
    const ModDef *m = find_mod(n);
    if (m) { post_mod(m, down); return 0; }
    int code, shift;
    if (!find_key(n, &code, &shift)) { fprintf(stderr, "qa-io: unknown key '%s'\n", n); return 2; }
    CGEventRef e = CGEventCreateKeyboardEvent(g_src, (CGKeyCode)code, down);
    CGEventFlags f = cur_flags() | extra | (shift ? kCGEventFlagMaskShift : 0);
    CGEventSetFlags(e, f);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
    return 0;
}

// ctrl+shift+n: hold each modifier (~60ms), tap the base (200ms), release in reverse
// - the same timing as the X11 driver so an app polling its key state sees it
static int key_combo(const char *combo) {
    char buf[256]; strncpy(buf, combo, sizeof buf - 1); buf[sizeof buf - 1] = 0;
    char *parts[16]; int n = 0;
    for (char *t = strtok(buf, "+"); t && n < 16; t = strtok(NULL, "+")) parts[n++] = t;
    if (n == 0) return 2;
    if (n == 1) { int r = key_updown(parts[0], 1, 0); ms(100); key_updown(parts[0], 0, 0); ms(50); return r; }
    for (int i = 0; i < n - 1; i++) { const ModDef *m = find_mod(parts[i]); if (!m) { fprintf(stderr, "qa-io: not a modifier '%s'\n", parts[i]); return 2; } post_mod(m, 1); ms(60); }
    ms(60);
    int r = key_updown(parts[n - 1], 1, 0); ms(200); key_updown(parts[n - 1], 0, 0); ms(40);
    for (int i = n - 2; i >= 0; i--) post_mod(find_mod(parts[i]), 0);
    ms(50);
    return r;
}

static void type_text(const char *s) {
    // one UTF-16 unit per char - the app gets the character, whatever the layout
    CFStringRef str = CFStringCreateWithCString(NULL, s, kCFStringEncodingUTF8);
    CFIndex len = CFStringGetLength(str);
    for (CFIndex i = 0; i < len; i++) {
        UniChar c = CFStringGetCharacterAtIndex(str, i);
        for (int down = 1; down >= 0; down--) {
            CGEventRef e = CGEventCreateKeyboardEvent(g_src, 0, down);
            CGEventKeyboardSetUnicodeString(e, 1, &c);
            CGEventPost(kCGHIDEventTap, e);
            CFRelease(e);
        }
        ms(30);
    }
    CFRelease(str);
}

// ── mouse ────────────────────────────────────────────────────────────────────
static int held_button(void) {
    st_load();
    if (st_buttons & 1) return 1;
    if (st_buttons & 4) return 3;
    if (st_buttons & 2) return 2;
    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonLeft)) return 1;
    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonRight)) return 3;
    if (CGEventSourceButtonState(kCGEventSourceStateHIDSystemState, kCGMouseButtonCenter)) return 2;
    return 0;
}

static void mouse_at(CGPoint p) {
    int b = held_button();
    CGEventType t = kCGEventMouseMoved; CGMouseButton mb = kCGMouseButtonLeft;
    if (b == 1) t = kCGEventLeftMouseDragged;
    else if (b == 3) { t = kCGEventRightMouseDragged; mb = kCGMouseButtonRight; }
    else if (b == 2) { t = kCGEventOtherMouseDragged; mb = kCGMouseButtonCenter; }
    // a real move event WITH its delta - apps (GLFW: the cursor-position
    // callback) track the pointer from these; a warp alone sends no event and a
    // zero-delta move after a warp can be dropped, leaving the app's idea of the
    // pointer stale (the click then lands where the app last saw it)
    CGPoint from = cur_pt();
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, mb);   // no source, as cliclick does
    CGEventSetIntegerValueField(e, kCGMouseEventDeltaX, (int64_t)(p.x - from.x));
    CGEventSetIntegerValueField(e, kCGMouseEventDeltaY, (int64_t)(p.y - from.y));
    CGEventSetFlags(e, cur_flags());
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
    // if the cursor itself did not follow, place it (the app already has the event)
    usleep(4000);
    CGPoint now = cur_pt();
    if (fabs(now.x - p.x) > 0.5 || fabs(now.y - p.y) > 0.5) CGWarpMouseCursorPosition(p);
}

static int button(int b, int down) {
    CGEventType t; CGMouseButton mb;
    switch (b) {
        case 1: t = down ? kCGEventLeftMouseDown : kCGEventLeftMouseUp; mb = kCGMouseButtonLeft; break;
        case 3: t = down ? kCGEventRightMouseDown : kCGEventRightMouseUp; mb = kCGMouseButtonRight; break;
        case 2: t = down ? kCGEventOtherMouseDown : kCGEventOtherMouseUp; mb = kCGMouseButtonCenter; break;
        default: fprintf(stderr, "qa-io: button %d?\n", b); return 2;
    }
    st_load();
    unsigned long bit = 1UL << (b - 1);
    st_buttons = down ? (st_buttons | bit) : (st_buttons & ~bit); st_save();
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, cur_pt(), mb);
    CGEventSetIntegerValueField(e, kCGMouseEventClickState, 1);   // a single click (0 = not a click for AppKit)
    CGEventSetFlags(e, cur_flags());
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
    return 0;
}

static void scroll(int up, int n) {
    for (int i = 0; i < n; i++) {
        CGEventRef e = CGEventCreateScrollWheelEvent(g_src, kCGScrollEventUnitLine, 1, up ? 1 : -1);
        CGEventPost(kCGHIDEventTap, e);
        CFRelease(e);
        ms(20);
    }
}

// ── windows ──────────────────────────────────────────────────────────────────
static CFArrayRef win_list(void) {
    return CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
}

static long dict_long(CFDictionaryRef d, CFStringRef k) {
    long v = 0; CFNumberRef n = CFDictionaryGetValue(d, k);
    if (n) CFNumberGetValue(n, kCFNumberLongType, &v);
    return v;
}

static int dict_str(CFDictionaryRef d, CFStringRef k, char *out, size_t cap) {
    out[0] = 0; CFStringRef s = CFDictionaryGetValue(d, k);
    return s && CFStringGetCString(s, out, (CFIndex)cap, kCFStringEncodingUTF8);
}

static CFDictionaryRef find_win(CFArrayRef a, long id) {
    for (CFIndex i = 0; i < CFArrayGetCount(a); i++) {
        CFDictionaryRef d = CFArrayGetValueAtIndex(a, i);
        if (dict_long(d, kCGWindowNumber) == id) return d;
    }
    return NULL;
}

static int cmd_find(const char *pid, const char *title) {
    CFArrayRef a = win_list(); long want = (pid && *pid) ? atol(pid) : 0;
    char name[512];
    for (CFIndex i = 0; i < CFArrayGetCount(a); i++) {
        CFDictionaryRef d = CFArrayGetValueAtIndex(a, i);
        if (dict_long(d, kCGWindowLayer) != 0) continue;
        if (want && dict_long(d, kCGWindowOwnerPID) != want) continue;
        dict_str(d, kCGWindowName, name, sizeof name);
        if (title && *title && !strstr(name, title)) continue;
        printf("%ld\n", dict_long(d, kCGWindowNumber));
        CFRelease(a); return 0;
    }
    CFRelease(a); return 1;
}

static int cmd_title(long id) {
    CFArrayRef a = win_list(); CFDictionaryRef d = find_win(a, id); char name[512];
    if (!d) { CFRelease(a); return 1; }
    dict_str(d, kCGWindowName, name, sizeof name); printf("%s\n", name);
    CFRelease(a); return 0;
}

// The standard title bar's height in points, from AppKit itself
// (+[NSWindow frameRectForContentRect:styleMask:] for a titled window) - it
// changes between macOS versions (28pt, 32pt on macOS 26).
static double titlebar_pt(void) {
    typedef CGRect (*FrFn)(id, SEL, CGRect, unsigned long);
    Class cls = objc_getClass("NSWindow");
    if (!cls) return 28.0;
    CGRect fr = ((FrFn)objc_msgSend)((id)cls, sel_registerName("frameRectForContentRect:styleMask:"),
                                     CGRectMake(0, 0, 100, 100), (unsigned long)(1 | 2 | 4));
    double tb = fr.size.height - 100.0;
    return tb > 0 && tb < 200 ? tb : 28.0;
}

static int cmd_client(long id) {
    CFArrayRef a = win_list(); CFDictionaryRef d = find_win(a, id);
    if (!d) { CFRelease(a); puts("0 0 0 0"); return 1; }
    CGRect r; CFDictionaryRef b = CFDictionaryGetValue(d, kCGWindowBounds);
    CGRectMakeWithDictionaryRepresentation(b, &r);
    double tb = titlebar_pt();
    printf("%ld %ld %ld %ld\n", (long)(r.origin.x * g_scale + .5), (long)((r.origin.y + tb) * g_scale + .5),
           (long)(r.size.width * g_scale + .5), (long)((r.size.height - tb) * g_scale + .5));
    CFRelease(a); return 0;
}

static int cmd_bounds(long id) {
    CFArrayRef a = win_list(); CFDictionaryRef d = find_win(a, id);
    if (!d) { CFRelease(a); puts("0 0 0 0"); return 1; }
    CGRect r; CFDictionaryRef b = CFDictionaryGetValue(d, kCGWindowBounds);
    CGRectMakeWithDictionaryRepresentation(b, &r);
    printf("%ld %ld %ld %ld\n", (long)(r.origin.x * g_scale + .5), (long)(r.origin.y * g_scale + .5),
           (long)(r.size.width * g_scale + .5), (long)(r.size.height * g_scale + .5));
    CFRelease(a); return 0;
}

static long win_pid(long id) {
    CFArrayRef a = win_list(); CFDictionaryRef d = find_win(a, id);
    long p = d ? dict_long(d, kCGWindowOwnerPID) : 0;
    CFRelease(a); return p;
}

static int cmd_activate(long wid) {
    long pid = win_pid(wid);
    if (!pid) return 1;
    // LaunchServices activation, not just the AX frontmost flag: a GLFW app
    // spawned by QA Runner reads as frontmost but gets NO mouseMoved events (so
    // clicks land wherever the cursor last was) until it is activated this way.
    typedef id (*AppFn)(id, SEL, int);
    typedef BOOL (*ActFn)(id, SEL, unsigned long);
    id ra = ((AppFn)objc_msgSend)((id)objc_getClass("NSRunningApplication"),
                                  sel_registerName("runningApplicationWithProcessIdentifier:"), (int)pid);
    if (ra) ((ActFn)objc_msgSend)(ra, sel_registerName("activateWithOptions:"), 1UL | 2UL);  // all windows | ignoring other apps
    AXUIElementRef app = AXUIElementCreateApplication((pid_t)pid);
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute, kCFBooleanTrue);
    CFRelease(app);
    ms(80);
    return 0;
}

// ── seq ──────────────────────────────────────────────────────────────────────
static int run_seq(int argc, char **argv) {
    for (int i = 0; i < argc; ) {
        const char *t = argv[i];
        if (!strcmp(t, "move") && i + 2 < argc)          { mouse_at(px_to_pt(atof(argv[i+1]), atof(argv[i+2]))); i += 3; }
        else if (!strcmp(t, "moverel") && i + 2 < argc)  { CGPoint p = cur_pt(); p.x += atof(argv[i+1]) / g_scale; p.y += atof(argv[i+2]) / g_scale; mouse_at(p); i += 3; }
        else if (!strcmp(t, "down") && i + 1 < argc)     { button(atoi(argv[i+1]), 1); i += 2; }
        else if (!strcmp(t, "up") && i + 1 < argc)       { button(atoi(argv[i+1]), 0); i += 2; }
        else if (!strcmp(t, "key") && i + 1 < argc)      { key_combo(argv[i+1]); i += 2; }
        else if (!strcmp(t, "keydown") && i + 1 < argc)  { key_updown(argv[i+1], 1, 0); i += 2; }
        else if (!strcmp(t, "keyup") && i + 1 < argc)    { key_updown(argv[i+1], 0, 0); i += 2; }
        else if (!strcmp(t, "sleep") && i + 1 < argc)    { ms(atoi(argv[i+1])); i += 2; }
        else { fprintf(stderr, "qa-io seq: bad token '%s'\n", t); return 2; }
        ms(8);
    }
    return 0;
}

static int dispatch(int argc, char **argv) {
    const char *c = argv[1];
    if (!strcmp(c, "scale"))    { printf("%g\n", g_scale); return 0; }
    if (!strcmp(c, "noop"))     return 0;
    if (!strcmp(c, "reset"))    { st_buttons = 0; st_flags = 0; st_save(); return 0; }   // forget held buttons / modifiers
    if (!strcmp(c, "where"))    { CGPoint p = cur_pt(); printf("%ld %ld\n", (long)(p.x * g_scale + .5), (long)(p.y * g_scale + .5)); return 0; }
    if (!strcmp(c, "trusted"))  { printf("%d\n", AXIsProcessTrusted() ? 1 : 0); return 0; }
    if (!strcmp(c, "request")) {  // ask macOS to prompt for both grants (for the app that runs us)
        const void *k[] = { kAXTrustedCheckOptionPrompt }; const void *v[] = { kCFBooleanTrue };
        CFDictionaryRef o = CFDictionaryCreate(NULL, k, v, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        int ax = AXIsProcessTrustedWithOptions(o); CFRelease(o);
        int sr = CGRequestScreenCaptureAccess();
        printf("accessibility=%d screen=%d\n", ax ? 1 : 0, sr ? 1 : 0); return 0;
    }
    if (!strcmp(c, "move") && argc >= 4)    { mouse_at(px_to_pt(atof(argv[2]), atof(argv[3]))); return 0; }
    if (!strcmp(c, "moverel") && argc >= 4) { CGPoint p = cur_pt(); p.x += atof(argv[2]) / g_scale; p.y += atof(argv[3]) / g_scale; mouse_at(p); return 0; }
    if (!strcmp(c, "down") && argc >= 3)    return button(atoi(argv[2]), 1);
    if (!strcmp(c, "up") && argc >= 3)      return button(atoi(argv[2]), 0);
    if (!strcmp(c, "click") && argc >= 3)   { int r = button(atoi(argv[2]), 1); ms(30); button(atoi(argv[2]), 0); return r; }
    if (!strcmp(c, "keydown") && argc >= 3) return key_updown(argv[2], 1, 0);
    if (!strcmp(c, "keyup") && argc >= 3)   return key_updown(argv[2], 0, 0);
    if (!strcmp(c, "key") && argc >= 3)     return key_combo(argv[2]);
    if (!strcmp(c, "type") && argc >= 3)    { type_text(argv[2]); return 0; }
    if (!strcmp(c, "scroll") && argc >= 3)  { scroll(!strcmp(argv[2], "up"), argc >= 4 ? atoi(argv[3]) : 1); return 0; }
    if (!strcmp(c, "find") && argc >= 4)    return cmd_find(argv[2], argv[3]);
    if (!strcmp(c, "title") && argc >= 3)   return cmd_title(atol(argv[2]));
    if (!strcmp(c, "bounds") && argc >= 3)  return cmd_bounds(atol(argv[2]));
    if (!strcmp(c, "client") && argc >= 3)  return cmd_client(atol(argv[2]));
    if (!strcmp(c, "titlebar"))             { printf("%ld\n", (long)(titlebar_pt() * g_scale + .5)); return 0; }
    if (!strcmp(c, "pid") && argc >= 3)     { long p = win_pid(atol(argv[2])); if (!p) return 1; printf("%ld\n", p); return 0; }
    if (!strcmp(c, "activate") && argc >= 3) return cmd_activate(atol(argv[2]));
    if (!strcmp(c, "seq"))                  return run_seq(argc - 2, argv + 2);
    fprintf(stderr, "qa-io: unknown command '%s'\n", c);
    return 2;
}

// ── serve ────────────────────────────────────────────────────────────────────
// macOS drops a drag whose press, moves and release come from DIFFERENT
// processes: after `qa-io down 1` exits, the next process's dragged / up events
// never reach the app, and nothing does until the session recovers. So input
// is posted by ONE long-lived process: `qa-io serve` listens on a Unix socket
// and every input command (move, down, up, key, ...) is forwarded to it when it
// is running; without a server the command runs locally as before.
static const char *sock_path(void) {
    const char *e = getenv("QA_IO_SOCK");
    if (e && *e) return e;
    static char p[1024]; const char *h = getenv("HOME");
    snprintf(p, sizeof p, "%s/.qa-runner/io.sock", h ? h : "/tmp"); return p;
}
static int is_input_cmd(const char *c) {
    static const char *in[] = { "move", "moverel", "down", "up", "click", "keydown", "keyup",
                                "key", "type", "scroll", "seq", "reset", "noop", NULL };
    for (int i = 0; in[i]; i++) if (!strcmp(c, in[i])) return 1;
    return 0;
}
static int sock_addr(struct sockaddr_un *a) {
    memset(a, 0, sizeof *a); a->sun_family = AF_UNIX;
    if (strlen(sock_path()) >= sizeof a->sun_path) return 0;
    strcpy(a->sun_path, sock_path()); return 1;
}
// ~/.qa-runner/io-serve.log: server start / exit / signals, and clients that
// found the socket but no server behind it (input then runs per call, where
// drags break) - the trail to read when drags start failing mid-run
static void io_log(const char *fmt, ...) {
    char p[1024]; const char *h = getenv("HOME");
    snprintf(p, sizeof p, "%s/.qa-runner/io-serve.log", h ? h : "/tmp");
    FILE *f = fopen(p, "a"); if (!f) return;
    struct timeval tv; gettimeofday(&tv, NULL);
    fprintf(f, "%ld.%03d pid %d: ", (long)tv.tv_sec, (int)(tv.tv_usec / 1000), (int)getpid());
    va_list ap; va_start(ap, fmt); vfprintf(f, fmt, ap); va_end(ap);
    fputc('\n', f); fclose(f);
}
static void on_signal(int sig) { io_log("serve: killed by signal %d", sig); signal(sig, SIG_DFL); raise(sig); }

// -1 = no server (run locally), else the server's exit code
static int forward(int argc, char **argv) {
    struct sockaddr_un a; if (!sock_addr(&a)) return -1;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return -1;
    if (connect(fd, (struct sockaddr *)&a, sizeof a) != 0) {
        int e = errno; close(fd);
        if (access(a.sun_path, F_OK) == 0 && strcmp(argv[1], "noop") && strcmp(argv[1], "quit")) {
            io_log("client %s: socket there but no server (errno %d) - running locally", argv[1], e);
            fprintf(stderr, "qa-io: input server gone - '%s' runs per call (drags may fail)\n", argv[1]);
        }
        return -1;
    }
    struct timeval tv = { 60, 0 }; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    for (int i = 1; i < argc; i++) { size_t n = strlen(argv[i]) + 1; if (write(fd, argv[i], n) != (ssize_t)n) { close(fd); return 2; } }
    shutdown(fd, SHUT_WR);
    unsigned char rc = 2; if (read(fd, &rc, 1) != 1) rc = 2;
    close(fd); return rc;
}
static int serve(void) {
    struct sockaddr_un a; if (!sock_addr(&a)) { fprintf(stderr, "qa-io: socket path too long\n"); return 2; }
    unlink(a.sun_path);
    int s = socket(AF_UNIX, SOCK_STREAM, 0);
    if (s < 0 || bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 8) != 0) { perror("qa-io serve"); return 2; }
    st_buttons = 0; st_flags = 0; st_save(); st_loaded = 1;   // a fresh server: nothing held
    signal(SIGPIPE, SIG_IGN);   // a client gone before its reply must not kill the server
    signal(SIGTERM, on_signal); signal(SIGHUP, on_signal); signal(SIGINT, on_signal);
    signal(SIGSEGV, on_signal); signal(SIGBUS, on_signal); signal(SIGABRT, on_signal);
    io_log("serve: start (ppid %d)", (int)getppid());
    static char buf[65536];
    for (;;) {
        int c = accept(s, NULL, NULL); if (c < 0) continue;
        size_t len = 0; ssize_t r;
        while (len < sizeof buf - 1 && (r = read(c, buf + len, sizeof buf - 1 - len)) > 0) len += (size_t)r;
        buf[len] = 0;
        char *av[256]; int ac = 0; av[ac++] = "qa-io";
        for (size_t i = 0; i < len && ac < 255; ) { av[ac++] = buf + i; i += strlen(buf + i) + 1; }
        av[ac] = NULL;
        unsigned char rc = 2;
        if (ac >= 2 && !strcmp(av[1], "quit")) { rc = 0; if (write(c, &rc, 1)) {} close(c); io_log("serve: stop"); break; }
        if (ac >= 2 && is_input_cmd(av[1])) rc = (unsigned char)dispatch(ac, av);
        if (write(c, &rc, 1)) {}
        close(c);
    }
    close(s); return 0;   // no unlink: a successor may already own the path
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: qa-io CMD ... (see the header)\n"); return 2; }
    if (is_input_cmd(argv[1])) { int r = forward(argc, argv); if (r >= 0) return r; }
    else if (!strcmp(argv[1], "ping")) { char *q[] = { argv[0], "noop" }; return forward(2, q) >= 0 ? 0 : 1; }   // 0 = a server is running
    else if (!strcmp(argv[1], "stop")) { char *q[] = { argv[0], "quit" }; return forward(2, q) >= 0 ? 0 : 1; }
    g_scale = display_scale();
    g_src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!strcmp(argv[1], "serve")) return serve();
    return dispatch(argc, argv);
}
