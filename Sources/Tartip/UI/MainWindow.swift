import SwiftUI

enum MainTab: String, CaseIterable {
    case setup = "Get started", tasks = "Tasks", activities = "Activities", rules = "Optional features", stats = "Stats"

    // Until first-run setup is done Get started is the only page: there's nothing to see
    // in Stats yet, and Activities and Rules would compete with it. Afterwards it's gone.
    @MainActor static var shown: [MainTab] { Setup.isPending ? [.setup] : [.activities, .rules] + (Settings.current.has(.tasks) ? [.tasks] : []) + (Settings.current.has(.statistics) ? [.stats] : []) }

    var icon: String {
        switch self {
        case .setup: return "sparkles"
        case .stats: return "chart.bar"
        case .activities: return "list.bullet"
        case .tasks: return "checklist"
        case .rules: return "slider.horizontal.3"
        }
    }
}

// One window for everything that isn't "now": a Craft-style sidebar on the left,
// the selected page on the right.
struct MainView: View {
    @ObservedObject var model: Model
    @ObservedObject private var settings = Settings.shared
    @State var tab: MainTab
    var close: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.separator).frame(width: 1)
            ScrollView {
                Group {
                    switch tab {
                    case .setup: GetStartedView(model: model, done: close).padding(28)
                    case .stats: StatsView(model: model)
                    case .tasks: TaskPlanningView(model: model, clock: model.clock).padding(28)
                    case .activities, .rules: SettingsView(model: model, page: tab).padding(28)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.bg)
        }
        .frame(width: 820, height: 620)
        .environment(\.colorScheme, .light)
        .onChange(of: settings.value.features) { _ in
            if !MainTab.shown.contains(tab) { tab = .activities }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(nsImage: Logo.image(size: 16, color: .white))
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accent))
                Text("Tartip").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10).padding(.top, 30).padding(.bottom, 14)
            ForEach(MainTab.shown, id: \.self) { t in
                Button { tab = t } label: {
                    Label(t.rawValue, systemImage: t.icon)
                        .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? Theme.text : Theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tab == t ? Theme.card : .clear)
                            .shadow(color: .black.opacity(tab == t ? 0.06 : 0), radius: 3, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 190)
        .background(Theme.pill.opacity(0.5))
    }
}
