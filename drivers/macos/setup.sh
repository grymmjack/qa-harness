#!/usr/bin/env bash
# drivers/macos/setup.sh — run ON the Mac (over SSH is fine): ImageMagick,
# qa-io and "QA Runner.app". Idempotent. Afterwards grant the app its two
# permissions once (it prints how).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="/opt/homebrew/bin:$PATH"
command -v magick >/dev/null || brew install imagemagick
# the harness speaks GNU userland (sed -i, date -d, grep -P, timeout, stat -c): qa-run puts these first
for f in coreutils gnu-sed grep findutils gawk; do brew list --versions "$f" >/dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 brew install "$f"; done
mkdir -p "$HOME/.qa-runner/bin"
clang -O2 -o "$HOME/.qa-runner/bin/qa-io" "$HERE/qa-io.c" -framework ApplicationServices -framework CoreFoundation
APP="$HOME/Applications/QA Runner.app"
mkdir -p "$APP/Contents/MacOS"
clang -O2 -o "$APP/Contents/MacOS/qa-runner" "$HERE/qa-runner.c"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>qa-runner</string>
  <key>CFBundleIdentifier</key><string>com.grymmjack.qa-runner</string>
  <key>CFBundleName</key><string>QA Runner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "QA Runner.app: $APP"
echo "qa-io: $HOME/.qa-runner/bin/qa-io"
cat <<'MSG'

One-time permissions (System Settings > Privacy & Security):
  * Accessibility    -> + -> ~/Applications/QA Runner.app -> on
  * Screen & System Audio Recording (Screen Recording) -> + -> QA Runner.app -> on
Then: drivers/macos/qa-run --check
MSG
