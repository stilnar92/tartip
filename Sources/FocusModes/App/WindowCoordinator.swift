import SwiftUI
import AppKit

// Shows the window each phase asks for: "What's next?" while picking, the review after
// a session, nothing otherwise. The main window opens on request.
@MainActor
final class WindowCoordinator {
    private let model: Model
    private let prompt = PromptWindow()
    private let main = MainWindowController()
    private var setupReminder: Task<Void, Never>?

    init(model: Model) { self.model = model }

    // Called once the app has launched; also restores a question left open by a restart.
    func start() {
        model.onPhaseChange = { [weak self] in self?.show(for: $0) }
        show(for: model.phase)
        if Setup.isPending {
            openMain(.setup)
            // A closed Get started comes back every 30 min while you're at the computer,
            // so a new install doesn't sit there doing nothing.
            setupReminder = Task { [weak self] in
                while !Task.isCancelled && Setup.isPending {
                    try? await Task.sleep(for: .seconds(30 * 60))
                    guard let self, Setup.isPending, !self.main.isVisible, userPresent() else { continue }
                    self.openMain(.setup)
                }
            }
        }
    }

    // Stats, Activities and Rules live in one window with a sidebar.
    func openMain(_ tab: MainTab) {
        hideMenuPanel()
        model.reloadRecords()
        let tab = MainTab.shown.contains(tab) ? tab : MainTab.shown[0]
        main.show(MainView(model: model, tab: tab, close: { [weak self] in self?.main.close() }))
    }

    private func show(for phase: AppPhase) {
        switch phase {
        case .picking: prompt.show(ActivityPickerView(model: model, clock: model.clock))
        case .reviewing: prompt.show(ReviewView(model: model))
        case .idle, .session, .freeTime: prompt.hide()
        }
    }
}

// Normal closable window (the main Stats / Activities / Rules window).
@MainActor
final class MainWindowController {
    private var window: NSWindow?
    private let title = "Focus"

    var isVisible: Bool { window?.isVisible == true }
    func close() { window?.close() }

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
@MainActor private var loggedWindowClasses = false

@MainActor
func hideMenuPanel(except keep: NSWindow? = nil) {
    let panels = NSApp.windows.filter { $0 !== keep && $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra") }
    // The class name is private to SwiftUI; log once if it ever stops matching.
    if panels.isEmpty && !loggedWindowClasses && NSApp.windows.contains(where: { $0 !== keep && $0.isVisible }) {
        loggedWindowClasses = true
        log("no MenuBarExtra window among: " + NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))" }.joined(separator: ", "))
    }
    panels.forEach { $0.orderOut(nil) }
}

// Floating panel above everything, without a close button ("What's next?" and the review).
@MainActor
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
