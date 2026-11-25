# Desktop apps

Desktop widgets for macOS built on [DesktopKit](https://github.com/rob901/desktop-widgets).
Each widget is its own app in its own folder, with its own `build.sh`.

| Folder | App | What it does |
|---|---|---|
| [`claude-widget`](claude-widget) | Claude Usage | Claude plan usage (session and weekly %) with a day/week chart |

Desktop Notes (sticky notes) lives in its own repo: [desktop-stickies](https://github.com/rob901/desktop-stickies).

## Building a widget

```sh
cd claude-widget
./build.sh           # builds build/<App>.app
./build.sh install   # also copies it to /Applications and launches it
```

Requires the Xcode command-line tools (Swift 5.9+) and macOS 14+. SwiftPM fetches
DesktopKit from GitHub. To build against a local checkout of the framework while changing it,
with this repo and `desktop-framework` side by side:

```sh
DESKTOPKIT_PATH=../../desktop-framework ./build.sh
```

## Adding a widget

Make a new folder with `Package.swift`, `Info.plist` (`LSUIElement` true, a unique bundle ID),
`build.sh`, and `Sources/<App>/`. Copying `claude-widget` is the quickest start.
Add it to the table above.
