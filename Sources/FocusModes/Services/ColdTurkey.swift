import Foundation

// Starts and stops blocks. A protocol, so the model doesn't depend on the real CLI.
protocol Blocker: Sendable {
    func lock(_ block: String, until end: Date)
    func stop(_ block: String)
    func clearStrayCommands()
}

struct ColdTurkey: Blocker {
    static let path = "/Applications/Cold Turkey Blocker.app/Contents/MacOS/Cold Turkey Blocker"

    // Locks for the whole minutes left until `end` (Cold Turkey can extend a lock, never shorten it).
    func lock(_ block: String, until end: Date) {
        let minutes = Int((end.timeIntervalSinceNow / 60).rounded(.up))
        guard minutes > 0 else { return }
        run(["-start", block, "-lock", String(minutes)], keep: Double(minutes * 60 + 60))
    }

    func stop(_ block: String) { run(["-stop", block]) }

    // Leftover CLI processes (e.g. after the app restarted) keep the Cold Turkey
    // window from opening. Clear them when no session needs them.
    func clearStrayCommands() {
        FocusModes.run("/usr/bin/pkill", ["-f", "Cold Turkey Blocker -(start|stop) "])
    }

    // Cold Turkey 4.9's CLI never exits, and it can take well over 15 s to apply a block
    // (e.g. right after the display wakes). Closing it before then cancels the start;
    // closing it after the block is on is harmless. So keep it running for `keep` seconds.
    private func run(_ args: [String], keep: TimeInterval = 60) {
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Self.path)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return log("ct    failed to run: \(args.joined(separator: " "))") }
            log("ct    pid=\(p.processIdentifier) \(args.joined(separator: " "))")
            let deadline = Date().addingTimeInterval(keep)
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 1) }
            if p.isRunning { p.terminate() } else { log("ct    pid=\(p.processIdentifier) exited \(p.terminationStatus)") }
        }
    }
}
