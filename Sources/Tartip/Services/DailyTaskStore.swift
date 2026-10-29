import Foundation

// Separate from settings and session state: checking a task never loosens a rule.
enum DailyTaskStore {
    private static let key = "dailyActivityTasks"

    static func load(from defaults: UserDefaults = .standard) -> DailyTasks {
        guard let data = defaults.data(forKey: key) else { return DailyTasks() }
        do { return try JSONDecoder().decode(DailyTasks.self, from: data) }
        catch {
            log("error: couldn't read daily tasks: \(error)")
            return DailyTasks()
        }
    }

    static func save(_ tasks: DailyTasks, to defaults: UserDefaults = .standard) {
        do { defaults.set(try JSONEncoder().encode(tasks), forKey: key) }
        catch { log("error: couldn't save daily tasks: \(error)") }
    }
}
