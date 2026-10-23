// Paths, process helpers, logging and the Cold Turkey CLI.

import AppKit

let ctPath = "/Applications/Cold Turkey Blocker.app/Contents/MacOS/Cold Turkey Blocker"
let modesDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("modes")
let logFile = modesDir.appendingPathComponent("logs/modes.log")
let configFile = modesDir.appendingPathComponent("modes.json")

@discardableResult
func run(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

// Cold Turkey 4.9's CLI never exits, and it can take well over 15 s to apply a block
// (e.g. right after the display wakes). Closing it before then cancels the start;
// closing it after the block is on is harmless. So keep it running for `keep` seconds.
func runCT(_ args: [String], keep: TimeInterval = 60) {
    DispatchQueue.global().async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ctPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { log("ct    failed to run: \(args.joined(separator: " "))"); return }
        log("ct    pid=\(p.processIdentifier) \(args.joined(separator: " "))")
        let deadline = Date().addingTimeInterval(keep)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 1) }
        if p.isRunning { p.terminate() } else { log("ct    pid=\(p.processIdentifier) exited \(p.terminationStatus)") }
    }
}

// Leftover CLI processes (e.g. after the app restarted) also keep the Cold Turkey
// window from opening. Clear them when no session needs them.
func killStrayCTCommands() {
    run("/usr/bin/pkill", ["-f", "Cold Turkey Blocker -(start|stop) "])
}
