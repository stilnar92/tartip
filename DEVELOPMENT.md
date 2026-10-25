# Developing Tartip

How to work on the code. To see what the app does and how to install it, read [README.md](README.md).

## Requirements

- macOS 13+
- Swift 6 (Xcode, or the Command Line Tools: `xcode-select --install`)
- No dependencies beyond SwiftPM and the system frameworks (SwiftUI, AppKit, UserNotifications)

## Build and test

```sh
swift build                  # debug build
swift test                   # unit tests
scripts/build.sh             # release build → /Applications/Tartip.app, then (re)start it
NO_START=1 scripts/build.sh  # same, without starting it
scripts/make-dmg.sh          # universal build → build/Tartip.dmg (the installed copy isn't touched)
```

`scripts/build.sh` also takes `APP=path/Tartip.app` (build there; nothing is stopped or started) and `UNIVERSAL=1` (build arm64 and x86_64 separately with `--triple`, then `lipo` them together, which works with the Command Line Tools alone).

### Auto-start

The app needs the launch agent to start at login and come back after a quit. There are two ways it gets installed:

- `install.sh` / `scripts/build.sh` copy [launchd/com.user.tartip.plist](launchd/com.user.tartip.plist) into `~/Library/LaunchAgents`.
- `AutoStart.ensure()` ([AutoStart.swift](Sources/Tartip/Services/AutoStart.swift)) handles DMG installs. When the app is opened by hand from an Applications folder and the agent is missing, points elsewhere, or isn't loaded, it writes the agent and bootstraps it. The launchd copy then starts and closes the hand-opened one. It does nothing for `swift run` (no bundle id) or when opened from the DMG or a build folder.

Keep `AutoStart.agent` and the plist file in step with each other.

### Distribution

The DMG is signed with the local "Tartip Local" certificate, so on other Macs Gatekeeper asks the user to approve it in Privacy & Security (the README explains this). To avoid that, it needs an Apple Developer ID signature with the hardened runtime and the `com.apple.security.automation.apple-events` entitlement, plus notarization (`xcrun notarytool submit … --wait`, then `xcrun stapler staple`). The script doesn't do this yet.

`./install.sh` is for users. It checks the macOS version and toolchain, installs the launch agent, and runs `scripts/build.sh`. `./install.sh --uninstall` removes the app and the agent.

### What `scripts/build.sh` does

1. Builds the release binary with SwiftPM first, so a failed build leaves the running copy alone.
2. Stops the running copy (`launchctl bootout`, `pkill`) and wraps the binary into `/Applications/Tartip.app` with a generated `Info.plist` (bundle id `com.user.tartip`, `LSUIElement`, so there's no Dock icon).
3. Draws the icon: `scripts/make-icon.swift` is compiled together with `Sources/Tartip/UI/Logo.swift` (the same mark the app draws), and every size is packed into `AppIcon.icns`.
4. Signs the app with **"Tartip Local"**, a self-signed code-signing certificate created once in the login keychain. A stable signature lets macOS keep the Accessibility permission across rebuilds; ad-hoc signatures change every build. If signing fails, it falls back to ad-hoc and says so.
5. Starts the app again under launchd from `~/Library/LaunchAgents/com.user.tartip.plist` (a copy of [launchd/com.user.tartip.plist](launchd/com.user.tartip.plist)): `RunAtLoad`, `KeepAlive` (it relaunches after any exit, even a normal quit) and `TARTIP_LAUNCHD=1`.

### Running a dev build

Only one copy runs at a time (`enforceSingleInstance` in [App.swift](Sources/Tartip/App/App.swift)). The launchd copy always wins: a copy started any other way exits if another copy is already running. To run `swift run` or a debug binary, stop the agent first:

```sh
launchctl bootout gui/$UID/com.user.tartip
swift run Tartip
# when you're done: scripts/build.sh (rebuilds and brings the agent back)
```

A dev build uses the same `~/modes` as the installed app, so back up the folder before you try anything risky. Events are written to `~/modes/logs/modes.log`.

## Architecture

| Path | What |
|---|---|
| `Sources/Tartip/App/` | entry point and single-instance check, `Model` (state, timer, sessions, free time, night), `Clock`, `WindowCoordinator` (prompt and main windows) |
| `Sources/Tartip/Domain/` | pure logic: `Session` and `AppPhase`, session records, daily `Limits`, `AppSettings` and night hours, `BlockRule` and its URL matching, `SettingsLock`, `Starter` (Get started's templates and suggested distractions) |
| `Sources/Tartip/Services/` | `Blocker` (locks, quitting blocked apps, checking Chrome's tabs), `Workspace` (apps and a Chrome window), `AutoStart` (the launch agent), `StateStore` (saved state), `SettingsStore`, `Setup` (first launch), `History`, `Log`, `Notifications`, `Permissions`, `Paths` |
| `Sources/Tartip/UI/` | Today list, panel, "What's next?"/review, Get started, main window (stats, activities, rules), theme, logo |
| `Tests/TartipTests/` | tests for the domain logic, URL matching, schedules, the settings lock, setup and the saved-state migration |
| `scripts/` | `build.sh`, `make-dmg.sh`, `make-icon.swift`, `import-cold-turkey.swift` |
| `launchd/` | the launch agent |

Rules of thumb:

- **Domain stays pure**: no AppKit, no files, no clock reads (pass `now` in). This is what the tests cover, so new rules go there with a test.
- **Services do the side effects**: quitting apps, AppleScript to Chrome, files in `~/modes`, UserDefaults.
- **Stored data must stay readable.** `settings.json`, `blocks.json` and the saved state in UserDefaults (`StateStore`) are read on every launch. When a format changes, migrate the old one (see `StateStore.migrate` and `SettingsStore.migrated`) and add a test, instead of breaking existing installs.

## Data files

Everything personal lives in `~/modes` (see `Paths.swift`): `settings.json`, `blocks.json`, `blocked.html`, `logs/sessions.jsonl`, `logs/modes.log`. The app state needed after a restart (phase, the running session, free time used) is in UserDefaults under `com.user.tartip`, key `state`.
