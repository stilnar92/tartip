// Everything that used to be a constant, editable in the Settings window.
// Stored in ~/modes/settings.json; missing keys fall back to the defaults below.

import Foundation
import Combine

let settingsFile = modesDir.appendingPathComponent("settings.json")

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

final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var v: AppSettings { didSet { if v != oldValue { save() } } }

    private init() {
        v = Settings.load()
        if !FileManager.default.fileExists(atPath: settingsFile.path) { save() }
    }

    private static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsFile) else { return migrated(AppSettings()) }
        return AppSettings.merged(over: data) ?? AppSettings()
    }

    // First run: take the activity list from activities.txt and the "Other" block from blocks.txt.
    private static func migrated(_ d: AppSettings) -> AppSettings {
        var s = d
        if let text = try? String(contentsOf: modesDir.appendingPathComponent("activities.txt"), encoding: .utf8) {
            let names = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !names.isEmpty { s.activities = names.map { ActivitySetting(name: $0) } }
        }
        if let text = try? String(contentsOf: modesDir.appendingPathComponent("blocks.txt"), encoding: .utf8),
           let first = text.split(separator: "\n").first.map({ $0.trimmingCharacters(in: .whitespaces) }), !first.isEmpty {
            s.otherBlock = first
            s.nightBlock = first
        }
        return s
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: modesDir, withIntermediateDirectories: true)
        if let d = try? enc.encode(v) { try? d.write(to: settingsFile) }
    }
}

var S: AppSettings { Settings.shared.v }

extension AppSettings {
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

func clockLabel(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

func limitLabel(_ minutes: Int) -> String {
    if minutes == 0 { return "No limit" }
    return minutes % 60 == 0 ? "\(minutes / 60)h" : (minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
}
