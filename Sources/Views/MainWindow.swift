import SwiftUI
import AppKit

enum MainTab: String, CaseIterable {
    case stats = "Stats", activities = "Activities", rules = "Rules"

    var icon: String {
        switch self {
        case .stats: return "chart.bar"
        case .activities: return "list.bullet"
        case .rules: return "slider.horizontal.3"
        }
    }
}

// One window for everything that isn't "now": a Craft-style sidebar on the left,
// the selected page on the right.
struct MainView: View {
    @ObservedObject var m: Model
    @State var tab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.separator).frame(width: 1)
            ScrollView {
                Group {
                    switch tab {
                    case .stats: StatsView(m: m)
                    case .activities: SettingsView(m: m).activitiesPage.padding(28)
                    case .rules: SettingsView(m: m).rulesPage.padding(28)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.bg)
        }
        .frame(width: 820, height: 620)
        .environment(\.colorScheme, .light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "scope").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accent))
                Text("Focus").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 10).padding(.top, 30).padding(.bottom, 14)
            ForEach(MainTab.allCases, id: \.self) { t in
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
