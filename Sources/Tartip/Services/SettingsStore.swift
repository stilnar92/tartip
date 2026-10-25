import Foundation
import Combine

@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var value: AppSettings {
        didSet {
            guard value != oldValue else { return }
            // Locked: a looser change is undone right here, so no screen has to know the rules.
            if let until = lockedUntil, case let why = loosenings(from: oldValue, to: value), !why.isEmpty {
                value = oldValue
                refuse("Locked until \(Fmt.weekdayClock.string(from: until)): no " + why.joined(separator: ", ") + ".")
                return
            }
            if value.lock.mode != oldValue.lock.mode { changedAt = Date() } else { noteChange() }
            save()
        }
    }

    // Why the last change was undone, shown for a few seconds.
    @Published private(set) var refused: String?

    // Start of the current round of changes, for the "after a change" lock.
    private var changedAt: Date? {
        get { UserDefaults.standard.object(forKey: "settingsChangedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "settingsChangedAt") }
    }

    // Until when looser changes are refused; nil = not locked (never during first-run setup).
    var lockedUntil: Date? {
        Setup.isPending ? nil : value.lock.lockedUntil(now: Date(), changedAt: changedAt)
    }

    // "Settings lock at 14:32": the grace after a change, while it's still open.
    var locksAt: Date? { value.lock.locksAt(changedAt: changedAt, now: Date()) }

    // Any change, here or to blocks.json, can start the "after a change" lock.
    func noteChange() {
        if value.lock.newRound(now: Date(), changedAt: changedAt) { changedAt = Date() }
    }

    func refuse(_ message: String) {
        refused = message
        log("lock  refused: \(message)")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if self?.refused == message { self?.refused = nil }
        }
    }

    // The current settings.
    static var current: AppSettings { shared.value }

    private init() {
        var s = Settings.load()
        let moved = Settings.moveModeConfigs(into: &s)
        value = s
        if moved || !FileManager.default.fileExists(atPath: settingsFile.path) { save() }
    }

    func updateActivity(_ id: UUID, _ change: (inout ActivitySetting) -> Void) {
        guard let i = value.activities.firstIndex(where: { $0.id == id }) else { return }
        change(&value.activities[i])
    }

    private static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsFile) else { return migrated(AppSettings()) }
        return AppSettings.merged(over: data) ?? AppSettings()
    }

    // No settings.json yet. A new install starts with free time and night off, so Get started
    // doesn't choose for the user. An old install takes its list from activities.txt and the
    // "Other" block from blocks.txt.
    private static func migrated(_ d: AppSettings) -> AppSettings {
        var s = d
        if Setup.isPending {
            s.dailyFreeMinutes = 0
            s.nightEnabled = false
        }
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
        do { try enc.encode(value).write(to: settingsFile) } catch { log("error: couldn't save \(settingsFile.path): \(error)") }
    }
}

