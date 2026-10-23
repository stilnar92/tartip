// What each mode opens: desktop switch, apps, a Chrome window, and cleanup of the previous mode.

import SwiftUI
import AppKit
import ApplicationServices

// What a mode opens when it starts.
struct ModeConfig: Codable, Equatable {
    var apps: [String] = []        // .app paths
    var urls: [String] = []
    var maximize: Bool = true      // stretch windows to fill the screen

    init(apps: [String] = [], urls: [String] = [], maximize: Bool = true) {
        self.apps = apps; self.urls = urls; self.maximize = maximize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? []
        maximize = try c.decodeIfPresent(Bool.self, forKey: .maximize) ?? true
    }
}

// What the last start opened, so the next start can clean it up.
struct OpenedWorkspace: Codable {
    var mode: String
    var apps: [String]
    var chromeWindow: Int?
}

// MARK: workspace (switch desktop, open apps / sites, close the previous mode's)

func axTrusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
}

@discardableResult
func osascript(_ script: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func appleString(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

// Turns on System Settings → Keyboard Shortcuts → Mission Control → "Switch to Desktop n" (⌃n)
// if it's off, since switchToDesktop relies on it. Ids: Desktop 1 = 118 … Desktop 9 = 126.
func ensureDesktopHotkey(_ n: Int) {
    let keyCodes = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25]
    guard let code = keyCodes[n] else { return }
    let id = String(117 + n)
    let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
    if let entry = hotkeys?[id] as? [String: Any], (entry["enabled"] as? Bool) == true { return }
    let ascii = 48 + n   // "7" → 55
    let value = "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array>"
        + "<integer>\(ascii)</integer><integer>\(code)</integer><integer>262144</integer>"
        + "</array><key>type</key><string>standard</string></dict></dict>"
    run("/usr/bin/defaults", ["write", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys", "-dict-add", id, value])
    // Apply without logging out.
    run("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings", ["-u"])
    log("enabled hotkey ⌃\(n) for Desktop \(n)")
}

// Presses ⌃<n> = "Switch to Desktop n" (System Settings → Keyboard → Shortcuts → Mission Control).
func switchToDesktop(_ n: Int) {
    let keyCodes: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25]
    guard let code = keyCodes[n] else { return }
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
        e?.flags = .maskControl
        e?.post(tap: .cghidEventTap)
    }
    Thread.sleep(forTimeInterval: 0.9)   // wait for the slide animation
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
func openWorkspace(mode: String, _ c: ModeConfig, extraURLs: [String], desktop: Int,
                   prev: OpenedWorkspace?, done: @escaping (OpenedWorkspace) -> Void) {
    workspaceQueue.async {
        let trusted = axTrusted(prompt: false)

        // Clean up the previous start: another mode → quit its apps (except ones we need now).
        if let prev {
            if prev.mode != mode { quitApps(prev.apps.filter { !c.apps.contains($0) }) }
            closeChromeWindow(prev.chromeWindow)
        }

        if desktop > 0 {
            ensureDesktopHotkey(desktop)
            if trusted { switchToDesktop(desktop) }
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
        DispatchQueue.main.async { done(opened) }
    }
}
