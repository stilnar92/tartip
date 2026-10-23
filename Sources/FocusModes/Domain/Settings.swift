// Everything that used to be a constant, editable in the Settings window.
// Stored in ~/modes/settings.json (see SettingsStore); missing keys fall back to the defaults below.

import Foundation

struct ActivitySetting: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var dailyMinutes = 0          // 0 = no daily limit
    var fromMinute: Int? = nil    // hours it can be picked, minutes since midnight;
    var toMinute: Int? = nil      // nil = any time. May cross midnight.
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

    // Night: block stays on, nothing is asked. Minutes since midnight.
    var nightEnabled = true
    var nightFrom = 0
    var nightTo = 8 * 60
    var nightBlock = "Focus_Mode"

    // Workspace
    var otherBlock = "Focus_Mode"         // Cold Turkey block for "Other"

    var activities: [ActivitySetting] = ["Work", "Arabic", "AI education", "Project", "English", "Interview", "Rest"]
        .map { ActivitySetting(name: $0) }
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

    // Each activity has a Cold Turkey block with the same name; "Other" uses its own.
    func block(for activity: String) -> String { activity == otherActivity ? otherBlock : activity }

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
