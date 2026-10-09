#!/usr/bin/env bash
# drivers/windows/setup.sh — run in Git Bash ON the Windows host (over SSH is
# fine): builds qa-io.exe into C:\qa-runner\bin and checks ImageMagick (the
# portable build unpacked in C:\qa-runner\imagemagick, or an installed one).
# C:\qa-runner is shared, so the desktop user's Scheduled Task can use it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p /c/qa-runner/bin
CSC=/c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe
"$CSC" -nologo -optimize "-out:$(cygpath -w /c/qa-runner/bin/qa-io.exe)" -r:System.Drawing.dll "$(cygpath -w "$HERE/qa-io.cs")"
if [[ ! -x /c/qa-runner/imagemagick/magick.exe ]] && ! ls /c/Program\ Files/ImageMagick*/magick.exe >/dev/null 2>&1; then
    echo "ImageMagick: unpack the portable Q16 x64 build into C:\\qa-runner\\imagemagick" >&2; exit 1
fi
echo "qa-io: C:\\qa-runner\\bin\\qa-io.exe"
