// Everything that used to be a constant, editable in the Settings window.
// Stored in ~/modes/settings.json; missing keys fall back to the defaults below.

import SwiftUI
import AppKit

let settingsFile = modesDir.appendingPathComponent("settings.json")

struct ActivitySetting: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var dailyMinutes = 0          // 0 = no daily limit
}

struct AppSettings: Codable, Equatable {
    // Guard: when idle time is counted and the 15-min prompt can appear.
    var guardDays = [2, 3, 4, 5, 6]          // Calendar weekdays, 1 = Sunday
    var guardFromHour = 10
    var guardToHour = 22

    // Free time
    var dailyFreeMinutes = 60
    var maxRestMinutes = 60          // longest single stretch of free time
    var idleNudgeMinutes = 15
    var promptCountdownSeconds = 60

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

    // Loaded values are laid over the defaults, so new settings get their default.
    private static func load() -> AppSettings {
        let defaults = AppSettings()
        guard let data = try? Data(contentsOf: settingsFile),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults)) as? [String: Any]
        else { return migrated(defaults) }
        let merged = base.merging(saved) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let s = try? JSONDecoder().decode(AppSettings.self, from: mergedData) else { return defaults }
        return s
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

// Night window, which may cross midnight (e.g. 22:00–06:00).
func isNight(_ d: Date) -> Bool {
    guard S.nightEnabled, S.nightFrom != S.nightTo else { return false }
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    return S.nightFrom < S.nightTo ? (m >= S.nightFrom && m < S.nightTo)
                                   : (m >= S.nightFrom || m < S.nightTo)
}

// When the current night ends.
func nightEnd(after d: Date) -> Date {
    let cal = Calendar.current
    var end = cal.startOfDay(for: d).addingTimeInterval(Double(S.nightTo * 60))
    if end <= d { end = cal.date(byAdding: .day, value: 1, to: end)! }
    return end
}

func clockLabel(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

func limitLabel(_ minutes: Int) -> String {
    if minutes == 0 { return "No limit" }
    return minutes % 60 == 0 ? "\(minutes / 60)h" : (minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m")
}
