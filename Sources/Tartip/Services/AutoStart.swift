import Foundation

// The same policy is used after a DMG launch and a source install. New installs
// create no launch agent. Existing installations retain their legacy policy.
@MainActor
enum AutoStart {
    static let label = "com.user.tartip"
    static let agentFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    private static var pending: Task<Void, Never>?

    static func scheduleUpdate() {
        pending?.cancel()
        pending = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            ensure()
        }
    }

    static func ensure() {
        guard Bundle.main.bundleIdentifier == label,
            let exe = Bundle.main.executablePath
        else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard exe.hasPrefix("/Applications/") || exe.hasPrefix(home + "/Applications/") else { return }
        let settings = Settings.current
        let enabled = settings.has(.login)
        let loaded = run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]) == 0
        let desired = agent(exe, keepAlive: settings.has(.relaunch))
        if enabled, loaded,
            let data = try? Data(contentsOf: agentFile),
            let existing = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            NSDictionary(dictionary: existing).isEqual(to: desired)
        {
            return
        }
        if !enabled && !loaded && !FileManager.default.fileExists(atPath: agentFile.path) { return }
        do {
            if enabled {
                try FileManager.default.createDirectory(at: agentFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: desired, format: .xml, options: 0)
                    .write(to: agentFile, options: .atomic)
            } else if FileManager.default.fileExists(atPath: agentFile.path) {
                try FileManager.default.removeItem(at: agentFile)
            }
            // A child of the app can be killed with its launchd process group.
            // Submit the handoff as a separate one-shot job so it survives bootout.
            // Paths remain arguments, never interpolated into shell source.
            let helperLabel = label + ".startup." + UUID().uuidString
            let script = """
                /bin/sleep 1
                /bin/launchctl bootout "$1/com.user.tartip" 2>/dev/null || true
                if [ "$2" = "on" ]; then
                    /bin/launchctl bootstrap "$1" "$3"
                else
                    /usr/bin/open "$4"
                fi
                /bin/launchctl remove "$5"
                """
            let status = run("/bin/launchctl", ["submit", "-l", helperLabel, "--", "/bin/sh", "-c", script,
                "tartip-startup", "gui/\(getuid())", enabled ? "on" : "off", agentFile.path,
                Bundle.main.bundleURL.path, helperLabel])
            if status != 0 {
                throw NSError(domain: "Tartip.Startup", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not schedule startup handoff"])
            }
        } catch {
            log("auto-start: \(error)")
            Settings.shared.refuse("Could not update startup behavior. Try toggling Launch at login again.")
        }
    }

    static func agent(_ exe: String, keepAlive: Bool = true) -> [String: Any] {
        [
            "Label": label, "ProgramArguments": [exe], "RunAtLoad": true,
            "KeepAlive": keepAlive, "EnvironmentVariables": ["TARTIP_LAUNCHD": "1"],
            "ThrottleInterval": 5, "LimitLoadToSessionType": "Aqua",
        ]
    }
}
