#!/bin/zsh
# Builds build/DesktopNotes.app. `./build.sh install` also copies it to /Applications and launches it.
# Set DESKTOPKIT_PATH=../desktop-framework to build against a local framework checkout.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -n "${DESKTOPKIT_PATH:-}" ]]; then
  KIT="$DESKTOPKIT_PATH"
else
  swift package resolve
  KIT=.build/checkouts/desktop-widgets
fi
exec "$KIT/Scripts/bundle-app.sh" . DesktopNotes "$@"
