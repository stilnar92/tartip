import Foundation

// Start at login and come back after a quit, also when the app was installed by dragging it
// from the DMG. A copy opened by hand writes the launch agent (the same as
// launchd/com.user.tartip.plist, pointing at itself) and loads it; the launchd copy that starts
// then closes this one (enforceSingleInstance), so from here on it's the one that runs.
enum AutoStart {
    static let label = "com.user.tartip"
    static let agentFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")

    static func ensure() {
        guard ProcessInfo.processInfo.environment["TARTIP_LAUNCHD"] != "1",
              Bundle.main.bundleIdentifier == label,      // not `swift run`
              let exe = Bundle.main.executablePath else { return }
        // Not from the mounted DMG or a build folder: the agent would point at a file that goes away.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard exe.hasPrefix("/Applications/") || exe.hasPrefix(home + "/Applications/") else {
            log("auto-start skipped: not in Applications (\(exe))")
            return
        }
        if programPath() == exe && isLoaded() { return }
        do {
            try FileManager.default.createDirectory(at: agentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: agent(exe), format: .xml, options: 0).write(to: agentFile)
        } catch {
            log("auto-start: couldn't write \(agentFile.path): \(error)")
            return
        }
        let domain = "gui/\(getuid())"
        run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        let status = run("/bin/launchctl", ["bootstrap", domain, agentFile.path])
        log("auto-start installed for \(exe) (bootstrap \(status))")
    }

    // Keep in step with launchd/com.user.tartip.plist.
    static func agent(_ exe: String) -> [String: Any] {
        ["Label": label,
         "ProgramArguments": [exe],
         "RunAtLoad": true,
         "KeepAlive": true,     // relaunch after any exit, including a normal quit
         "EnvironmentVariables": ["TARTIP_LAUNCHD": "1"],
         "ThrottleInterval": 5,
         "LimitLoadToSessionType": "Aqua"]
    }

    private static func programPath() -> String? {
        guard let data = try? Data(contentsOf: agentFile),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (plist["ProgramArguments"] as? [String])?.first
    }

    private static func isLoaded() -> Bool {
        run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]) == 0
    }
}
