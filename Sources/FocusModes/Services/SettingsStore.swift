import Foundation
import Combine

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var v: AppSettings { didSet { if v != oldValue { save() } } }

    private init() {
        var s = Settings.load()
        let moved = Settings.moveModeConfigs(into: &s)
        v = s
        if moved || !FileManager.default.fileExists(atPath: settingsFile.path) { save() }
    }

    func updateActivity(_ id: UUID, _ change: (inout ActivitySetting) -> Void) {
        guard let i = v.activities.firstIndex(where: { $0.id == id }) else { return }
        change(&v.activities[i])
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

    // modes.json used to hold what each activity opens, keyed by its block name, so renaming
    // an activity lost it. Move it into the activities once; the file stays as modes.json.migrated.
    private static func moveModeConfigs(into s: inout AppSettings) -> Bool {
        guard let data = try? Data(contentsOf: configFile),
              let configs = try? JSONDecoder().decode([String: ModeConfig].self, from: data) else { return false }
        for i in s.activities.indices where s.activities[i].opens.isEmpty {
            if let c = configs[s.activities[i].block] ?? configs[s.activities[i].name] { s.activities[i].opens = c }
        }
        do {
            try FileManager.default.moveItem(at: configFile, to: configFile.appendingPathExtension("migrated"))
        } catch {
            log("error: couldn't rename \(configFile.path) after moving it into settings: \(error)")
        }
        log("moved modes.json into settings.json")
        return true
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
