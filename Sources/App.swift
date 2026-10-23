// Focus Modes: a menu bar app that starts Cold Turkey blocks with a timer and keeps you honest.

import SwiftUI
import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        log("quit pid=\(ProcessInfo.processInfo.processIdentifier)")
    }
}

@main
struct FocusModesApp: App {
    @StateObject private var model = Model()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Only one copy. The launchd copy always wins: it restarts on any exit,
        // so if it were the one to quit it would loop.
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.user.focusmodes")
            .filter { $0.processIdentifier != mine }
        let fromLaunchd = ProcessInfo.processInfo.environment["FOCUSMODES_LAUNCHD"] == "1"
        if !others.isEmpty {
            if fromLaunchd { others.forEach { $0.forceTerminate() } }
            else { exit(0) }
        }
        log("launch pid=\(mine) via \(fromLaunchd ? "launchd" : "other")")
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(m: model)
        } label: {
            if model.session == nil {
                Image(systemName: "scope")
            } else {
                Text(model.menuTitle).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
