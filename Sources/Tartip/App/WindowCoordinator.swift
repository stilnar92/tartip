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
                while !Task.isCancelled && Setup.isPending && Settings.current.has(.guidance) {
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
        case .picking: prompt.show(ActivityPickerView(model: model, clock: model.clock), fullScreen: Settings.current.pickerFullScreen)
        case .reviewing:
            let fullScreen = Settings.current.reviewFullScreen
            let screen = NSScreen.main ?? NSScreen.screens.first
            let available = (fullScreen ? screen?.frame : screen?.visibleFrame)?.size ?? CGSize(width: 1024, height: 768)
            let size = CGSize(width: min(fullScreen ? 1080 : 880, max(280, available.width - 64)),
                              height: min(fullScreen ? 820 : 680, max(300, available.height - 80)))
            prompt.show(ReviewView(model: model, size: size), fullScreen: fullScreen)
        case .idle, .session, .freeTime, .away: prompt.hide()
        }
    }
}

// Normal closable window (the main Stats / Activities / Rules window).
@MainActor
final class MainWindowController {
    private var window: NSWindow?
    private let title = "Tartip"

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
        let host = NSHostingView(rootView: view.background(Theme.bg).environment(\.colorScheme, .light).noFocusRings())
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
// Full screen ("What's next?" with the Rules setting on): it covers the whole screen, menu bar
// included, can't be moved, and dims any other screens, so there's nowhere else to go.
@MainActor
final class PromptWindow {
    private var panel: NSPanel?
    private var isFullScreen = false
    private var covers: [NSPanel] = []

    func show<V: View>(_ view: V, fullScreen: Bool = false) {
        if panel == nil || isFullScreen != fullScreen {
            panel?.orderOut(nil)
            panel = fullScreen ? Self.fullScreenPanel() : Self.floatingPanel()
            isFullScreen = fullScreen
        }
        guard let panel else { return }
        // Close the menu bar panel so it doesn't sit on top of the question.
        hideMenuPanel(except: panel)
        let content = view.background(Theme.bg).environment(\.colorScheme, .light).noFocusRings()
        if fullScreen, let screen = NSScreen.main ?? NSScreen.screens.first {
            let host = NSHostingView(rootView: ZStack {
                Theme.bg
                content.card(radius: 22)
            }
            .environment(\.colorScheme, .light))
            panel.contentView = host
            panel.setFrame(screen.frame, display: true)
            coverOtherScreens(than: screen)
        } else {
            let host = NSHostingView(rootView: content)
            panel.contentView = host
            panel.setContentSize(host.fittingSize)
            panel.center()
            removeCovers()
        }
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
        removeCovers()
    }

    private static func floatingPanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        return onTop(p)
    }

    private static func fullScreenPanel() -> NSPanel {
        let p = KeyPanel(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isMovable = false
        p.isMovableByWindowBackground = false
        return onTop(p)
    }

    // Above everything, including the menu bar, the menu bar panel and full-screen apps, on every Space.
    private static func onTop(_ p: NSPanel) -> NSPanel {
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        return p
    }

    private func coverOtherScreens(than main: NSScreen) {
        removeCovers()
        for screen in NSScreen.screens where screen != main {
            let c = Self.onTop(KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false))
            c.isMovable = false
            c.backgroundColor = NSColor(white: 0.08, alpha: 0.96)
            c.setFrame(screen.frame, display: true)
            c.orderFrontRegardless()
            covers.append(c)
        }
    }

    private func removeCovers() {
        covers.forEach { $0.orderOut(nil) }
        covers = []
    }
}

// A borderless panel can't take keyboard focus by default; the picker's own dialogs need it.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
