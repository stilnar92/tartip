import Foundation
import Combine

@MainActor
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
        do { try enc.encode(v).write(to: settingsFile) } catch { log("error: couldn't save \(settingsFile.path): \(error)") }
    }
}

// The current settings.
@MainActor var S: AppSettings { Settings.shared.v }
