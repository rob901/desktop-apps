# dt-claude — Claude plan usage widget

## Goal

A desktop widget showing Claude subscription usage for the day and week as a small graph,
the same data the Claude desktop app shows in its menu-bar menu.

## Data sources investigated (2026-11-24)

| Source | What it has | Credentials | Verdict |
|---|---|---|---|
| **Claude desktop app's `plan-usage-history.json`** (`~/Library/Application Support/Claude/`) | Samples `{t (ms), org, u: {fh: 5-hour %, sd: 7-day %}}`, `version: 2`. Every 5–15 min while the app is active; gaps when it's closed or the Mac sleeps. ~40 samples covering 4 weeks. | None | **Used for v1.** It's the same data as the app's menu-bar graph. |
| Claude Code's usage endpoint (what `/usage` shows) | Live 5-hour and 7-day utilization plus **reset times**. | The Claude Code OAuth token stored in the login keychain. | **Not used.** It needs this app to read another app's sign-in token, and the endpoint isn't a documented API. Revisit only if you want live numbers and reset times, and are OK with the widget asking keychain permission for that item. |
| Claude Code transcripts (`~/.claude*/projects/**/*.jsonl`) | Token counts per message, Claude Code only. | None | Not used: it gives tokens, not % of plan limits, and misses claude.ai and desktop chat usage. Could become a "tokens by day" view later. |
| Usage and Cost Analytics / Admin API | Org-level API usage. | Admin key | Not applicable to a personal subscription. |

## v1 (built)

- One widget (no menu-bar icon), 290×210 by default, at the top right on first launch.
- Two stat tiles with meters. Severity is amber or red at configurable levels, always with a warning icon,
  never color alone.
- A single-series line + area chart with a 0–100% axis and hairline grid. Lines break where readings are missing
  (gap of more than 45 min in Day view, 12 h in Week view). Hovering shows a crosshair and the nearest reading.
- The collapsed bar shows "Claude · session N% · week N%".
- The right-click menu has Day/Week, Refresh Now, Collapse, plus the framework's standard items.
- Preferences: amber/red levels, the data file location, and the shared snapping setting.
- The file is checked every 30 s and after wake (`PeriodicTask`), and re-read only when its modification date changes.

## Framework changes it needed

`WidgetWindow.title`, `DesktopHost.standardMenuItems()`, `PeriodicTask`. See the framework's `PLAN.md`.

## Ideas for later

- Show the reset time ("resets 7:40 PM") if a live source is added.
- Dark appearance (needs dark-mode steps validated against a dark surface, not an automatic flip).
- Detect and label session resets on the Day chart.
- Pick an organization if the file ever contains more than one account (today it follows the most recent).
