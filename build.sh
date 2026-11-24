#!/bin/zsh
# Builds build/DesktopNotes.app. `./build.sh install` also copies it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/DesktopNotes.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/DesktopNotes"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
if [[ "${1:-}" == "install" ]]; then
  pkill -x DesktopNotes 2>/dev/null || true
  rm -rf /Applications/DesktopNotes.app
  cp -R "$APP" /Applications/
  open /Applications/DesktopNotes.app
  echo "Installed to /Applications and launched"
fi
