# Focus Modes

A small macOS menu bar app that helps you **start** working and keeps you from drifting off. You pick what you'll work on; for a set time the app blocks the apps and sites that activity doesn't need, opens the ones it does, and afterwards asks what you actually did. Whenever nothing is running, it asks what's next, so the decision is always yours and always made.

## How a day works

0. **First launch.** The **Get started** page opens. It explains the idea, has you build your activity list (from templates with icons, or your own), tick the apps and sites to block, and set the night. Nothing is asked or blocked until you press **Start**; until then the menu bar panel only leads back to Get started (so does opening the app again from Finder or Spotlight).
1. **Start.** Click ◎ in the menu bar: the **Today** list shows every activity with the time left today. Pick a length at the top (default 30 min, or 🍅 Pomodoro) and click an activity to start it. Right-click a row to start it with a specific length.
2. **Blocking.** The activity's block is locked for the session: by default the one **with the same name**, and it stays linked if you rename the activity (Activities → ⌄ → Block it locks). Its apps are quit as soon as they start, and its sites are replaced with a "Not now" page in Chrome. Stopping the timer early doesn't lift the block before its time. **Rest** is an activity too: a short break between tasks with its own block, so a break doesn't turn into a movie.
3. **Workspace.** The app opens the activity's apps and links (set them up in Activities → ⌄). For a one-off site, use **Open a site** before pressing Start.
4. **Review.** When time's up (or you stop), a checklist appears with the plan already checked: one click confirms, or tick what you actually did. That goes into the stats.
5. **Always decide.** Whenever nothing is running (no session, no free time) and it isn't night, the "What's next?" window opens right away and can't be closed. Nothing is blocked until you pick an activity or free time. If it stays unanswered for 15 minutes, an activity starts by itself for 30 minutes: the one furthest behind its daily limit (Rest only if nothing else can start). The window shows which one and a countdown; both numbers are in Rules.
6. **Free time.** 🍿 Free time blocks nothing (movies, YouTube) and comes from a budget of 60 min a day. It's offered in the "What's next?" window and in the panel, and is only ever taken on purpose. It can't be taken twice in a row; a session has to run in between.
7. **Daily limits.** Each activity can have a daily limit (e.g. Work 1h). Once it's used up, the activity disappears from the picker for the rest of the day. When nothing is left, the picker says so.
   **Hours.** An activity can also have hours (e.g. Work 12:00–20:00). Outside them it's greyed out in the picker with "from 12:00".
8. **Night.** From 00:00 to 08:00 the night block (`Focus_Mode`) is locked until morning. No prompts, no timers, and nothing can be started.

All the numbers above are defaults. **Stats**, **Activities** (list, daily limits, hours, what each opens) and **Rules** (night, free time, session length) live in one window with a sidebar, opened from the panel's toolbar.

## Setup

### 1. Blocks

Blocks live in `~/modes/blocks.json`, by name; each activity locks the one named in Activities → ⌄ → Block it locks. `Focus_Mode` is the night block and the one "Other" uses. Edit them in **Activities → ⌄ → Blocks** (and **Rules → Night**), or in the file:

```json
{ "Work": { "apps": ["com.tdesktop.telegram"], "web": ["google.com"], "exceptions": ["mail.google.com", "github.com"] } }
```

- `apps`: bundle ids, quit while the block is on.
- `web`: sites to block, with subdomains and every path. `*` is a wildcard; `"*"` alone blocks everything.
- `exceptions`: always allowed, even under `"*"` (`youtube.com/watch*`, `file://*.*`).

While a block is locked it can only get stricter: you can add apps and sites and remove exceptions, but not the other way round.

On first launch, **Start** on Get started fills every block that's still empty with the apps and sites you ticked; blocks that already exist are kept.

Coming from Cold Turkey? `swift scripts/import-cold-turkey.swift` copies the blocks named like your activities (and `Focus_Mode`) into `blocks.json` once (`--force` replaces an existing file). Then turn those blocks off in Cold Turkey so they don't double up.

### 2. Build and install

```sh
scripts/build.sh            # builds /Applications/Focus Modes.app and starts it
NO_START=1 scripts/build.sh # build only
```

The build needs Xcode or its command-line tools (Swift 6). It:
- builds the release binary with SwiftPM and wraps it into `/Applications/Focus Modes.app`
- draws the icon (`scripts/make-icon.swift`)
- signs the app with a local self-signed certificate "FocusModes Local", created once in your login keychain, so macOS remembers permissions across rebuilds
- installs the launch agent (`launchd/com.user.focusmodes.plist`): the app starts at login and comes back within seconds if it's quit

### 3. Permissions (once)

- **Accessibility** (System Settings → Privacy & Security → Accessibility → Focus Modes): needed to stretch opened windows to fill the screen.
- **Chrome automation:** allow "Focus Modes" to control Google Chrome when asked. It's how links open (in a separate window that's closed when you switch activities) and how blocked sites are caught. If it's turned off, Chrome is quit while a block with sites is on.

## Data

Everything personal lives in `~/modes`, outside the repo:

| File | What |
|---|---|
| `settings.json` | all settings, including activities, daily limits, the block each locks and what each opens (apps, links, stretch windows) |
| `blocks.json` | what each block blocks (apps, sites, exceptions) |
| `blocked.html` | the "Not now" page blocked tabs are sent to (written by the app) |
| `logs/sessions.jsonl` | one line per session: start, end, planned, actual, note |
| `logs/modes.log` | event log: launches, blocks, quit apps, blocked sites, prompts, reviews |

## Code

`swift build` and `swift test` work from the repo root (Swift 6, macOS 13+); `scripts/build.sh` wraps the release build into the app.

| Path | What |
|---|---|
| `Sources/FocusModes/App/` | entry point and single-instance check, `Model` (state, timer, sessions, free time, night), `Clock`, `WindowCoordinator` (prompt and main windows) |
| `Sources/FocusModes/Domain/` | pure logic: `Session` and `AppPhase`, session records, daily `Limits`, `AppSettings` and night hours, `BlockRule` and its URL matching |
| `Sources/FocusModes/Services/` | `Blocker` (locks, quitting blocked apps, checking Chrome's tabs), workspace (apps and a Chrome window), saved state, settings file, history, log, notifications |
| `Sources/FocusModes/UI/` | Today list, panel, "What's next?"/review, main window (stats, activities, rules), theme |
| `Tests/FocusModesTests/` | tests for the domain logic, URL matching and the saved-state migration |

## Known limits

- Sites are blocked in **Google Chrome** only. Chrome's tabs are checked every 1.5 s, so a blocked page can show for a moment. Other browsers (Safari, Firefox, Arc, Edge, Brave, …) are quit while a block with sites is on.
- Blocked apps are asked to quit, then force-quit after 3 s if they're still running.
- A lock can be extended but never shortened.
- macOS hides menu bar icons that don't fit. ⌘-drag ◎ next to the clock to keep it visible.
- This is self-control, not security: anyone with admin rights can unload the launch agent or change the settings.
