import SwiftUI

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    var model: Model? = nil                      // for "what it opens"
    let page: MainTab
    @State private var expanded: Set<UUID> = []
    @State private var newActivity = ""
    @State private var optionsText = Settings.shared.value.durationOptions.map(String.init).joined(separator: ", ")

    // The window shows this view itself, not one of its pages as a property:
    // only then does SwiftUI keep its @State (open rows, text being typed).
    var body: some View {
        switch page {
        case .activities: activitiesPage
        case .rules: rulesPage
        case .stats: EmptyView()
        }
    }

    // Pages of the main window's sidebar.
    private var activitiesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Activities", subtitle: "Each one locks a block while it runs: the one with its name, unless you pick another.")
            activitiesSection
        }
    }

    private var rulesPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: "Rules", subtitle: "Night, free time and session length.")
            nightSection
            freeTimeSection
            durationSection
            Text("Saved automatically to ~/modes/settings.json")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    // MARK: sections

    private var activitiesSection: some View {
        group("Your list", "Set a daily limit with the stepper; tap ⌄ for hours and what it opens.") {
            ForEach($settings.value.activities) { $a in
                activityRow($a)
            }
            HStack(spacing: 6) {
                TextField("New activity (locks the block with its name)", text: $newActivity)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .card(radius: 9)
                    .onSubmit(addActivity)
                Button("Add", action: addActivity)
                    .disabled(newActivity.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            dayPlan
        }
    }

    private func activityRow(_ a: Binding<ActivitySetting>) -> some View {
        let item = a.wrappedValue
        let st = ActivityStyle.of(item)
        let open = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: st.icon).foregroundStyle(st.color).frame(width: 18)
                TextField("Name", text: a.name).textFieldStyle(.plain).font(.system(size: 13))
                if let from = item.fromMinute, let to = item.toMinute {
                    Text("\(clockLabel(from))–\(clockLabel(to))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Text(limitLabel(item.dailyMinutes))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(item.dailyMinutes == 0 ? .secondary : .primary)
                    .frame(width: 60, alignment: .trailing)
                Stepper("", value: a.dailyMinutes, in: 0...720, step: 15).labelsHidden().controlSize(.small)
                Button {
                    if open { expanded.remove(item.id) } else { expanded.insert(item.id) }
                } label: {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Hours, block, look and what it opens")
                Button { settings.value.activities.removeAll { $0.id == item.id } } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Hours")
                    Toggle("Any time", isOn: Binding(
                        get: { a.wrappedValue.fromMinute == nil || a.wrappedValue.toMinute == nil },
                        set: { any in
                            a.wrappedValue.fromMinute = any ? nil : 12 * 60
                            a.wrappedValue.toMinute = any ? nil : 20 * 60
                        }))
                        .toggleStyle(.switch).controlSize(.small)
                    if item.fromMinute != nil && item.toMinute != nil {
                        row("Can be picked from") { clockStepper(Binding(get: { a.wrappedValue.fromMinute ?? 720 }, set: { a.wrappedValue.fromMinute = $0 })) }
                        row("Until") { clockStepper(Binding(get: { a.wrappedValue.toMinute ?? 1200 }, set: { a.wrappedValue.toMinute = $0 })) }
                    }
                    Divider()
                    row("Block it locks") { textField(a.block) }
                    BlockEditor(block: item.block.isEmpty ? item.name : item.block)
                    Divider()
                    SectionLabel(text: "Look")
                    lookPicker(a, st)
                    if let model {
                        Divider()
                        OpensEditor(model: model, activity: item)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .card(open ? st.color : nil, radius: 9)
    }

    private var nightSection: some View {
        group("Night", "Nothing is asked and no timers run; the night block stays on so you go to sleep.") {
            Toggle("Night mode", isOn: $settings.value.nightEnabled).toggleStyle(.switch).controlSize(.small)
            if settings.value.nightEnabled {
                row("From") { clockStepper($settings.value.nightFrom) }
                row("To") { clockStepper($settings.value.nightTo) }
                row("Block") { textField($settings.value.nightBlock) }
                Text("The night block is also what \"Other\" sessions lock.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                BlockEditor(block: settings.value.nightBlock)
                    .padding(10).card(radius: 9)
            }
        }
    }

    private var freeTimeSection: some View {
        group("Free time", "Nothing blocked: movies, YouTube, anything. Only when you take it on purpose; idle time doesn't count.") {
            row("Per day") { minuteStepper($settings.value.dailyFreeMinutes, 0...240, step: 5) }
            row("One stretch at most") { minuteStepper($settings.value.maxRestMinutes, 5...120, step: 5) }
        }
    }

    private var durationSection: some View {
        group("Session length", nil) {
            row("Options (min)") {
                TextField("15, 20, 30, 45, 60", text: $optionsText)
                    .textFieldStyle(.roundedBorder).frame(width: 160)
                    .onSubmit(saveOptions)
                    .onChange(of: optionsText) { _ in saveOptions() }
            }
            row("Default") { minuteStepper($settings.value.defaultMinutes, 5...240, step: 5) }
            row("Auto-start if unanswered for") {
                HStack(spacing: 6) {
                    Text(settings.value.autoStartAfterMinutes == 0 ? "never" : "\(settings.value.autoStartAfterMinutes) min").monospacedDigit()
                    Stepper("", value: $settings.value.autoStartAfterMinutes, in: 0...60, step: 5).labelsHidden()
                }
            }
            row("Auto-started session") { minuteStepper($settings.value.autoStartMinutes, 15...120, step: 5) }
            row("Minimum") { minuteStepper($settings.value.minMinutes, 5...120, step: 5) }
            row("Pomodoro work") { minuteStepper($settings.value.pomodoroWork, 5...90, step: 5) }
            row("Pomodoro break") { minuteStepper($settings.value.pomodoroBreak, 1...30, step: 1) }
            row("Pomodoro rounds") {
                HStack(spacing: 6) {
                    Text("\(settings.value.pomodoroRounds)").monospacedDigit()
                    Stepper("", value: $settings.value.pomodoroRounds, in: 1...8).labelsHidden()
                }
            }
        }
    }

    // MARK: day plan

    // How the daily limits add up: active work, Rest (with blocking), free time,
    // and what's left of the waking day (24 h minus night).
    private var dayPlan: some View {
        let s = settings.value
        let isRest = { (a: ActivitySetting) in a.name.lowercased() == "rest" }
        let active = s.activities.filter { !isRest($0) }.reduce(0) { $0 + $1.dailyMinutes }
        let rest = s.activities.filter(isRest).reduce(0) { $0 + $1.dailyMinutes }
        let free = s.dailyFreeMinutes
        let nightLen = s.nightEnabled ? (s.nightTo - s.nightFrom + 1440) % 1440 : 0
        let awake = 1440 - nightLen
        let planned = active + rest + free
        let unplanned = max(0, awake - planned)
        let noLimit = s.activities.filter { $0.dailyMinutes == 0 }.map(\.name)
        let parts: [(String, Int, Color)] = [("Active", active, .indigo), ("Rest", rest, .brown),
                                             ("Free time", free, .orange), ("Unplanned", unplanned, .gray)]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your day").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(minutesLabel(planned)) planned of \(minutesLabel(awake)) awake")
                    .font(.system(size: 11)).foregroundStyle(planned > awake ? .red : .secondary)
            }
            // One bar for the whole waking day.
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(parts.filter { $0.1 > 0 }, id: \.0) { _, mins, color in
                        RoundedRectangle(cornerRadius: 3).fill(color.gradient)
                            .frame(width: max(4, (g.size.width - 6) * CGFloat(mins) / CGFloat(max(awake, planned))))
                    }
                }
            }
            .frame(height: 10)
            HStack(spacing: 0) {
                ForEach(parts, id: \.0) { name, mins, color in
                    VStack(spacing: 2) {
                        Text(mins > 0 ? minutesLabel(mins) : "–")
                            .font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(color)
                        Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if !noLimit.isEmpty {
                Text("No limit (not counted): \(noLimit.joined(separator: ", "))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if planned > awake {
                Text("That's more than your waking day.").font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(12)
        .card(radius: 12)
    }

    // MARK: building blocks

    private func group<Content: View>(_ title: String, _ note: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            content()
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            content().font(.system(size: 13))
        }
    }

    private func minuteStepper(_ value: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 6) {
            Text(minutesLabel(value.wrappedValue)).monospacedDigit()
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }

    // Half-hour steps, wrapping around midnight.
    private func clockStepper(_ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(clockLabel(value.wrappedValue)).monospacedDigit()
            Stepper("", onIncrement: { value.wrappedValue = (value.wrappedValue + 30) % 1440 },
                        onDecrement: { value.wrappedValue = (value.wrappedValue + 1410) % 1440 }).labelsHidden()
        }
    }

    // Color swatches and an icon menu; the first swatch goes back to the guess from the name.
    private func lookPicker(_ a: Binding<ActivitySetting>, _ st: ActivityStyle) -> some View {
        HStack(spacing: 6) {
            ForEach(ActivityStyle.colors, id: \.name) { name, color in
                Button { a.wrappedValue.color = name } label: {
                    Circle().fill(color).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white, lineWidth: a.wrappedValue.color == name ? 2 : 0))
                        .shadow(color: a.wrappedValue.color == name ? color : .clear, radius: 2)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Menu {
                Button("From the name") { a.wrappedValue.icon = nil; a.wrappedValue.color = nil }
                Divider()
                ForEach(ActivityStyle.icons, id: \.self) { icon in
                    Button { a.wrappedValue.icon = icon } label: { Label(icon, systemImage: icon) }
                }
            } label: {
                Image(systemName: st.icon).foregroundStyle(st.color)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private func textField(_ value: Binding<String>) -> some View {
        TextField("", text: value).textFieldStyle(.roundedBorder).frame(width: 160)
    }

    private func addActivity() {
        let n = newActivity.trimmingCharacters(in: .whitespaces)
        newActivity = ""
        guard !n.isEmpty, !settings.value.activities.contains(where: { $0.name.lowercased() == n.lowercased() }) else { return }
        settings.value.activities.append(ActivitySetting(name: n))
    }

    private func saveOptions() {
        let list = optionsText.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Int($0) }.filter { $0 > 0 }
        if !list.isEmpty { settings.value.durationOptions = Array(Set(list)).sorted() }
    }
}
