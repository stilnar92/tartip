# Minimal first-run experience

Status: implemented in the working tree; validation results below.

## Goal

A new user can start a useful focus session without learning the app's discipline system. Extra capabilities are enabled deliberately in Settings. Existing installations retain their current behavior and data.

## Current implementation findings

- `UI/GetStartedView.swift:34` presents explanations followed by activities, blocking, free time, night, and permissions. New users must understand the whole system before starting.
- `Services/SettingsStore.swift:76` already starts new installations with night and free time off. This does not disable the discipline loop.
- `App/Model.swift:450` automatically changes idle into picking. Setting auto-start to zero only stops automatic session selection; it does not stop the unclosable picker.
- `App/Model.swift:333` sends every session of at least a minute into mandatory review. Without review, completion needs an explicit persistence path.
- `App/Model.swift:300` starts block locks and workspace effects. Initialization and return from away also restore/extend locks. UI visibility alone cannot disable these effects.
- `UI/MainWindow.swift:8` exposes Tasks, Activities, Rules, and Stats immediately after setup. The panel and Today list also expose tasks, free time, workspace links, and Pomodoro independently of those pages.
- `App/App.swift:20`, `Services/AutoStart.swift:12`, `install.sh`, and `scripts/build.sh` install or restore a KeepAlive launch agent. Changing only the app launch path would leave source installs intrusive.
- `Domain/Settings.swift:151` fills missing saved fields from defaults. Fresh-install defaults must be distinct from legacy compatibility defaults.
- `Domain/SettingsLock.swift:51` guards weaker settings changes. New module switches must participate in that policy.

## Proposed first run

One small welcome screen:

- An editable activity named Focus, ready to use.
- A duration, initially 30 minutes.
- Start focus, plus a way to dismiss setup and return later.
- One sentence: Add blocking, tasks, and other tools later in Settings.

Start begins the session immediately; it does not open another compulsory picker. The user does not choose modules during installation. No permission checklist, login registration, automatic activity selection, or night schedule is required.

The basic panel shows the activity, duration, Start/Stop, and today's focused time. Session completion saves elapsed time and returns to idle. No compulsory review or task completion is inferred. Preserve the current policy for very short sessions unless separately changed and documented.

The basic settings page contains activities, default duration, and an Optional features entry. Advanced controls and navigation appear when their corresponding capability is enabled. Basic session recording remains available even when the detailed statistics screen is hidden.

## Optional capabilities

| Capability | When off | When enabled |
|---|---|---|
| Distraction blocking | No new session block commitments | Configure apps/sites per activity; explain effects before starting |
| Workspace opening | No app/link/file opening or resizing | Configure activity workspace; request relevant permission when used |
| Tasks | No task buttons, previews, or task page | Daily activity checklists; can be used independently of reviews |
| Pomodoro | A simple duration timer | Work/break controls and contextual menu actions |
| Scheduling and daily targets | Activities are available without schedule restrictions | Days, hours, limits, timeline, and explicit round behavior |
| Session review | Save an unreviewed record and return to idle | Ask what was done; optionally include enabled tasks |
| Continuous guidance | Idle remains idle | What's next? loop; auto-start and free-time budgeting are subordinate options |
| Night rules | No new night commitments | Deliberate night schedule, with clear blocking dependencies |
| Settings lock | Settings editable | Existing delay/window policy, including restrictive module switches |
| Detailed statistics | Keep records, hide advanced analysis | Show detailed Stats navigation |
| Launch at login | Start manually | Register login launch; distinguish this from relaunch-after-quit enforcement |

Defaults for new users: all optional capabilities off. Automatic relaunch is not silently implied by launch at login. Existing users keep their current launch behavior.

Dependencies are explicit: auto-start requires guidance; free-time budgeting has meaning within guidance; night blocking requires blocking. Enabling a prerequisite must be deliberate. Disabling a capability preserves its saved configuration and task/history data.

## Implementation boundaries

1. Add a typed capability policy with separate fresh-install and legacy migration entry points. Use an explicit persisted version/marker so incomplete onboarding and subsequent upgrades are deterministic. Do not infer capabilities only from nonempty configuration.
2. Centralize effective capability checks. Both views and runtime actions use them; shortcuts, context menus, reopening windows, and persisted states follow the same rules.
3. Introduce an effective session policy snapshot for new sessions. Decode old sessions using legacy semantics. Later settings changes affect future sessions; they cannot retroactively introduce or erase a running commitment.
4. Update start, restore, pause/resume, stop, completion, and idle transitions. Preserve existing block deadlines and settings-lock enforcement. Do not turn off the blocker tick while outstanding commitments exist.
5. Save unreviewed completed sessions without claiming the planned activity was confirmed. Existing record logic already supports empty actual activities with planned-time attribution. Never mark tasks complete automatically.
6. Replace first-run setup with the small entry screen and add a settings capability catalog. Remove disabled features from all panel/sidebar/activity/review/context-menu surfaces. If the current page disappears, navigate to a valid core page.
7. Make permission prompts contextual. Accessibility is only relevant when window resizing is enabled and used; Chrome automation only for enabled browser operations; notifications are requested when the user enables them or explicitly chooses completion alerts.
8. Align DMG launch, source installation, rebuilds, and updates with the saved lifecycle policy. Preserve the existing user's launch agent instead of removing it during migration.
9. Update README and development instructions to describe the minimal defaults and opt-in discipline behavior.

## Validation before shipping

- Fresh install and interrupted onboarding: no compulsory prompt, automatic session, app/site blocking, workspace launch, or launch agent before opt-in.
- Start/stop/completion and restart: records saved exactly once, no required review, no inferred task completion.
- Each optional capability: enabling exposes its controls and behavior; disabling stops future behavior and retains its configuration.
- Old full/partial settings, legacy files, and renamed-app defaults: current values and behavior retained.
- Saved picking, review, free-time, night, active session, and away states: explicit migration/transition behavior with no hidden stalled state.
- Active commitments: block deadlines survive disable attempts, restart, and pause/resume; settings lock cannot be bypassed through module switches.
- UI routes: disabled features inaccessible through sidebar, panel buttons, context menus, timer click, and global shortcuts.
- Permission prompts: none for disabled features; denial does not break the basic timer.
- Both installation routes: fresh installs stay manual; updates preserve existing lifecycle behavior.
- Use isolated test storage/defaults and an alternate app output path. A development launch otherwise shares the real ~/modes directory.

## Backup completed before changes

Location: `/Users/ilnar/Tartip Backups/2026-10-29_18-19-20_before-minimal-setup`.

Includes the complete `~/modes` folder, launch-agent plist, raw preferences plist, and a `defaults export` of `com.user.tartip` (state, setup, tasks, locks, and settings-change metadata). A manifest records SHA-256 hashes for 33 copied/exported files; hashes were rechecked after copying.

This is a live backup: the application was not stopped, so it is not an atomic cross-file snapshot. Before deployment or data migration, take another backup during a controlled stop. Restoring later must account for new sessions recorded since the backup and use the exported preferences rather than overwriting a plist behind the preferences daemon.

## Decision record: dialectical review

One blind-solver round generated three different approaches. A separate discriminator examined concrete failure modes for each. Stop criterion: a strong candidate was found after one round.

| Candidate | Essence | Verdict | Key failure mode |
|---|---|---|---|
| S1: Feature modules | Small timer core plus independently enabled capabilities | Strong; recommended with the safeguards above | UI can hide a feature while restart/wake still executes it |
| S2: Two operating modes | Manual timer or guided discipline | Viable; not selected | Enabling one desired feature brings unrelated features back |
| S3: Session recipes and day controller | Compose each activity; separate all-day automation | Viable; deferred | Larger migration and competing transition ownership |

S1 wins over S2 because users can choose tasks or blocking without adopting compulsory guidance. It borrows immutable active-session commitments from S3 without introducing a full recipe architecture.

Principal risks and mitigations:

1. Legacy behavior changes through missing-key defaults: explicit versioned migration, separate fresh/legacy policies, and partial-settings fixtures.
2. Hidden functionality still runs: centralized effective policy, checks at action entry points, and restart/wake/context-menu tests.
3. Disabling a module weakens a current commitment: retain independent block deadlines, snapshot session policy, and extend settings-lock comparisons.
4. Disabled reviews leave the model stuck or fabricate confirmed work: reconcile existing pending review state without discarding it, and record future unreviewed sessions with empty actual activities.
5. Installer recreates unwanted background persistence: app and installation/update paths share the lifecycle decision.
6. The feature catalog becomes a second overwhelming onboarding: place it only in Settings, use short descriptions, and reveal details only for enabled capabilities.

## Implementation and validation

Implemented the typed feature policy, minimal onboarding, conditional navigation and editors, session policy snapshots, unreviewed history persistence with a durable retry outbox, preserved legacy behavior, contextual permissions, optional startup policy, and matching installation paths. Added Step away and Notifications as explicit optional capabilities. Night scheduling may be enabled alone; actual night blocking requires the separate blocking capability.

Fresh pre-implementation backup: `/Users/ilnar/Tartip Backups/2026-10-30_21-04-03_before-implementation` (33 files verified; live copy).

Validation covers fresh/legacy settings, disabled schedules, active and paused session restoration, legacy session decoding, settings-lock feature switches, independent tasks/reviews and login/relaunch choices, completion records, and outbox replay across history timestamp precision. Builds and unit tests do not install or launch the application against personal data.

Verified: 92 tests in 19 suites pass; debug/test and optimized release builds succeed; `zsh -n install.sh scripts/build.sh` and `git diff --check` pass. The installed application was not replaced or launched for testing. Native UI interactions and the live launchd handoff remain untested end to end.
