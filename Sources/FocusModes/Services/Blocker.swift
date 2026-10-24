import AppKit
import Combine

// Locks blocks. A protocol, so the model doesn't depend on the real one.
@MainActor
protocol Blocker: AnyObject {
    // On until `end`. A lock can be extended, never shortened.
    func lock(_ block: String, until end: Date)
    // Called every second: enforces what's locked and drops what has run out.
    func tick(_ now: Date)
}

let blockRulesFile = modesDir.appendingPathComponent("blocks.json")
let blockedPage = modesDir.appendingPathComponent("blocked.html")

let chromeID = "com.google.Chrome"
// Browsers whose tabs we can't see: quit while a block with sites is on.
private let otherBrowsers: Set<String> = [
    "com.apple.Safari", "org.mozilla.firefox", "company.thebrowser.Browser", "company.thebrowser.dia",
    "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium",
    "ru.yandex.desktop.yandex-browser", "app.zen-browser.zen", "com.kagi.kagimacOS",
]
private let neverQuit: Set<String> = ["com.user.focusmodes", "com.apple.finder"]

// Blocking apps and sites while a block is locked (what Cold Turkey used to do).
// Apps from an active block are quit. Chrome's tabs are checked every 1.5 s and blocked
// ones are sent to a "Not now" page; browsers whose tabs we can't see are quit.
@MainActor
final class NativeBlocker: ObservableObject, Blocker {
    static let shared = NativeBlocker()

    @Published private(set) var rules: [String: BlockRule] = [:]
    // Block name → locked until. Kept across restarts.
    @Published private(set) var locks: [String: Date] = UserDefaults.standard.dictionary(forKey: "locks") as? [String: Date] ?? [:]

    private let scriptQueue = DispatchQueue(label: "blocker.chrome")
    private var webBusy = false
    private var lastWebCheck = Date.distantPast
    private var quitting: [pid_t: Date] = [:]        // asked to quit; forced after 3 s
    private var lastNotice: [String: Date] = [:]
    private var launchObserver: NSObjectProtocol?

    private init() {
        load()
        writeBlockedPage()
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweepApps() }
        }
    }

    // MARK: rules (~/modes/blocks.json)

    func load() {
        guard let d = try? Data(contentsOf: blockRulesFile) else { return }
        do { rules = try JSONDecoder().decode([String: BlockRule].self, from: d) }
        catch { log("error: couldn't read \(blockRulesFile.path): \(error)") }
    }

    func rule(_ name: String) -> BlockRule { rules[name] ?? BlockRule() }

    // While a block is locked it can only get stricter: apps and sites can be added, exceptions removed.
    func update(_ name: String, _ change: (inout BlockRule) -> Void) {
        let old = rule(name)
        var r = old
        change(&r)
        if isLocked(name) { r = old.stricter(r) }
        rules[name] = r
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try enc.encode(rules).write(to: blockRulesFile) } catch { log("error: couldn't save \(blockRulesFile.path): \(error)") }
    }

    // MARK: locks

    func isLocked(_ name: String, at now: Date = Date()) -> Bool { (locks[name] ?? .distantPast) > now }

    func lock(_ block: String, until end: Date) {
        guard end > (locks[block] ?? .distantPast) else { return }
        locks[block] = end
        UserDefaults.standard.set(locks, forKey: "locks")
        log("block \(block) until \(Fmt.clock.string(from: end))\(rules[block] == nil ? " (not in blocks.json, nothing to block)" : "")")
        sweepApps()
        lastWebCheck = .distantPast
    }

    private var active: [ActiveBlock] {
        let now = Date()
        return locks.filter { $0.value > now }.sorted { $0.key < $1.key }.map { ActiveBlock(name: $0.key, rule: rule($0.key), until: $0.value) }
    }

    func tick(_ now: Date) {
        let expired = locks.filter { $0.value <= now }.map(\.key)
        if !expired.isEmpty {
            expired.forEach { locks[$0] = nil; log("unblock \($0)") }
            UserDefaults.standard.set(locks, forKey: "locks")
        }
        sweepApps()
        if now.timeIntervalSince(lastWebCheck) >= 1.5 {
            lastWebCheck = now
            sweepWeb()
        }
    }

    // MARK: apps

    private func sweepApps() {
        let act = active
        guard !act.isEmpty else { quitting.removeAll(); return }
        let webBlock = act.first { !$0.rule.web.isEmpty }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, !neverQuit.contains(id) else { continue }
            let name = app.localizedName ?? id
            if let b = act.first(where: { $0.rule.apps.contains { $0.caseInsensitiveCompare(id) == .orderedSame } }) {
                quit(app, because: b, what: name)
            } else if let w = webBlock, otherBrowsers.contains(id) {
                quit(app, because: w, what: "\(name) (sites are blocked; use Chrome)")
            }
        }
        let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        quitting = quitting.filter { running.contains($0.key) }
    }

    private func quit(_ app: NSRunningApplication, because b: ActiveBlock, what: String) {
        let pid = app.processIdentifier
        if let asked = quitting[pid] {
            if Date().timeIntervalSince(asked) > 3 { app.forceTerminate() }
            return
        }
        quitting[pid] = Date()
        app.terminate()
        log("quit  \(app.bundleIdentifier ?? what) (\(b.name))")
        let key = app.bundleIdentifier ?? what
        if Date().timeIntervalSince(lastNotice[key] ?? .distantPast) > 60 {
            lastNotice[key] = Date()
            notify("Blocked: \(what)", "\(b.name) is on until \(Fmt.clock.string(from: b.until)).")
        }
    }

    // MARK: Chrome

    private func sweepWeb() {
        let act = active.filter { !$0.rule.web.isEmpty }
        guard !act.isEmpty, !webBusy,
              let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: chromeID).first,
              chrome.isFinishedLaunching else { return }
        webBusy = true
        scriptQueue.async { [weak self] in
            let denied = Self.redirectBlockedTabs(act)
            Task { @MainActor in
                guard let self else { return }
                self.webBusy = false
                // Automation for Chrome is off, so its tabs can't be checked: Chrome goes instead.
                if denied, let b = act.first,
                   let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: chromeID).first {
                    self.quit(chrome, because: b, what: "Google Chrome (allow Focus Modes to control Chrome in Privacy & Security → Automation)")
                }
            }
        }
    }

    // Reads every tab's URL in one script and sends the blocked ones to the "Not now" page.
    // Runs on scriptQueue. Returns true when macOS refused to let us control Chrome.
    private nonisolated static func redirectBlockedTabs(_ act: [ActiveBlock]) -> Bool {
        var err: NSDictionary?
        let res = NSAppleScript(source: """
            tell application id "\(chromeID)" to return {id of every window, URL of every tab of every window}
            """)?.executeAndReturnError(&err)
        guard let res, err == nil else {
            let code = err?[NSAppleScript.errorNumber] as? Int ?? 0
            return code == -1743 || code == -10004    // not allowed / privilege violation
        }
        guard res.numberOfItems == 2, let ids = res.atIndex(1), let urls = res.atIndex(2) else { return false }
        let page = blockedPage.absoluteString
        var fixes: [String] = []
        for w in 0..<min(ids.numberOfItems, urls.numberOfItems) {
            guard let winID = ids.atIndex(w + 1)?.stringValue, let tabs = urls.atIndex(w + 1) else { continue }
            for t in 0..<tabs.numberOfItems {
                guard let url = tabs.atIndex(t + 1)?.stringValue, !url.hasPrefix(page),
                      let hit = act.first(where: { $0.rule.blocks(url: url) }) else { continue }
                let target = blockedPageURL(url, block: hit.name, until: hit.until)
                fixes.append("set URL of tab \(t + 1) of (first window whose id is \(appleString(winID))) to \(appleString(target))")
                log("site  \(url.prefix(120)) (\(hit.name))")
            }
        }
        if !fixes.isEmpty {
            NSAppleScript(source: "tell application id \"\(chromeID)\"\n" + fixes.joined(separator: "\n") + "\nend tell")?
                .executeAndReturnError(nil)
        }
        return false
    }

    // blocked.html?block=Work&until=<unix time>&url=<the blocked URL>
    private nonisolated static func blockedPageURL(_ url: String, block: String, until: Date) -> String {
        guard var c = URLComponents(url: blockedPage, resolvingAgainstBaseURL: false) else { return blockedPage.absoluteString }
        c.queryItems = [URLQueryItem(name: "block", value: block),
                        URLQueryItem(name: "until", value: String(Int(until.timeIntervalSince1970))),
                        URLQueryItem(name: "url", value: url)]
        return c.url?.absoluteString ?? blockedPage.absoluteString
    }

    private func writeBlockedPage() {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Not now</title>
        <style>
        body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
             font:15px -apple-system,system-ui,sans-serif;background:#f6f5f2;color:#2b2a27}
        .c{text-align:center;max-width:520px;padding:24px}
        h1{font-size:30px;margin:0 0 8px}
        p{color:#77736b;margin:6px 0;word-break:break-all}
        </style></head><body><div class="c">
        <h1>🎯 Not now</h1>
        <p id="b"></p><p id="u"></p>
        </div><script>
        const q = new URLSearchParams(location.search);
        const until = new Date(Number(q.get("until")) * 1000);
        document.getElementById("b").textContent = (q.get("block") || "Focus") + " is on until " +
          until.toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"}) + ".";
        document.getElementById("u").textContent = q.get("url") || "";
        </script></body></html>
        """
        do {
            try FileManager.default.createDirectory(at: modesDir, withIntermediateDirectories: true)
            try html.write(to: blockedPage, atomically: true, encoding: .utf8)
        } catch { log("error: couldn't write \(blockedPage.path): \(error)") }
    }
}

private struct ActiveBlock: Sendable {
    let name: String
    let rule: BlockRule
    let until: Date
}
