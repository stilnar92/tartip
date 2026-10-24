import SwiftUI
import AppKit

// First-run setup: what the app does, your activities, what gets blocked, night, then Start.
// Activities and night edit the real settings as you go; what to block is applied on Start.
// Nothing is asked or blocked before Start (see Setup), so this page can take its time.
struct GetStartedView: View {
    @ObservedObject var model: Model
    @ObservedObject var settings = Settings.shared
    let done: () -> Void

    @State private var apps: Set<String> = Set(Self.installed.filter { $0.app.suggested }.map(\.id))
    @State private var sites: Set<String> = Self.hasChrome ? Set(siteGroups.filter(\.suggested).map(\.name)) : []
    @State private var newName = ""
    @State private var newIcon = "circle.fill"

    // Distracting apps that are actually on this Mac, with the bundle id that was found.
    private static let installed: [(app: DistractionApp, id: String, url: URL)] = distractionApps.compactMap { a in
        for id in a.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return (a, id, url) }
        }
        return nil
    }
    private static let hasChrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageTitle(title: "Welcome to Focus",
                      subtitle: "A couple of minutes to set up. Nothing is blocked until you press Start.")
            howItWorks
            section("1", "Your activities", "What do you want to spend focused time on? Add your own, or start from a template.") {
                activities
            }
            section("2", "What gets blocked", "While an activity runs, these apps are closed and these sites don't open.") {
                blocking
            }
            section("3", "Night", "From this hour until morning nothing is asked, and the same apps and sites stay blocked.") {
                night
            }
            footer
        }
    }

    // MARK: how it works

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                step("hand.tap.fill", "Pick", "Choose an activity and how long: 15 min, an hour, or Pomodoro.")
                step("lock.fill", "Stay on it", "Distracting apps close and sites don't open until the timer ends.")
                step("checkmark.circle.fill", "Look back", "Say what you actually did; Stats shows your day.")
            }
            Text("When nothing is running, Focus asks \"What's next?\" so the day doesn't drift. Free time (1 h a day) blocks nothing.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ icon: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .card(radius: 12)
    }

    // MARK: 1. activities

    private var activities: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !settings.value.activities.isEmpty {
                FlowLayout {
                    ForEach(settings.value.activities) { a in
                        let st = ActivityStyle.of(a)
                        HStack(spacing: 6) {
                            IconPicker(icon: st.icon, color: st.color, size: 12) { icon in
                                settings.updateActivity(a.id) { $0.icon = icon }
                            }
                            Text(a.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                            Button { settings.value.activities.removeAll { $0.id == a.id } } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.text2)
                        }
                        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
                        .card(st.color, radius: 10)
                    }
                }
            }
            HStack(spacing: 8) {
                IconPicker(icon: newIcon, color: Theme.accent, size: 13) { newIcon = $0 }
                TextField("Your own, e.g. Thesis", text: $newName)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .onSubmit(addOwn)
                Button("Add", action: addOwn)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .card(radius: 10)
            let unused = activityTemplates.filter { t in !settings.value.activities.contains { $0.name.lowercased() == t.name.lowercased() } }
            if !unused.isEmpty {
                Text("Templates").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
                FlowLayout {
                    ForEach(unused, id: \.self) { t in
                        Button { settings.value.activities.append(ActivitySetting(template: t)) } label: {
                            Label(t.name, systemImage: t.icon)
                                .font(.system(size: 12))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .pill()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func addOwn() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !settings.value.activities.contains(where: { $0.name.lowercased() == name.lowercased() }) else { return }
        var a = ActivitySetting(name: name)
        if newIcon != "circle.fill" { a.icon = newIcon }
        settings.value.activities.append(a)
        newName = ""
        newIcon = "circle.fill"
    }

    // MARK: 2. blocking

    private var blocking: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            if Self.installed.isEmpty {
                Text("None of the usual distractions are installed. You can add any app later in Activities → ⌄ → Blocks.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            } else {
                FlowLayout {
                    ForEach(Self.installed, id: \.id) { item in
                        toggleChip(apps.contains(item.id), action: { apps.formSymmetricDifference([item.id]) }) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 16, height: 16)
                            Text(item.app.name)
                        }
                    }
                }
            }
            Text("Sites").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            FlowLayout {
                ForEach(siteGroups, id: \.name) { g in
                    toggleChip(sites.contains(g.name), action: { sites.formSymmetricDifference([g.name]) }) {
                        Image(systemName: g.icon)
                        Text(g.name)
                    }
                    .help(g.sites.joined(separator: ", "))
                    .disabled(!Self.hasChrome)
                }
            }
            Text(Self.hasChrome
                 ? "Sites are blocked in Google Chrome: a blocked tab shows a \"Not now\" page. Other browsers are closed while sites are blocked, and macOS will ask to let Focus control Chrome."
                 : "Site blocking needs Google Chrome; without it, only apps are blocked. You can add sites later.")
                .font(.system(size: 11)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleChip<Content: View>(_ on: Bool, action: @escaping () -> Void, @ViewBuilder _ content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                content()
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            }
            .font(.system(size: 12, weight: on ? .medium : .regular))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .pill(selected: on)
        }
        .buttonStyle(.plain)
    }

    // MARK: 3. night

    private var night: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Night mode", isOn: $settings.value.nightEnabled).toggleStyle(.switch).controlSize(.small)
            if settings.value.nightEnabled {
                HStack(spacing: 16) {
                    clockStepper("From", $settings.value.nightFrom)
                    clockStepper("Until", $settings.value.nightTo)
                }
            }
        }
    }

    private func clockStepper(_ label: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.text2)
            Text(clockLabel(value.wrappedValue)).font(.system(size: 13, weight: .medium)).monospacedDigit()
            Stepper("", onIncrement: { value.wrappedValue = (value.wrappedValue + 30) % 1440 },
                        onDecrement: { value.wrappedValue = (value.wrappedValue + 1410) % 1440 }).labelsHidden()
        }
    }

    // MARK: start

    private var canStart: Bool { settings.value.activities.contains { $0.name.lowercased() != "rest" } }

    private var summary: String {
        let appNames = Self.installed.filter { apps.contains($0.id) }.map(\.app.name)
        let siteNames = siteGroups.filter { sites.contains($0.name) }.map { $0.name.lowercased() }
        let and = { (list: [String]) in ListFormatter.localizedString(byJoining: list) }
        let what = [appNames.isEmpty ? nil : "closes " + and(appNames),
                    siteNames.isEmpty ? nil : "blocks " + and(siteNames) + " sites"]
            .compactMap { $0 }
        return what.isEmpty ? "Nothing is blocked yet: add apps or sites above, or later in Activities."
                            : "During a session Focus " + what.joined(separator: " and ") + "."
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary).font(.system(size: 13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { start() } label: {
                    Text("Start").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(Capsule().fill(canStart ? Theme.accent : Theme.text2.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                if !canStart {
                    Text("Add at least one activity").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Button("Use a simple setup") {
                    if !canStart, let work = activityTemplates.first { settings.value.activities.append(ActivitySetting(template: work)) }
                    start()
                }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.accent)
                .help("Adds Work if you have no activity yet, keeps the ticked apps and sites, and starts.")
            }
        }
        .padding(16)
        .card(radius: 14)
    }

    private func start() {
        guard canStart else { return }
        let web = siteGroups.filter { sites.contains($0.name) }.flatMap(\.sites)
        model.finishSetup(base: BlockRule(apps: Self.installed.filter { apps.contains($0.id) }.map(\.id), web: web))
        done()
    }

    // MARK: building blocks

    private func section<Content: View>(_ number: String, _ title: String, _ note: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(number).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.accent))
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            }
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            content()
        }
    }
}
