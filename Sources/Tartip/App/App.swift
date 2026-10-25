// Tartip (Tatar тәртип, "order"): a menu bar app that blocks apps and sites for a timed session and keeps you honest.

import SwiftUI
import AppKit
import UserNotifications

// Builds the app's objects once, in order: the single-instance check has to run
// before the model starts quitting blocked apps.
@MainActor
final class AppRoot {
    static let shared = AppRoot()
    let model: Model
    let windows: WindowCoordinator

    private init() {
        Rename.carryOverState()  // before Setup: the old app's state says this isn't a new install
        Setup.resolve()          // first: everything after this writes files that would hide a new install
        enforceSingleInstance()
        AutoStart.ensure()       // a copy opened by hand hands over to launchd, which closes it
        model = Model()
        windows = WindowCoordinator(model: model)
    }
}

// Only one copy. The launchd copy always wins: it restarts on any exit,
// so if it were the one to quit it would loop.
private func enforceSingleInstance() {
    let mine = ProcessInfo.processInfo.processIdentifier
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.user.tartip")
        .filter { $0.processIdentifier != mine }
    let fromLaunchd = ProcessInfo.processInfo.environment["TARTIP_LAUNCHD"] == "1"
    if !others.isEmpty {
        if fromLaunchd { others.forEach { $0.forceTerminate() } }
        else { exit(0) }
    }
    log("launch pid=\(mine) via \(fromLaunchd ? "launchd" : "other")")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)   // Craft-like light look everywhere
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        // A new install asks on Get started, where it's explained, not at launch.
        if !Setup.isPending { requestNotificationPermission() }
        AppRoot.shared.windows.start()
    }

    // Opening the app again (Finder, Spotlight) while setup isn't done brings Get started back:
    // with no Dock icon this is the way to find a window that went behind others.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Setup.isPending { AppRoot.shared.windows.openMain(.setup) }
        return true
    }

    // Show banners even while the panel makes this app the active one.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("quit pid=\(ProcessInfo.processInfo.processIdentifier)")
    }
}

@main
struct TartipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppRoot.shared.model
    @ObservedObject private var clock = AppRoot.shared.model.clock

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model, clock: clock, openMain: AppRoot.shared.windows.openMain)
                .noFocusRings()
        } label: {
            if model.session == nil && model.freeTimeEnd == nil && Settings.current.isNight(at: clock.now) {
                Image(systemName: "moon.stars.fill")
            } else if model.session == nil && model.freeTimeEnd == nil {
                Image(nsImage: Logo.menuBar)
            } else {
                Text(model.menuTitle).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
