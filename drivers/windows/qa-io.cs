// qa-io (Windows) - the qa-harness's OS input / window helper for Windows.
// Same command line as drivers/macos/qa-io.c; drivers/windows/driver.sh wraps it.
//
// Coordinates are PHYSICAL screen pixels (the process is DPI-aware), the same
// space as `capture`. Keys are xdotool keysym names; they are sent as SCAN codes
// (GLFW identifies keys by scan code - a VK-only event reaches it as "unknown").
//
//   qa-io move X Y | moverel DX DY | down B | up B | click B     (B: 1 left, 2 middle, 3 right)
//   qa-io keydown K | keyup K | key COMBO | type TEXT | scroll up|down [N]
//   qa-io capture FILE.png              (the primary screen)
//   qa-io find PID TITLE | title H | bounds H (frame) | client H (client area) | activate H | pid H
//   qa-io seq TOKENS... | scale
//
// Build (any Windows, .NET Framework 4):
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /optimize /out:qa-io.exe /r:System.Drawing.dll qa-io.cs
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class QaIo {
    // ── Win32 ────────────────────────────────────────────────────────────────
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
    [StructLayout(LayoutKind.Explicit)] struct INPUTU { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public INPUTU u; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    delegate bool EnumProc(IntPtr h, IntPtr p);

    [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] i, int size);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int v);
    [DllImport("user32.dll")] static extern uint GetDpiForSystem();
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);

    const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
    const uint MOVE = 0x0001, LDOWN = 0x0002, LUP = 0x0004, RDOWN = 0x0008, RUP = 0x0010, MDOWN = 0x0020, MUP = 0x0040, WHEEL = 0x0800, ABSOLUTE = 0x8000, VIRTUALDESK = 0x4000;
    const uint KEYUP = 0x0002, SCANCODE = 0x0008, UNICODE = 0x0004, EXTENDED = 0x0001;

    static void Ms(int n) { Thread.Sleep(n); }
    static void Send(INPUT i) { SendInput(1, new[] { i }, Marshal.SizeOf(typeof(INPUT))); }

    // ── mouse ────────────────────────────────────────────────────────────────
    static void MoveTo(int x, int y) {
        // absolute move over the virtual desktop (normalised 0..65535), then pin the
        // exact pixel - SendInput rounds, SetCursorPos does not
        int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
        var i = new INPUT { type = INPUT_MOUSE };
        i.u.mi.dx = (int)Math.Round((x - vx) * 65535.0 / Math.Max(1, vw - 1));
        i.u.mi.dy = (int)Math.Round((y - vy) * 65535.0 / Math.Max(1, vh - 1));
        i.u.mi.dwFlags = MOVE | ABSOLUTE | VIRTUALDESK;
        Send(i);
        SetCursorPos(x, y);
    }
    static void Button(int b, bool down) {
        uint f = b == 1 ? (down ? LDOWN : LUP) : b == 3 ? (down ? RDOWN : RUP) : (down ? MDOWN : MUP);
        var i = new INPUT { type = INPUT_MOUSE }; i.u.mi.dwFlags = f; Send(i);
    }
    static void Scroll(bool up, int n) {
        for (int k = 0; k < n; k++) {
            var i = new INPUT { type = INPUT_MOUSE }; i.u.mi.dwFlags = WHEEL; i.u.mi.mouseData = (uint)(up ? 120 : -120); Send(i); Ms(20);
        }
    }

    // ── keys ─────────────────────────────────────────────────────────────────
    static readonly Dictionary<string, int[]> Keys = new Dictionary<string, int[]>(StringComparer.Ordinal) {
        // name -> { vk, shift, extended }
        {"Return",new[]{0x0D,0,0}},{"Enter",new[]{0x0D,0,0}},{"Escape",new[]{0x1B,0,0}},{"BackSpace",new[]{0x08,0,0}},
        {"Tab",new[]{0x09,0,0}},{"space",new[]{0x20,0,0}},{"Delete",new[]{0x2E,0,1}},{"Insert",new[]{0x2D,0,1}},
        {"Home",new[]{0x24,0,1}},{"End",new[]{0x23,0,1}},{"Prior",new[]{0x21,0,1}},{"Page_Up",new[]{0x21,0,1}},
        {"Next",new[]{0x22,0,1}},{"Page_Down",new[]{0x22,0,1}},{"Left",new[]{0x25,0,1}},{"Up",new[]{0x26,0,1}},
        {"Right",new[]{0x27,0,1}},{"Down",new[]{0x28,0,1}},
        {"minus",new[]{0xBD,0,0}},{"equal",new[]{0xBB,0,0}},{"bracketleft",new[]{0xDB,0,0}},{"bracketright",new[]{0xDD,0,0}},
        {"backslash",new[]{0xDC,0,0}},{"semicolon",new[]{0xBA,0,0}},{"apostrophe",new[]{0xDE,0,0}},{"grave",new[]{0xC0,0,0}},
        {"comma",new[]{0xBC,0,0}},{"period",new[]{0xBE,0,0}},{"slash",new[]{0xBF,0,0}},
        {"question",new[]{0xBF,1,0}},{"greater",new[]{0xBE,1,0}},{"less",new[]{0xBC,1,0}},{"asterisk",new[]{0x38,1,0}},
        {"braceleft",new[]{0xDB,1,0}},{"braceright",new[]{0xDD,1,0}},{"numbersign",new[]{0x33,1,0}},{"plus",new[]{0xBB,1,0}},
        {"underscore",new[]{0xBD,1,0}},{"colon",new[]{0xBA,1,0}},{"quotedbl",new[]{0xDE,1,0}},{"exclam",new[]{0x31,1,0}},
        {"at",new[]{0x32,1,0}},{"dollar",new[]{0x34,1,0}},{"percent",new[]{0x35,1,0}},{"asciicircum",new[]{0x36,1,0}},
        {"ampersand",new[]{0x37,1,0}},{"parenleft",new[]{0x39,1,0}},{"parenright",new[]{0x30,1,0}},{"bar",new[]{0xDC,1,0}},
        {"asciitilde",new[]{0xC0,1,0}},
    };
    static readonly Dictionary<string, int[]> Mods = new Dictionary<string, int[]>(StringComparer.OrdinalIgnoreCase) {
        {"ctrl",new[]{0xA2,0}},{"control",new[]{0xA2,0}},{"Control_L",new[]{0xA2,0}},
        {"shift",new[]{0xA0,0}},{"Shift_L",new[]{0xA0,0}},
        {"alt",new[]{0xA4,0}},{"Alt_L",new[]{0xA4,0}},
        {"super",new[]{0x5B,1}},{"Super_L",new[]{0x5B,1}},{"meta",new[]{0x5B,1}},{"cmd",new[]{0x5B,1}},
    };
    static bool Lookup(string n, out int vk, out bool shift, out bool ext) {
        vk = 0; shift = false; ext = false; int[] d;
        if (Mods.TryGetValue(n, out d)) { vk = d[0]; ext = d[1] == 1; return true; }
        if (Keys.TryGetValue(n, out d)) { vk = d[0]; shift = d[1] == 1; ext = d[2] == 1; return true; }
        if (n.Length == 1) {
            char c = n[0];
            if (c >= 'a' && c <= 'z') { vk = char.ToUpper(c); return true; }
            if (c >= 'A' && c <= 'Z') { vk = c; shift = true; return true; }
            if (c >= '0' && c <= '9') { vk = c; return true; }
        }
        if (n.Length >= 2 && (n[0] == 'F' || n[0] == 'f')) { int f; if (int.TryParse(n.Substring(1), out f) && f >= 1 && f <= 24) { vk = 0x70 + f - 1; return true; } }
        foreach (var kv in Keys) if (string.Equals(kv.Key, n, StringComparison.OrdinalIgnoreCase)) { vk = kv.Value[0]; shift = kv.Value[1] == 1; ext = kv.Value[2] == 1; return true; }
        return false;
    }
    static void SendVk(int vk, bool ext, bool down) {
        var i = new INPUT { type = INPUT_KEYBOARD };
        i.u.ki.wVk = (ushort)vk;
        i.u.ki.wScan = (ushort)MapVirtualKey((uint)vk, 0);
        i.u.ki.dwFlags = SCANCODE | (ext ? EXTENDED : 0) | (down ? 0 : KEYUP);
        Send(i);
    }
    static int KeyUpDown(string n, bool down) {
        int vk; bool shift, ext;
        if (!Lookup(n, out vk, out shift, out ext)) { Console.Error.WriteLine("qa-io: unknown key '" + n + "'"); return 2; }
        if (shift && down) { SendVk(0xA0, false, true); Ms(15); }
        SendVk(vk, ext, down);
        if (shift && !down) { Ms(15); SendVk(0xA0, false, false); }
        return 0;
    }
    // same timing as the X11 driver: hold each modifier ~60ms, the base 200ms
    static int KeyCombo(string combo) {
        var parts = combo.Split('+');
        if (parts.Length == 1) { int r = KeyUpDown(parts[0], true); Ms(100); KeyUpDown(parts[0], false); Ms(50); return r; }
        for (int k = 0; k < parts.Length - 1; k++) { if (!Mods.ContainsKey(parts[k])) { Console.Error.WriteLine("qa-io: not a modifier '" + parts[k] + "'"); return 2; } KeyUpDown(parts[k], true); Ms(60); }
        Ms(60);
        int res = KeyUpDown(parts[parts.Length - 1], true); Ms(200); KeyUpDown(parts[parts.Length - 1], false); Ms(40);
        for (int k = parts.Length - 2; k >= 0; k--) KeyUpDown(parts[k], false);
        Ms(50);
        return res;
    }
    static void TypeText(string s) {
        foreach (char c in s) {
            foreach (bool down in new[] { true, false }) {
                var i = new INPUT { type = INPUT_KEYBOARD }; i.u.ki.wScan = c; i.u.ki.dwFlags = UNICODE | (down ? 0 : KEYUP); Send(i);
            }
            Ms(30);
        }
    }

    // ── windows ──────────────────────────────────────────────────────────────
    static string Title(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
    static IntPtr Find(uint pid, string title) {
        IntPtr hit = IntPtr.Zero;
        EnumWindows((h, p) => {
            if (!IsWindowVisible(h)) return true;
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (pid != 0 && wp != pid) return true;
            string t = Title(h);
            if (t.Length == 0) return true;
            if (!string.IsNullOrEmpty(title) && t.IndexOf(title, StringComparison.Ordinal) < 0) return true;
            hit = h; return false;
        }, IntPtr.Zero);
        return hit;
    }
    static void Activate(IntPtr h) {
        if (IsIconic(h)) ShowWindow(h, 9);
        // the foreground lock lets a process take the foreground after it sent input
        SendVk(0xA4, false, true); SendVk(0xA4, false, false);
        SetForegroundWindow(h);
        Ms(80);
    }

    static void Capture(string file) {
        int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp)) {
            g.CopyFromScreen(0, 0, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
            bmp.Save(file, ImageFormat.Png);
        }
    }

    static int Seq(string[] a, int s) {
        for (int k = s; k < a.Length; ) {
            string t = a[k];
            if (t == "move" && k + 2 < a.Length) { MoveTo(int.Parse(a[k + 1]), int.Parse(a[k + 2])); k += 3; }
            else if (t == "moverel" && k + 2 < a.Length) { POINT p; GetCursorPos(out p); MoveTo(p.X + int.Parse(a[k + 1]), p.Y + int.Parse(a[k + 2])); k += 3; }
            else if (t == "down" && k + 1 < a.Length) { Button(int.Parse(a[k + 1]), true); k += 2; }
            else if (t == "up" && k + 1 < a.Length) { Button(int.Parse(a[k + 1]), false); k += 2; }
            else if (t == "key" && k + 1 < a.Length) { KeyCombo(a[k + 1]); k += 2; }
            else if (t == "keydown" && k + 1 < a.Length) { KeyUpDown(a[k + 1], true); k += 2; }
            else if (t == "keyup" && k + 1 < a.Length) { KeyUpDown(a[k + 1], false); k += 2; }
            else if (t == "sleep" && k + 1 < a.Length) { Ms(int.Parse(a[k + 1])); k += 2; }
            else { Console.Error.WriteLine("qa-io seq: bad token '" + t + "'"); return 2; }
            Ms(8);
        }
        return 0;
    }

    static int Main(string[] a) {
        try { SetProcessDpiAwareness(2); } catch { SetProcessDPIAware(); }
        if (a.Length < 1) { Console.Error.WriteLine("usage: qa-io CMD ... (see the header)"); return 2; }
        string c = a[0];
        try {
            switch (c) {
                case "scale": Console.WriteLine((GetDpiForSystem() / 96.0).ToString(System.Globalization.CultureInfo.InvariantCulture)); return 0;
                case "move": MoveTo(int.Parse(a[1]), int.Parse(a[2])); return 0;
                case "moverel": { POINT p; GetCursorPos(out p); MoveTo(p.X + int.Parse(a[1]), p.Y + int.Parse(a[2])); return 0; }
                case "down": Button(int.Parse(a[1]), true); return 0;
                case "up": Button(int.Parse(a[1]), false); return 0;
                case "click": Button(int.Parse(a[1]), true); Ms(30); Button(int.Parse(a[1]), false); return 0;
                case "keydown": return KeyUpDown(a[1], true);
                case "keyup": return KeyUpDown(a[1], false);
                case "key": return KeyCombo(a[1]);
                case "type": TypeText(a[1]); return 0;
                case "scroll": Scroll(a[1] == "up", a.Length > 2 ? int.Parse(a[2]) : 1); return 0;
                case "capture": Capture(a[1]); return 0;
                case "find": { uint pid = 0; if (a[1].Length > 0) pid = uint.Parse(a[1]); IntPtr h = Find(pid, a.Length > 2 ? a[2] : ""); if (h == IntPtr.Zero) return 1; Console.WriteLine(h.ToInt64()); return 0; }
                case "title": { IntPtr h = new IntPtr(long.Parse(a[1])); if (!IsWindow(h)) return 1; Console.WriteLine(Title(h)); return 0; }
                case "pid": { IntPtr h = new IntPtr(long.Parse(a[1])); if (!IsWindow(h)) return 1; uint p; GetWindowThreadProcessId(h, out p); Console.WriteLine(p); return 0; }
                case "bounds": {
                    IntPtr h = new IntPtr(long.Parse(a[1])); RECT r;
                    if (!IsWindow(h)) { Console.WriteLine("0 0 0 0"); return 1; }
                    if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) != 0) GetWindowRect(h, out r);  // 9 = extended frame bounds (no shadow)
                    Console.WriteLine(r.L + " " + r.T + " " + (r.R - r.L) + " " + (r.B - r.T)); return 0;
                }
                case "client": {
                    IntPtr h = new IntPtr(long.Parse(a[1])); RECT r; POINT o = new POINT();
                    if (!IsWindow(h)) { Console.WriteLine("0 0 0 0"); return 1; }
                    GetClientRect(h, out r); ClientToScreen(h, ref o);
                    Console.WriteLine(o.X + " " + o.Y + " " + (r.R - r.L) + " " + (r.B - r.T)); return 0;
                }
                case "activate": { IntPtr h = new IntPtr(long.Parse(a[1])); if (!IsWindow(h)) return 1; Activate(h); return 0; }
                case "seq": return Seq(a, 1);
            }
        } catch (Exception e) { Console.Error.WriteLine("qa-io: " + e.Message); return 2; }
        Console.Error.WriteLine("qa-io: unknown command '" + c + "'");
        return 2;
    }
}
