# Claude Usage

A desktop widget that shows your Claude plan usage: the current 5-hour session and
the rolling weekly limit as percentages, with a small chart of the last day or week.
It sits just above the desktop icons like the other DesktopKit widgets.

Built on [DesktopKit](https://github.com/rob901/desktop-widgets). It has no menu-bar icon;
right-click the widget's top bar for Day/Week, Refresh, Preferences, Open at Login, and Quit.

## Build

```sh
./build.sh           # builds build/ClaudeUsage.app
./build.sh install   # also copies to /Applications and launches it

# against a local framework checkout:
DESKTOPKIT_PATH=../../desktop-framework ./build.sh

# render the widget to a PNG and quit (for checking layout):
build/ClaudeUsage.app/Contents/MacOS/ClaudeUsage --snapshot /tmp/widget.png week
```

## Use

- **Day** charts session usage over the last 24 hours; **Week** charts weekly usage over the last 7 days.
  Switch with the Day/Week control, the right-click menu, or ⌘1 / ⌘2.
- Hover over the chart to read individual values.
- The meters turn amber and red at levels you set in Preferences (70% and 90% by default).
- Double-click the top bar to collapse the widget to one line that shows both numbers.
- ⌘R refreshes, and ⌘, opens Preferences.

## Where the numbers come from

The Claude desktop app records your plan usage every few minutes while it's running, in
`~/Library/Application Support/Claude/plan-usage-history.json`. The widget reads that file
every 30 seconds. The widget needs no sign-in or credentials, but:

- The numbers are only as fresh as the Claude app's last reading. Gaps in the chart are
  times it wasn't recording, and the footer tells you how old the last reading is.
- It's an internal file of the Claude app and could change. The widget shows a message
  rather than crashing if it can't read the file.

See `PLAN.md` for the other data sources considered.

Widget position and Day/Week choice: `~/Library/Application Support/ClaudeUsage/widget.json`.
