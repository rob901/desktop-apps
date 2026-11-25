#!/bin/zsh
# Builds build/ClaudeUsage.app. `./build.sh install` also copies it to /Applications and launches it.
# Set DESKTOPKIT_PATH=../../desktop-framework to build against a local framework checkout.
set -euo pipefail
cd "$(dirname "$0")"
if [[ -n "${DESKTOPKIT_PATH:-}" ]]; then
  KIT="$DESKTOPKIT_PATH"
  # SwiftPM drops the GitHub pin from Package.resolved when using a local path; put it back afterwards.
  if [[ -f Package.resolved ]]; then
    cp Package.resolved .build-package-resolved
    trap 'mv .build-package-resolved Package.resolved' EXIT
  fi
else
  swift package resolve
  KIT=.build/checkouts/desktop-widgets
fi
"$KIT/Scripts/bundle-app.sh" . ClaudeUsage "$@"
