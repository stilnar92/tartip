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
    @State private var sites: Set<String> = Self.hasChrome ? Set(siteGroups.filter(\.suggested).flatMap(\.sites)) : []
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
                      subtitle: "Set it up once, and from then on it does the pushing. Nothing happens until you press Start.")
            idea
            howItWorks
            section("1", "Your activities", "What do you want to spend focused time on? Add your own, or start from a template.") {
                activities
            }
            section("2", "What gets blocked", "While an activity runs, these apps are closed and these sites don't open.") {
                blocking
            }
            section("3", "Free time", "The one way out of the loop: nothing is blocked and nothing is asked. It comes from a daily budget and is only taken on purpose.") {
                freeTime
            }
            section("4", "Night", "From this hour until morning nothing is asked, and the same apps and sites stay blocked.") {
                night
            }
            footer
        }
    }

    // MARK: the idea

    // What sets the app apart: it doesn't wait for you to decide to focus, it makes you.
    private var idea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You don't have to make yourself start.")
                .font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.text)
            Text("Most focus apps wait until you decide to focus, and deciding is the hard part. Focus doesn't wait: it asks, it starts, and it holds you to it. You only choose what to work on.")
                .font(.system(size: 13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card(Theme.accent, radius: 14)
    }

    // The loop the app runs every day, in the app's own voice.
    private var howItWorks: some View {
        let s = settings.value
        let wait = s.autoStartAfterMinutes
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                step("questionmark.bubble.fill", "It asks",
                     "Whenever nothing is running, \"What's next?\" comes up over everything and can't be closed.")
                step("hand.point.up.left.fill", wait > 0 ? "You pick, or it picks" : "You pick",
                     wait > 0 ? "Choose an activity and a length. Leave it unanswered for \(wait) min and Focus starts one for you."
                              : "Choose an activity and a length.")
                step("lock.fill", "It holds you to it",
                     "Distracting apps close and sites don't open until the timer ends. Stopping early doesn't lift the block.")
            }
            Text("Afterwards you say what you actually did. "
                 + (s.dailyFreeMinutes > 0 ? "The only break from it is free time: \(minutesLabel(s.dailyFreeMinutes)) a day, taken on purpose. "
                                           : "There's no free time, so there's no break from it. ")
                 + "At night it leaves you alone and keeps distractions blocked.")
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
            // Each site on its own, so it's clear what "Social" means; the group name ticks them all.
            ForEach(siteGroups, id: \.name) { g in
                let on = g.sites.filter(sites.contains).count
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        if on == g.sites.count { sites.subtract(g.sites) } else { sites.formUnion(g.sites) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: g.icon).foregroundStyle(Theme.accent)
                            Text(g.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(on == g.sites.count ? "all" : on == 0 ? "none" : "\(on) of \(g.sites.count)")
                                .font(.system(size: 11)).foregroundStyle(Theme.text2)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(on == g.sites.count ? "Untick all" : "Tick all")
                    FlowLayout {
                        ForEach(g.sites, id: \.self) { site in
                            toggleChip(sites.contains(site), action: { sites.formSymmetricDifference([site]) }) {
                                Text(site)
                            }
                        }
                    }
                }
                .disabled(!Self.hasChrome)
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

    // MARK: 3. free time

    private var freeTime: some View {
        VStack(alignment: .leading, spacing: 10) {
            choice("Per day", [0, 30, 60, 90, 120], $settings.value.dailyFreeMinutes) { $0 == 0 ? "None" : minutesLabel($0) }
            if settings.value.dailyFreeMinutes > 0 {
                choice("One stretch at most", [15, 30, 60, 120], $settings.value.maxRestMinutes) { minutesLabel($0) }
            }
        }
    }

    // A row of pills; a value set elsewhere (Rules) that isn't among them is shown as well.
    private func choice(_ label: String, _ options: [Int], _ value: Binding<Int>, _ title: @escaping (Int) -> String) -> some View {
        let all = options.contains(value.wrappedValue) ? options : (options + [value.wrappedValue]).sorted()
        return HStack(spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(width: 130, alignment: .leading)
            ForEach(all, id: \.self) { v in
                Button { value.wrappedValue = v } label: {
                    Text(title(v)).font(.system(size: 12, weight: value.wrappedValue == v ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .pill(selected: value.wrappedValue == v)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 4. night

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
        let chosen = siteGroups.flatMap(\.sites).filter(sites.contains)
        // "a, b and c" in English: the UI isn't localized, so the system language mustn't leak in.
        let and = { (l: [String]) in l.count < 2 ? l.joined() : l.dropLast().joined(separator: ", ") + " and " + l.last! }
        let what = [appNames.isEmpty ? nil : "closes " + and(appNames),
                    chosen.isEmpty ? nil : "blocks " + (chosen.count <= 3 ? and(chosen)
                                                        : chosen.prefix(3).joined(separator: ", ") + " and \(chosen.count - 3) more sites")]
            .compactMap { $0 }
        return what.isEmpty ? "Nothing is blocked yet: add apps or sites above, or later in Activities."
                            : "During a session Focus " + what.joined(separator: " and ") + "."
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary).font(.system(size: 13)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("After Start, Focus takes over: \"What's next?\" comes up right away.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
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
        let web = siteGroups.flatMap(\.sites).filter(sites.contains)
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
