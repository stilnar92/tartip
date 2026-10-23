# Focus Modes

A small macOS menu bar app that helps you **start** working and keeps you from drifting off. You pick what you'll work on; the app turns on the matching [Cold Turkey](https://getcoldturkey.com/) block for a set time, opens what you need on a dedicated desktop, and afterwards asks what you actually did. If you sit at the computer without doing anything, it nudges you, and then makes you pick.

## How a day works

1. **Start.** Click ◎ in the menu bar → **Start** → pick a length (default 30 min, never under 15) and an activity (Work, Arabic, English, …).
2. **Blocking.** The Cold Turkey block **with the same name as the activity** is locked for the session. Anything typed under "Other" uses `Focus_Mode`.
3. **Workspace.** The app switches to Desktop 7 and opens the activity's apps and links (set them up in **Edit modes**).
4. **Review.** When time's up (or you stop), it asks what you did: confirm the plan, or pick what you did instead. That goes into the stats.
5. **Idle guard.** On weekdays 10:00–22:00, after 15 minutes at the computer without a session, a window counts down 60 s and then opens the picker. Nothing is blocked until you pick.
6. **Free time.** ☕ Rest unblocks nothing for 5–15 min. Rest and idle time share one budget of 60 min a day. Rest can't be taken twice in a row; a session has to run in between.
7. **Daily limits.** Each activity can have a daily limit (e.g. Work 1h). Once it's used up, the activity disappears from the picker for the rest of the day. When nothing is left, only "Other" remains.
8. **Night.** From 00:00 to 08:00 the night block (`Focus_Mode`) is locked until morning. No prompts, no timers, and nothing can be started.

All the numbers above are defaults and can be changed in **Settings** (the gear in the panel).

## Setup

### 1. Cold Turkey

Install [Cold Turkey Blocker](https://getcoldturkey.com/) (Pro is needed for locks). Create one block per activity, **named exactly like the activity** (case and spaces matter):

```
Work, Arabic, AI education, Project, English, Interview, Rest, Focus_Mode
```

`Focus_Mode` is used for "Other" and at night. To allow only certain sites in a block, block `*` and add the allowed sites as exceptions.

### 2. Build and install

```sh
scripts/build.sh            # builds /Applications/Focus Modes.app and starts it
NO_START=1 scripts/build.sh # build only
```

The build needs the Xcode command-line tools (`swiftc`). It:
- compiles `Sources/` into `/Applications/Focus Modes.app`
- draws the icon (`scripts/make-icon.swift`)
- signs the app with a local self-signed certificate "FocusModes Local", created once in your login keychain, so macOS remembers permissions across rebuilds
- installs the launch agent (`launchd/com.user.focusmodes.plist`): the app starts at login and comes back within seconds if it's quit

### 3. Permissions (once)

- **Accessibility** (System Settings → Privacy & Security → Accessibility → Focus Modes): needed to switch desktops and resize windows.
- **Desktop shortcut:** the app enables "Switch to Desktop N" (⌃N) itself; Desktop 7 must exist in Mission Control.
- **Chrome automation:** allow "Focus Modes" to control Google Chrome when asked; links open in a separate Chrome window that's closed when you switch activities.

## Data

Everything personal lives in `~/modes`, outside the repo:

| File | What |
|---|---|
| `settings.json` | all settings, including activities and daily limits |
| `modes.json` | what each activity opens (apps, links, stretch windows) |
| `logs/sessions.jsonl` | one line per session: start, end, planned, actual, note |
| `logs/modes.log` | event log: launches, Cold Turkey commands, prompts, reviews |

## Code

| Path | What |
|---|---|
| `Sources/App.swift` | entry point, menu bar item, single-instance logic |
| `Sources/Model.swift` | state, timer loop, sessions, rest, prompts, limits, night |
| `Sources/Settings.swift` | `AppSettings` and its JSON storage |
| `Sources/Rules.swift` | guard hours, presence detection, values derived from settings |
| `Sources/Activities.swift` | session history, activity styles, helper windows |
| `Sources/Workspace.swift` | desktop switch, opening apps/Chrome, cleanup |
| `Sources/Core.swift` | paths, process helpers, logging, Cold Turkey CLI |
| `Sources/Views/` | panel, prompt, picker/review, stats, settings |

## Known limits

- **Cold Turkey 4.9's command line never exits** and can take more than 15 s to apply a block. The app keeps each command running for the whole lock and closes it afterwards; while it runs, Cold Turkey's own window may not open. Newer Cold Turkey versions behave better.
- The command line can start and stop existing blocks but can't create them or add apps to them; that's done once in Cold Turkey.
- Cold Turkey can extend a lock but never shorten it.
- macOS hides menu bar icons that don't fit. ⌘-drag ◎ next to the clock to keep it visible.
- This is self-control, not security: anyone with admin rights can unload the launch agent or change the settings.
