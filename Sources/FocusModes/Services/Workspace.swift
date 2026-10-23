// What each mode opens: apps, a Chrome window, and cleanup of the previous mode.

import AppKit
import ApplicationServices

// What the last start opened, so the next start can clean it up.
struct OpenedWorkspace: Codable, Equatable, Sendable {
    var mode: String
    var apps: [String]
    var chromeWindow: Int?
}

// MARK: workspace (open apps / sites, close the previous mode's)

func axTrusted(prompt: Bool) -> Bool {
    // The value of kAXTrustedCheckOptionPrompt, which Swift 6 sees as a mutable global.
    let key = "AXTrustedCheckOptionPrompt"
    return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
}

func waitForApp(bundleID: String, timeout: Double = 10) -> NSRunningApplication? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, a.isFinishedLaunching { return a }
        Thread.sleep(forTimeInterval: 0.3)
    }
    return nil
}

// Stretches the app's focused window over the visible screen area, waiting up to ~8 s for it.
func maximize(pid: pid_t) {
    guard let screen = NSScreen.main else { return }
    let vf = screen.visibleFrame
    let topY = screen.frame.maxY - vf.maxY            // AX uses a top-left origin
    var pos = CGPoint(x: vf.minX, y: topY)
    var size = CGSize(width: vf.width, height: vf.height)
    let app = AXUIElementCreateApplication(pid)
    for _ in 0..<16 {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
           let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() {
            let w = v as! AXUIElement
            if let p = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p) }
            if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s) }
            return
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
}

func bundleID(_ path: String) -> String? { Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier }

func quitApps(_ paths: [String]) {
    for path in paths {
        guard let id = bundleID(path) else { continue }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
    }
    // Give them a moment so relaunching doesn't race the quit.
    if !paths.isEmpty { Thread.sleep(forTimeInterval: 1.2) }
}

func closeChromeWindow(_ id: Int?) {
    guard let id else { return }
    osascript("""
    if application "Google Chrome" is running then
        tell application "Google Chrome" to close (every window whose id is \(id))
    end if
    """)
}

// Opens the links in one new Chrome window and returns its id.
func openChromeWindow(_ urls: [String]) -> Int? {
    guard let first = urls.first else { return nil }
    var script = """
    tell application "Google Chrome"
        set w to make new window
        set URL of active tab of w to \(appleString(first))

    """
    for u in urls.dropFirst() {
        script += "    tell w to make new tab with properties {URL:\(appleString(u))}\n"
    }
    script += """
        set active tab index of w to 1
        activate
        return id of w
    end tell
    """
    return Int(osascript(script))
}

let workspaceQueue = DispatchQueue(label: "workspace")   // one start at a time

// prev: what the previous start opened. Returns what this start opened.
func openWorkspace(mode: String, _ c: ModeConfig, extraURLs: [String],
                   prev: OpenedWorkspace?, done: @escaping @MainActor @Sendable (OpenedWorkspace) -> Void) {
    workspaceQueue.async {
        let trusted = axTrusted(prompt: false)

        // Clean up the previous start: another mode → quit its apps (except ones we need now).
        if let prev {
            if prev.mode != mode { quitApps(prev.apps.filter { !c.apps.contains($0) }) }
            closeChromeWindow(prev.chromeWindow)
        }

        for path in c.apps {
            guard let id = bundleID(path) else { continue }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
            if let app = waitForApp(bundleID: id), c.maximize && trusted {
                Thread.sleep(forTimeInterval: 0.8)
                maximize(pid: app.processIdentifier)
            }
        }

        let links = (c.urls + extraURLs).map { $0.contains("://") ? $0 : "https://" + $0 }
        var chromeWindow: Int?
        if !links.isEmpty {
            chromeWindow = openChromeWindow(links)
            if c.maximize && trusted, let chrome = waitForApp(bundleID: "com.google.Chrome") {
                Thread.sleep(forTimeInterval: 0.6)
                maximize(pid: chrome.processIdentifier)
            }
        }

        let opened = OpenedWorkspace(mode: mode, apps: c.apps, chromeWindow: chromeWindow)
        Task { @MainActor in done(opened) }
    }
}
