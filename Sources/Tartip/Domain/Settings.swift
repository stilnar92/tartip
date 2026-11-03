// Everything that used to be a constant, editable in the Settings window.
// Stored in ~/modes/settings.json (see SettingsStore); missing keys fall back to the defaults below.

import Foundation

// One stretch of the day an activity can be picked in, minutes since midnight. `to` may be
// <= `from`, meaning it crosses midnight (same rule as inWindow).
struct TimeWindow: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: Int
    var to: Int
}

// Clamp `windows[i]`'s `from` or `to` so editing one window can't cross into a same-day
// neighbour: no two windows for one activity are allowed to overlap. Neighbours that touch
// exactly at a boundary (one's `to` equals another's `from`) are fine, left alone. Windows
// that cross midnight (this one, or the neighbour being clamped against) are excluded from
// clamping — reasoning about a neighbour across midnight adds real complexity for no clear
// benefit here.
func clampedWindowEdge(_ windows: [TimeWindow], editing i: Int, movingFrom: Bool, to value: Int) -> Int {
    guard windows.indices.contains(i), windows[i].from < windows[i].to else { return value }
    let w = windows[i]
    let others = windows.enumerated().filter { $0.offset != i }.map(\.element).filter { $0.from < $0.to }
    if movingFrom {
        let floor = others.filter { $0.to <= w.to }.map(\.to).max() ?? 0
        return max(value, floor)
    } else {
        let ceiling = others.filter { $0.from >= w.from }.map(\.from).min() ?? 1440
        return min(value, ceiling)
    }
}

struct ActivitySetting: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var block: String              // block it locks (blocks.json): the name at first, kept when the name changes
    var dailyMinutes = 0           // 0 = no daily limit
    var windows: [TimeWindow] = [] // hours it can be picked; empty = any time. May cross midnight.
    var days: [Int] = []           // weekdays it's planned for (Calendar: 1 = Sunday … 7 = Saturday); empty = every day
    var dayMinutes: [Int: Int] = [:]   // a different daily limit on some weekdays (0 = no limit); absent = dailyMinutes.
                                       // "Off on a day" is only ever `days`, never a limit.
    var catchUpMinutes = 0          // > 0 marks this activity "important": if its hours close with
                                     // none of it done, the next pick is forced to this many minutes of it.
    var opens = ModeConfig()       // apps and links opened when it starts
    var icon: String? = nil        // SF Symbol; nil = picked from the name
    var color: String? = nil       // one of ActivityStyle.colors; nil = picked from the name

    var hasSchedule: Bool { !windows.isEmpty }

    init(name: String, dailyMinutes: Int = 0, fromMinute: Int? = nil, toMinute: Int? = nil) {
        self.name = name
        self.block = name
        self.dailyMinutes = dailyMinutes
        if let f = fromMinute, let t = toMinute, f != t { windows = [TimeWindow(from: f, to: t)] }
    }

    init(name: String, dailyMinutes: Int = 0, windows: [TimeWindow]) {
        self.name = name
        self.block = name
        self.dailyMinutes = dailyMinutes
        self.windows = windows
    }

    init(template t: ActivityTemplate) {
        self.init(name: t.name)
        icon = t.icon
        color = t.color
    }

    // The daily limit on a weekday (Calendar numbering), in minutes; 0 = no limit.
    func limit(onWeekday d: Int) -> Int { dayMinutes[d] ?? dailyMinutes }

    func isPlanned(onWeekday d: Int) -> Bool { days.isEmpty || days.contains(d) }

    // Planned for the day `d` falls on: any day when no days are set.
    func isPlanned(on d: Date, calendar: Calendar = .current) -> Bool {
        isPlanned(onWeekday: calendar.component(.weekday, from: d))
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, block, dailyMinutes, windows, fromMinute, toMinute, days, dayMinutes, catchUpMinutes, opens, icon, color
    }

    // Settings saved before a field existed still load. Settings saved before multiple windows
    // existed have fromMinute/toMinute instead of windows: fold that single pair into one window.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        block = try c.decodeIfPresent(String.self, forKey: .block) ?? name
        dailyMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyMinutes) ?? 0
        if let w = try c.decodeIfPresent([TimeWindow].self, forKey: .windows) {
            windows = w
        } else {
            let f = try c.decodeIfPresent(Int.self, forKey: .fromMinute)
            let t = try c.decodeIfPresent(Int.self, forKey: .toMinute)
            windows = (f != nil && t != nil && f != t) ? [TimeWindow(from: f!, to: t!)] : []
        }
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? []
        dayMinutes = try c.decodeIfPresent([Int: Int].self, forKey: .dayMinutes) ?? [:]
        catchUpMinutes = try c.decodeIfPresent(Int.self, forKey: .catchUpMinutes) ?? 0
        opens = try c.decodeIfPresent(ModeConfig.self, forKey: .opens) ?? ModeConfig()
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(block, forKey: .block)
        try c.encode(dailyMinutes, forKey: .dailyMinutes)
        try c.encode(windows, forKey: .windows)
        try c.encode(days, forKey: .days)
        try c.encode(dayMinutes, forKey: .dayMinutes)
        try c.encode(catchUpMinutes, forKey: .catchUpMinutes)
        try c.encode(opens, forKey: .opens)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(color, forKey: .color)
    }
}

// What an activity opens when it starts.
struct ModeConfig: Codable, Hashable, Sendable {
    var apps: [String] = []        // .app paths
    var urls: [String] = []
    var files: [String] = []       // files and folders, opened in their default app (folders in Finder)
    var maximize: Bool = true      // stretch windows to fill the screen

    init(apps: [String] = [], urls: [String] = [], files: [String] = [], maximize: Bool = true) {
        self.apps = apps; self.urls = urls; self.files = files; self.maximize = maximize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? []
        files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
        maximize = try c.decodeIfPresent(Bool.self, forKey: .maximize) ?? true
    }

    var isEmpty: Bool { apps.isEmpty && urls.isEmpty && files.isEmpty }
}

struct AppSettings: Codable, Equatable {
    var features = Features.legacy
    // Free time
    var dailyFreeMinutes = 60
    var maxRestMinutes = 60          // longest single extended stretch of free time (see alwaysFreeMinutes)
    var alwaysFreeMinutes = 5        // always available after a session, outside the daily budget
    var extendedFreeIntervalHours = 1  // a longer (> alwaysFreeMinutes) stretch can be picked at most this often

    // Session length
    var durationOptions = [15, 20, 30, 45, 60]
    var capSessionsToRemainingTime = true
    var defaultMinutes = 30
    var minMinutes = 15
    var pomodoroWork = 25
    var pomodoroBreak = 5
    var pomodoroRounds = 4

    // Auto-start: if "What's next?" stays unanswered this long, start an activity by itself.
    var autoStartAfterMinutes = 15   // 0 = never
    var autoStartMinutes = 30        // length of that session
    var pickerFullScreen = false     // "What's next?" covers the whole screen and can't be moved aside
    var reviewFullScreen = false     // so does "Session done", until it's answered

    // Away from the computer: a session waits this long, then ends as of when you left.
    var maxAwayMinutes = 60

    // Step away locks the screen for at least this long: unlocking sooner locks it again,
    // until this much has actually elapsed since it started. 0 = no minimum (today's behavior).
    var stepAwayMinutes = 0

    // Forced breaks: after this long continuously at the computer, the session ends and a
    // break is required. 0 = never. The break only lifts once the cooldown runs out.
    var forceBreakAfterHours = 2
    var forceBreakCooldownMinutes = 1

    // Night: block stays on, nothing is asked. Minutes since midnight.
    var nightEnabled = true
    var nightFrom = 0
    var nightTo = 8 * 60
    var nightBlock = "Focus_Mode"

    // Workspace
    var otherBlock = "Focus_Mode"         // block for "Other"

    // Settings lock (off by default): when settings may be loosened.
    var lock = LockSettings()

    // Empty for a new install: first-run setup has the user build the list.
    var activities: [ActivitySetting] = []
}

extension AppSettings {
    // Values derived from the settings.
    var dailyFreeSeconds: Int { dailyFreeMinutes * 60 }
    var sessionLengths: [Int] { durationOptions.filter { $0 >= minMinutes }.sorted() }
    var defaultSessionMinutes: Int { max(defaultMinutes, minMinutes) }
    // Extended free time lengths offered (beyond the always-free minutes), never longer than
    // one stretch may be. The cap itself is always one of them, so a cap under 15 minutes
    // still leaves a choice.
    var freeTimeLengths: [Int] {
        let under = [15, 30, 45, 60, 90, 120].filter { $0 > alwaysFreeMinutes && $0 < maxRestMinutes }
        return maxRestMinutes > alwaysFreeMinutes ? under + [maxRestMinutes] : under
    }

    func pomodoroPhases() -> [Phase] {
        let rounds = max(1, pomodoroRounds)
        return (0..<rounds).flatMap { i in
            [Phase(isBreak: false, minutes: pomodoroWork)] + (i < rounds - 1 ? [Phase(isBreak: true, minutes: pomodoroBreak)] : [])
        }
    }

    func activity(named name: String) -> ActivitySetting? { activities.first { $0.name == name } }

    // The block an activity locks. "Other" has its own setting, but only when there's no real
    // activity by that name — an activity the user made named "Other" is just an activity.
    func block(for activity: String) -> String {
        if let b = self.activity(named: activity)?.block, !b.isEmpty { return b }
        if activity == otherActivity { return otherBlock }
        return activity
    }

    // Saved values are laid over the defaults, so new settings get their default.
    static func merged(over data: Data) -> AppSettings? {
        guard let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any],
              let mergedData = try? JSONSerialization.data(withJSONObject: base.merging(saved) { _, new in new })
        else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: mergedData)
    }

    // Night window, which may cross midnight (e.g. 22:00–06:00).
    func isNight(at d: Date, calendar: Calendar = .current) -> Bool {
        guard has(.night), nightEnabled, nightFrom != nightTo else { return false }
        return inWindow(minuteOfDay(d, calendar: calendar), nightFrom, nightTo)
    }

    // When the current night ends.
    func nightEnd(after d: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: nightTo / 60, minute: nightTo % 60, second: 0, of: d) ?? d
        if today > d { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
}

func minuteOfDay(_ d: Date, calendar: Calendar = .current) -> Int {
    let c = calendar.dateComponents([.hour, .minute], from: d)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

// Whether `m` (minutes since midnight) is inside from..<to, which may cross midnight.
func inWindow(_ m: Int, _ from: Int, _ to: Int) -> Bool {
    from < to ? (m >= from && m < to) : (m >= from || m < to)
}
