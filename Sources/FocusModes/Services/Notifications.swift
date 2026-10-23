import AppKit
import UserNotifications

// A banner plus the Glass sound. Uses Notification Center once it's allowed; until then
// (or when running outside the app bundle) falls back to AppleScript's notification.
func notify(_ title: String, _ text: String) {
    NSSound(named: "Glass")?.play()
    guard Bundle.main.bundleIdentifier != nil else { return scriptNotify(title, text) }
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
        guard settings.authorizationStatus == .authorized else { return scriptNotify(title, text) }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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
