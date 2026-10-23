import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Activities (what a session is for) and session history

let activitiesFile = modesDir.appendingPathComponent("activities.txt")
let sessionsFile = modesDir.appendingPathComponent("logs/sessions.jsonl")
let defaultActivities = ["Work", "Arabic", "AI education", "Project", "English"]
let otherActivity = "Other"

// One line per session in sessions.jsonl.
struct SessionRecord: Codable, Equatable {
    var start: Date
    var end: Date
    var mode: String
    var planned: String?
    var actual: [String] = []
    var note: String?

    var seconds: Int { max(0, Int(end.timeIntervalSince(start))) }
    var asPlanned: Bool { planned != nil && actual == [planned!] }
}

func recordCoder() -> (JSONEncoder, JSONDecoder) {
    let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    return (e, d)
}

func appendRecord(_ r: SessionRecord) {
    guard let data = try? recordCoder().0.encode(r), var line = String(data: data, encoding: .utf8) else { return }
    line += "\n"
    try? FileManager.default.createDirectory(at: sessionsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let h = try? FileHandle(forWritingTo: sessionsFile) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: sessionsFile, atomically: true, encoding: .utf8)
    }
}

func loadRecords() -> [SessionRecord] {
    guard let text = try? String(contentsOf: sessionsFile, encoding: .utf8) else { return [] }
    let dec = recordCoder().1
    return text.split(separator: "\n").compactMap { try? dec.decode(SessionRecord.self, from: Data($0.utf8)) }
}

// Activity names come from Settings; activities.txt is only read once to migrate.
func loadActivities() -> [String] { S.activities.map(\.name).filter { !$0.isEmpty } }

func legacyLoadActivities() -> [String] {
    let text = (try? String(contentsOf: activitiesFile, encoding: .utf8)) ?? ""
    let list = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if list.isEmpty {
        try? (defaultActivities.joined(separator: "\n") + "\n").write(to: activitiesFile, atomically: true, encoding: .utf8)
        return defaultActivities
    }
    return list
}

struct ActivityStyle {
    let icon: String
    let color: Color

    static func of(_ name: String) -> ActivityStyle {
        let n = name.lowercased()
        if n == "work" { return ActivityStyle(icon: "briefcase.fill", color: .blue) }
        if n.contains("arab") { return ActivityStyle(icon: "character.book.closed.fill", color: .green) }
        if n.contains("ai") { return ActivityStyle(icon: "brain", color: .purple) }
        if n.contains("project") { return ActivityStyle(icon: "hammer.fill", color: .orange) }
        if n.contains("english") { return ActivityStyle(icon: "textformat.abc", color: .teal) }
        if n == "rest" { return ActivityStyle(icon: "cup.and.saucer.fill", color: .brown) }
        if n.contains("interview") { return ActivityStyle(icon: "person.2.wave.2.fill", color: .indigo) }
        if n == otherActivity.lowercased() { return ActivityStyle(icon: "ellipsis.circle.fill", color: .gray) }
        return ActivityStyle(icon: "circle.fill", color: .pink)
    }
}

// A start that's waiting for the activity to be picked.
struct PendingStart {
    var block: String
    var phases: [Phase]
    var extra: [String]
    var auto = false   // opened automatically because nothing is running: no Cancel
}

// Normal closable window (the main Stats / Activities / Rules window).
final class StatsWindow {
    private var window: NSWindow?
    private let title: String

    init(title: String = "Focus stats") { self.title = title }

    func show<V: View>(_ view: V) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = title
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.moveToActiveSpace]
            window = w
        }
        guard let window else { return }
        let host = NSHostingView(rootView: view.background(Theme.bg).environment(\.colorScheme, .light))
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// Hide (never close) the menu bar panel: a closed MenuBarExtra window can't be reopened,
// and the menu bar icon would stop responding.
private var loggedWindowClasses = false

func hideMenuPanel(except keep: NSWindow? = nil) {
    if !loggedWindowClasses {
        loggedWindowClasses = true
        log("windows: " + NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))@\($0.level.rawValue)" }.joined(separator: ", "))
    }
    for w in NSApp.windows where w !== keep && w.isVisible
        && String(describing: type(of: w)).contains("MenuBarExtra") {
        w.orderOut(nil)
    }
}

final class PromptWindow {
    private var panel: NSPanel?

    func show<V: View>(_ view: V) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isMovableByWindowBackground = true
            // Above everything, including the menu bar panel and full-screen apps.
            p.level = .screenSaver
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.standardWindowButton(.closeButton)?.isHidden = true
            p.standardWindowButton(.miniaturizeButton)?.isHidden = true
            p.standardWindowButton(.zoomButton)?.isHidden = true
            panel = p
        }
        guard let panel else { return }
        // Close the menu bar panel so it doesn't sit on top of the question.
        hideMenuPanel(except: panel)
        let host = NSHostingView(rootView: view.background(Theme.bg).environment(\.colorScheme, .light))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.center()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func hide() { panel?.orderOut(nil) }
}
