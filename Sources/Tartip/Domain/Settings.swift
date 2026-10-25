// Everything that used to be a constant, editable in the Settings window.
// Stored in ~/modes/settings.json (see SettingsStore); missing keys fall back to the defaults below.

import Foundation

struct ActivitySetting: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var block: String              // block it locks (blocks.json): the name at first, kept when the name changes
    var dailyMinutes = 0           // 0 = no daily limit
    var fromMinute: Int? = nil     // hours it can be picked, minutes since midnight;
    var toMinute: Int? = nil       // nil = any time. May cross midnight.
    var days: [Int] = []           // weekdays it's planned for (Calendar: 1 = Sunday … 7 = Saturday); empty = every day
    var dayMinutes: [Int: Int] = [:]   // a different daily limit on some weekdays (0 = no limit); absent = dailyMinutes.
                                       // "Off on a day" is only ever `days`, never a limit.
    var opens = ModeConfig()       // apps and links opened when it starts
    var icon: String? = nil        // SF Symbol; nil = picked from the name
    var color: String? = nil       // one of ActivityStyle.colors; nil = picked from the name

    init(name: String, dailyMinutes: Int = 0, fromMinute: Int? = nil, toMinute: Int? = nil) {
        self.name = name
        self.block = name
        self.dailyMinutes = dailyMinutes
        self.fromMinute = fromMinute
        self.toMinute = toMinute
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

    // Settings saved before a field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        block = try c.decodeIfPresent(String.self, forKey: .block) ?? name
        dailyMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyMinutes) ?? 0
        fromMinute = try c.decodeIfPresent(Int.self, forKey: .fromMinute)
        toMinute = try c.decodeIfPresent(Int.self, forKey: .toMinute)
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? []
        dayMinutes = try c.decodeIfPresent([Int: Int].self, forKey: .dayMinutes) ?? [:]
        opens = try c.decodeIfPresent(ModeConfig.self, forKey: .opens) ?? ModeConfig()
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        color = try c.decodeIfPresent(String.self, forKey: .color)
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
    // Free time
    var dailyFreeMinutes = 60
    var maxRestMinutes = 60          // longest single stretch of free time

    // Session length
    var durationOptions = [15, 20, 30, 45, 60]
    var defaultMinutes = 30
    var minMinutes = 15
    var pomodoroWork = 25
    var pomodoroBreak = 5
    var pomodoroRounds = 4

    // Auto-start: if "What's next?" stays unanswered this long, start an activity by itself.
    var autoStartAfterMinutes = 15   // 0 = never
    var autoStartMinutes = 30        // length of that session
    var pickerFullScreen = false     // "What's next?" covers the whole screen and can't be moved aside

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
    // Free time lengths offered, never longer than one stretch may be.
    var freeTimeLengths: [Int] { [15, 30, 45, 60, 90, 120].filter { $0 <= maxRestMinutes } }

    func pomodoroPhases() -> [Phase] {
        let rounds = max(1, pomodoroRounds)
        return (0..<rounds).flatMap { i in
            [Phase(isBreak: false, minutes: pomodoroWork)] + (i < rounds - 1 ? [Phase(isBreak: true, minutes: pomodoroBreak)] : [])
        }
    }

    func activity(named name: String) -> ActivitySetting? { activities.first { $0.name == name } }

    // The block an activity locks; "Other" has its own setting.
    func block(for activity: String) -> String {
        if activity == otherActivity { return otherBlock }
        guard let b = self.activity(named: activity)?.block, !b.isEmpty else { return activity }
        return b
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
        guard nightEnabled, nightFrom != nightTo else { return false }
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
