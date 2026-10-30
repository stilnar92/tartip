import AppKit
import SwiftUI

// Where each macOS permission stands, what it's for, and a button to allow it.
// On Get started (step 5) and in Rules, to check later that nothing was turned off.
struct PermissionsList: View {
    @ObservedObject var perms: Permissions
    let blocksSites: Bool  // Chrome control only matters when some block has sites

    static let hasChrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) != nil

    var body: some View {
        VStack(spacing: 8) {
            if Self.hasChrome && (Settings.current.has(.workspace) || (Settings.current.has(.blocking) && blocksSites)) {
                permissionRow(
                    "globe", "Control Google Chrome",
                    !blocksSites
                        ? "Not needed while no sites are blocked."
                        : "Lets Tartip see your Chrome tabs and send a blocked site to the \"Not now\" page. Without it Chrome is closed while sites are blocked.",
                    status: perms.chrome, optional: !blocksSites
                ) {
                    switch perms.chrome {
                    case .granted: EmptyView()
                    case .denied: actionButton("Open System Settings") { perms.openSettings("Privacy_Automation") }
                    case .chromeNotRunning: actionButton(perms.askingChrome ? "Waiting for Chrome…" : "Open Chrome and allow") { perms.askChrome() }
                    case .notAsked: actionButton(perms.askingChrome ? "Waiting…" : "Allow") { perms.askChrome() }
                    }
                }
            }
            if Settings.current.has(.notifications) {
                permissionRow(
                    "bell.badge.fill", "Notifications",
                    "Tells you when a round ends, a session is done, or an app was closed.",
                    status: perms.notifications, optional: false
                ) {
                    switch perms.notifications {
                    case .granted: EmptyView()
                    case .denied: actionButton("Open System Settings") { perms.openNotificationSettings() }
                    default: actionButton("Allow") { perms.askNotifications() }
                    }
                }
            }
            if Settings.current.has(.workspace) {
                permissionRow(
                    "macwindow", "Accessibility",
                    "Only to stretch the apps an activity opens to fill the screen. Blocking works without it.",
                    status: perms.accessibility, optional: true
                ) {
                    if perms.accessibility != .granted {
                        actionButton("Open System Settings") { perms.openSettings("Privacy_Accessibility") }
                    }
                }
            }

        }
    }

    private func permissionRow<Action: View>(
        _ icon: String, _ title: String, _ why: String, status: Access, optional: Bool,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                    switch status {
                    case .granted: Tag(text: "✓ Allowed", color: .green, fill: .green.opacity(0.12))
                    case .denied: Tag(text: "Not allowed", color: Theme.red, fill: Theme.redTint)
                    default: Tag(text: optional ? "Optional" : "Not yet")
                    }
                }
                Text(why).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(12)
        .card(radius: 12)
    }

    private func actionButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).controlSize(.small)
    }
}
