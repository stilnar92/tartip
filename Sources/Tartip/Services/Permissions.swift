import AppKit
import ApplicationServices
import CoreServices
import UserNotifications

// The three macOS permissions the app uses, checked without side effects so Get started can
// say where each one stands before anything relies on it.
enum Access: Equatable {
    case granted, denied, notAsked
    case chromeNotRunning      // Chrome control can only be checked or asked while Chrome runs
}

@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var chrome: Access = .notAsked
    @Published private(set) var notifications: Access = .notAsked
    @Published private(set) var accessibility: Access = .notAsked
    @Published private(set) var askingChrome = false
    private var checkingChrome = false   // one check at a time, so a slow one can't pile up threads

    private var activeSub: NSObjectProtocol?

    init() {
        refresh()
        // Coming back from System Settings: show what changed there.
        activeSub = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .notAsked
        if !checkingChrome && !askingChrome {
            checkingChrome = true
            Task { [weak self] in
                let status = await Task.detached { chromeAutomation(ask: false) }.value
                self?.chrome = status
                self?.checkingChrome = false
            }
        }
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor [weak self] in
                self?.notifications = switch status {
                case .authorized, .provisional: .granted
                case .denied: .denied
                default: .notAsked
                }
            }
        }
    }

    // Shows macOS's own "allow Tartip to control Google Chrome?" prompt, opening Chrome
    // first if needed (the button says so). Runs off the main thread: the call waits for the answer.
    func askChrome() {
        guard !askingChrome else { return }
        askingChrome = true
        if NSRunningApplication.runningApplications(withBundleIdentifier: chromeID).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        Task { [weak self] in
            // Chrome takes a moment to start; it has to be running for the prompt.
            var status = Access.chromeNotRunning
            for _ in 0..<20 where status == .chromeNotRunning {
                status = await Task.detached { chromeAutomation(ask: true) }.value
                if status == .chromeNotRunning { try? await Task.sleep(for: .milliseconds(500)) }
            }
            self?.chrome = status
            self?.askingChrome = false
            log("perm  chrome control: \(status)")
        }
    }

    func askNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    // macOS's Accessibility prompt only offers to open System Settings, so go there directly.
    func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Whether this app may send Apple events to Chrome. With ask, macOS shows its prompt the first
// time and the call waits for the answer, so never call it on the main thread.
// Aimed at one Chrome process, not the bundle id: with more than one Chrome running (a test
// browser, say) a bundle-id check never returns. The permission is per app, so any one will do.
nonisolated func chromeAutomation(ask: Bool) -> Access {
    guard var pid = NSRunningApplication.runningApplications(withBundleIdentifier: chromeID).first?.processIdentifier
    else { return .chromeNotRunning }
    var target = AEAddressDesc()
    guard AECreateDesc(typeKernelProcessID, &pid, MemoryLayout<pid_t>.size, &target) == noErr else { return .notAsked }
    defer { AEDisposeDesc(&target) }
    switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask) {
    case noErr: return .granted
    case OSStatus(errAEEventNotPermitted): return .denied
    case OSStatus(procNotFound): return .chromeNotRunning
    default: return .notAsked     // errAEEventWouldRequireUserConsent: not asked yet
    }
}
