import AppKit
import UserNotifications

// A banner plus the Glass sound. Uses Notification Center once it's allowed; until then
// (or when running outside the app bundle) falls back to AppleScript's notification, which
// shows Script Editor's icon rather than ours.
func notify(_ title: String, _ text: String) {
    NSSound(named: "Glass")?.play()
    guard Bundle.main.bundleIdentifier != nil else { return scriptNotify(title, text) }
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        let allowed = settings.authorizationStatus == .authorized
        notifyPath.logOnce(allowed ? "notifications: Notification Center" : "notifications: AppleScript (not allowed for Tartip)")
        guard allowed else { return scriptNotify(title, text) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

func requestNotificationPermission() {
    guard Bundle.main.bundleIdentifier != nil else { return }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
        if !granted { log("notifications not allowed, using AppleScript") }
    }
}

// osascript takes a moment to start, so it never runs on the main thread.
private func scriptNotify(_ title: String, _ text: String) {
    DispatchQueue.global().async {
        run("/usr/bin/osascript", ["-e", "display notification \(appleString(text)) with title \(appleString(title))"])
    }
}

// Which way banners go, logged once per launch so a wrong icon is easy to trace.
private final class LogOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func logOnce(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        log(line)
    }
}

private let notifyPath = LogOnce()
