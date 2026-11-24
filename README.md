# Desktop Stickies

Sticky notes for macOS that live on the desktop itself. They sit just above the
desktop icons, so they're always behind your windows. They stay on every Space,
and they stay visible (and editable) when you use Show Desktop.

## Build

```sh
./build.sh           # builds build/DesktopNotes.app
./build.sh install   # also copies to /Applications and launches it
```

Requires the Xcode command-line tools (swiftc) and macOS 14+.

## Use

- Show Desktop, then click a note to type into it.
- Double-click a note's top bar to collapse or expand it.
- `+` or ⌘N makes a new note. `×` deletes it.
- Right-click the top bar to change the color.
- Drag the top bar to move a note. Drag the bottom-right corner to resize it.
- The menu-bar icon has New Note, Collapse All, Expand All, Open at Login, and Quit.

Notes are saved to `~/Library/Application Support/DesktopNotes/notes.json`.
