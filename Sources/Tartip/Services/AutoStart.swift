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

    // The installed executable, or nil for a development build, which never registers itself.
    private static var installedExecutable: String? {
        guard Bundle.main.bundleIdentifier == label,
            let exe = Bundle.main.executablePath
        else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return exe.hasPrefix("/Applications/") || exe.hasPrefix(home + "/Applications/") ? exe : nil
    }

    static func ensure() {
        ensureGuard()
        guard let exe = installedExecutable else { return }
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

    // MARK: Guard

    // Relaunch's KeepAlive doesn't survive `launchctl bootout` or a deleted plist: launchd
    // stops the app and forgets it. A second agent checks every minute and opens the app
    // once it has been down `guardDelay` in a row. Opening it runs `ensure()`, which puts
    // the main agent back. The app restores the guard in turn (`startGuardRepair`).
    static let guardLabel = label + ".guard"
    static let guardDelay: TimeInterval = 15 * 60
    static let guardFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(guardLabel).plist")
    static let guardStateFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/\(label)/guard-down-since")
    private static var repair: Timer?

    // $1 app, $2 file holding when it was first seen down, $3 delay in seconds, $4 process name.
    static let guardScript = """
        if /usr/bin/pgrep -x -U "$(/usr/bin/id -u)" "$4" >/dev/null 2>&1; then
            /bin/rm -f "$2"; exit 0
        fi
        now=$(/bin/date +%s)
        since=$(/bin/cat "$2" 2>/dev/null)
        case "$since" in ''|*[!0-9]*)
            /bin/mkdir -p "$(/usr/bin/dirname "$2")"; echo "$now" > "$2"; exit 0 ;;
        esac
        [ $((now - since)) -ge "$3" ] || exit 0
        /bin/rm -f "$2"
        /usr/bin/open "$1"
        """

    static func guardAgent(app: String, stateFile: String, delay: Int = Int(guardDelay), process: String = "Tartip") -> [String: Any] {
        [
            "Label": guardLabel,
            "ProgramArguments": ["/bin/sh", "-c", guardScript, "tartip-guard", app, stateFile, String(delay), process],
            "RunAtLoad": true, "StartInterval": 60, "LimitLoadToSessionType": "Aqua",
        ]
    }

    static func ensureGuard() {
        let domain = "gui/\(getuid())"
        let loaded = run("/bin/launchctl", ["print", "\(domain)/\(guardLabel)"]) == 0
        guard installedExecutable != nil, Settings.current.has(.relaunch) else {
            if loaded { run("/bin/launchctl", ["bootout", "\(domain)/\(guardLabel)"]) }
            try? FileManager.default.removeItem(at: guardFile)
            try? FileManager.default.removeItem(at: guardStateFile)
            return
        }
        let desired = guardAgent(app: Bundle.main.bundleURL.path, stateFile: guardStateFile.path)
        let current = (try? Data(contentsOf: guardFile))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let same = current.map { NSDictionary(dictionary: $0).isEqual(to: desired) } ?? false
        if same && loaded { return }
        do {
            if !same {
                try FileManager.default.createDirectory(at: guardFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: desired, format: .xml, options: 0)
                    .write(to: guardFile, options: .atomic)
                if loaded { run("/bin/launchctl", ["bootout", "\(domain)/\(guardLabel)"]) }
            }
            let status = run("/bin/launchctl", ["bootstrap", domain, guardFile.path])
            if status != 0 { log("guard: bootstrap failed (\(status))") } else { log("guard: installed") }
        } catch {
            log("guard: \(error)")
        }
    }

    // A guard booted out while the app runs is back within a minute.
    static func startGuardRepair() {
        guard repair == nil else { return }
        repair = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { ensureGuard() }
        }
    }
}
