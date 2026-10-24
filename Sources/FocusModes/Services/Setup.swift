import Foundation

// First-run setup. Until it's done the app teaches and collects, but doesn't push:
// no "What's next?", no auto-start, no night lock, so nothing is blocked unseen.
// Kept in its own UserDefaults key, so the saved state's format doesn't change.
enum Setup {
    private static let key = "setup"

    // Decided once, on the very first launch, before anything writes settings or state:
    // later the files exist either way, so they'd no longer tell a new install apart.
    // blocks.json isn't evidence: the README has new users import it before the first launch.
    static func resolve(_ d: UserDefaults = .standard,
                        evidence: [URL] = [settingsFile, sessionsFile, modesDir.appendingPathComponent("activities.txt")]) {
        guard d.string(forKey: key) == nil else { return }
        let existing = evidence.contains { FileManager.default.fileExists(atPath: $0.path) }
            || d.object(forKey: "state") != nil || d.object(forKey: "session") != nil
        d.set(existing ? "done" : "pending", forKey: key)
        log("setup \(existing ? "not needed (existing install)" : "pending (new install)")")
    }

    static func isPending(_ d: UserDefaults) -> Bool { d.string(forKey: key) == "pending" }
    static var isPending: Bool { isPending(.standard) }

    static func markDone(_ d: UserDefaults = .standard) {
        d.set("done", forKey: key)
        log("setup done")
    }
}
