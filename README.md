# Focus Modes

A small macOS menu bar app that helps you **start** working and keeps you from drifting off. You pick what you'll work on; the app turns on the matching [Cold Turkey](https://getcoldturkey.com/) block for a set time, opens the apps and sites you need, and afterwards asks what you actually did. Whenever nothing is running, it asks what's next, so the decision is always yours and always made.

## How a day works

1. **Start.** Click ◎ in the menu bar → **Start** → pick a length (default 30 min, never under 15) and an activity (Work, Arabic, English, …).
2. **Blocking.** The Cold Turkey block **with the same name as the activity** is locked for the session. **Rest** is an activity too: a short break between tasks with its own block, so a break doesn't turn into a movie.
3. **Workspace.** The app opens the activity's apps and links (set them up in Settings → Activities → ⌄). For a one-off site, use **Open a site** before pressing Start.
4. **Review.** When time's up (or you stop), it asks what you did: confirm the plan, or pick what you did instead. That goes into the stats.
5. **Always decide.** Whenever nothing is running (no session, no free time) and it isn't night, the "What's next?" window opens right away and can't be closed. Nothing is blocked until you pick an activity or free time.
6. **Free time.** 🍿 Free time blocks nothing (movies, YouTube) and comes from a budget of 60 min a day. It's offered in the "What's next?" window and in the panel, and is only ever taken on purpose. It can't be taken twice in a row; a session has to run in between.
7. **Daily limits.** Each activity can have a daily limit (e.g. Work 1h). Once it's used up, the activity disappears from the picker for the rest of the day. When nothing is left, the picker says so.
   **Hours.** An activity can also have hours (e.g. Work 12:00–20:00). Outside them it's greyed out in the picker with "from 12:00".
8. **Night.** From 00:00 to 08:00 the night block (`Focus_Mode`) is locked until morning. No prompts, no timers, and nothing can be started.

All the numbers above are defaults and can be changed in **Settings** (the gear in the panel).

## Setup

### 1. Cold Turkey

Install [Cold Turkey Blocker](https://getcoldturkey.com/) (Pro is needed for locks). Create one block per activity, **named exactly like the activity** (case and spaces matter):

```
Work, Arabic, AI education, Project, English, Interview, Rest, Focus_Mode
```

`Focus_Mode` is the night block. To allow only certain sites in a block, block `*` and add the allowed sites as exceptions.

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

- **Accessibility** (System Settings → Privacy & Security → Accessibility → Focus Modes): needed to stretch opened windows to fill the screen.
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
| `Sources/Rules.swift` | presence detection, values derived from settings |
| `Sources/Activities.swift` | session history, activity styles, helper windows |
| `Sources/Workspace.swift` | opening apps and a Chrome window, cleanup |
| `Sources/Core.swift` | paths, process helpers, logging, Cold Turkey CLI |
| `Sources/Views/` | panel, picker/review, free time row, stats, settings, what an activity opens |

## Known limits

- **Cold Turkey 4.9's command line never exits** and can take more than 15 s to apply a block. The app keeps each command running for the whole lock and closes it afterwards; while it runs, Cold Turkey's own window may not open. Newer Cold Turkey versions behave better.
- The command line can start and stop existing blocks but can't create them or add apps to them; that's done once in Cold Turkey.
- Cold Turkey can extend a lock but never shorten it.
- macOS hides menu bar icons that don't fit. ⌘-drag ◎ next to the clock to keep it visible.
- This is self-control, not security: anyone with admin rights can unload the launch agent or change the settings.
