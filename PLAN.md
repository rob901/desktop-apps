# dt-stickies — rebuild of Desktop Stickies on DesktopKit

Goal: the same app as `../desktop-stickies` (same behavior, same saved notes),
rebuilt as a thin widget on `../desktop-framework` (DesktopKit). No new
features in this pass — any behavior difference is a bug.

---

## 1. Drop-in replacement, no data migration

Keep these identical to `desktop-stickies` so installing `dt-stickies` simply
replaces the old app and picks up existing notes and settings:

- App name `DesktopNotes`, bundle ID `local.desktopnotes.DesktopNotes`
  (keeps `UserDefaults` — color, font, size, snapping — and the Open at Login registration).
- Data file `~/Library/Application Support/DesktopNotes/notes.json`.
- JSON shape of `NoteData` (flat `id, x, top, width, height, collapsed, color, rtf`).
  In code, `NoteData` exposes a computed `frame: WidgetFrame` so the on-disk
  format doesn't change.

Before first install, back up `notes.json` anyway.

---

## 2. Layout

```
dt-stickies/
  Package.swift              // executable "DesktopNotes", depends on ../desktop-framework
  Info.plist                 // copied from desktop-stickies
  build.sh                   // calls ../desktop-framework/Scripts/bundle-app.sh DesktopNotes Info.plist "$@"
  README.md
  Sources/DesktopNotes/
    main.swift               // DesktopApp.run(StickiesApp())
    StickiesApp.swift        // DesktopWidgetApp: note list, new/remove, menu items, prefs rows
    Note.swift               // NoteController: owns a WidgetWindow + the text view
    NoteText.swift           // bold/italic/size/find, typing attributes
    NoteModel.swift          // NoteData, NoteColor (+ theme mapping), NotePrefs
    NotePreferences.swift    // stickies rows for the framework's preferences form
```

---

## 3. What each old file becomes

| desktop-stickies | dt-stickies | Notes |
|---|---|---|
| `main.swift` | `main.swift` | One line. |
| `AppDelegate.swift` | `StickiesApp.swift` | Keeps `notes`, `newNote(near:)`, `remove`, first-launch empty note. Status item, Open at Login, Quit, save timer, `fitOnScreen` → framework. Supplies menu items: New Note, Collapse All, Expand All. |
| `Note.swift` → `NotePanel`, `HeaderView`, `GripView`, `trackDrag`, panel config, layout, move/resize/snap, collapse | framework `WidgetWindow` | Removed from the app. |
| `Note.swift` → text view, formatting, find, delete confirm, color menu, first-line title | `Note.swift` + `NoteText.swift` | `NoteController` creates a `WidgetWindow`, sets the scroll view as its content, adds delete (leading) and new (trailing) buttons, and implements `WidgetWindowDelegate`. |
| `Snapping.swift` | framework `Snapper` | Stickies passes `NotePrefs.size` as a preferred snap size via the delegate. |
| `Model.swift` → `NoteColor` | `NoteModel.swift` | Adds `var theme: WidgetTheme`; swatch comes from the framework. |
| `Model.swift` → `NoteData` | `NoteModel.swift` | Unchanged fields + computed `frame`. |
| `Model.swift` → `Prefs` | `NoteModel.swift` (`NotePrefs`) | Minus `snapping` (now `DesktopSettings.snapping`, same key). |
| `Model.swift` → `Store` | framework `JSONStore<[NoteData]>(folder: "DesktopNotes", file: "notes.json")` | Removed from the app. |
| `Model.swift` → `performStandardEditShortcut` | framework | Removed from the app. |
| `Preferences.swift` | `NotePreferences.swift` | Only the stickies rows: color, font, text color, preview, size, use-note-size. Window, grid, helpers, snapping row → framework. |
| `build.sh` | `build.sh` | Delegates to the framework script. |

Key-equivalent split: ⌘N, ⌘B, ⌘I, ⌘U, ⌘F, ⌘=/⌘-, ⌘, and paste-as-plain-text
stay in stickies (via `widgetWindow(_:keyEquivalent:)`); cut/copy/paste/select
all/undo/redo are handled by the framework panel.

---

## 4. Steps

Do these alongside the framework steps — each stickies step is the check that
the matching framework step is right.

1. **Skeleton:** `Package.swift`, `main.swift`, empty `StickiesApp`. Builds; shows
   a menu-bar icon with the framework's standard items. *(framework steps 1, 5)*
2. **Model:** port `NoteData`, `NoteColor`, `NotePrefs`; load/save with
   `JSONStore`. Load the real `notes.json` copy and print the count.
   *(framework step 2)*
3. **Windows:** `NoteController` on `WidgetWindow` with a plain text view; notes
   restore at their saved positions/sizes/collapse state, move, resize, snap,
   collapse. *(framework steps 3–4)*
4. **Text features:** rich text, formatting shortcuts, find, collapsed title,
   delete confirmation, color menu.
5. **Preferences:** stickies rows in the framework form; "Use This Note's Size",
   live refresh when notes change. *(framework step 6)*
6. **Build/install:** `./build.sh install` via the framework script. *(framework step 7)*
7. **Parity check** (below), then retire `desktop-stickies` (keep its git history).

---

## 5. Parity checklist

Run against the real `notes.json` (backed up first):

- [ ] Existing notes reappear with the same position, size, color, collapsed state, and rich text.
- [ ] Notes sit above desktop icons, below all windows; on every Space; usable during Show Desktop without ending it.
- [ ] Click a note during Show Desktop and type; ⌘X/C/V/A/Z/⇧⌘Z work.
- [ ] ⌘B / ⌘I / ⌘U / ⌘F / ⌘= / ⌘- / ⌥⌘V / ⇧⌘V / ⌘N / ⌘, work.
- [ ] Drag header to move; drag corner to resize; snapping to notes, screen edges, and default size, with haptic tick; ⌘ bypasses; snapping pref toggles it.
- [ ] Double-click header collapses/expands with the top edge fixed; collapsed bar shows first line.
- [ ] `+` / `×` / chevron buttons; deleting a non-empty note asks first.
- [ ] Right-click menu: colors with checkmark, Use This Size, Preferences, Delete.
- [ ] Menu bar: New Note, Collapse All, Expand All, Preferences…, Open at Login (state correct), Show Notes File in Finder, Quit.
- [ ] Preferences: every control works and persists; preview updates; note list updates when notes are added/removed; ⌘W closes.
- [ ] Note saved on a disconnected display comes back onto the main screen.
- [ ] Edits survive quit and relaunch; corrupt `notes.json` is backed up, not overwritten.
- [ ] First launch with no data creates one note.

---

## Status (2026-11-24)

Steps 1–6 done: the app builds on DesktopKit with no warnings, and `NoteData`
matches the keys in the real `notes.json`. Remaining: install it in place of
the running old app (`./build.sh install`, after backing up `notes.json`) and go
through the parity checklist by hand.
