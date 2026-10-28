import SwiftUI

// MARK: - Settings window

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @StateObject private var perms = Permissions()
    var model: Model? = nil                      // for "what it opens"
    let page: MainTab
    @State var expanded: Set<UUID> = []                 // rows opened with ⌄
    @State private var limitsByDay: Set<UUID> = []      // "different limit on some days" opened
    @State private var askNight = false                  // warning before night is switched on
    @State private var askFullScreen = false             // warning before "What's next?" goes full screen
    @State private var askDelete: ActivitySetting?       // "Delete activity?" waiting for an answer
    @State private var askLock: LockSettings?            // warning before the settings lock gets on or stronger
    @State private var newActivity = ""
    @State private var optionsText = Settings.shared.value.durationOptions.map(String.init).joined(separator: ", ")

    // The window shows this view itself, not one of its pages as a property:
    // only then does SwiftUI keep its @State (open rows, text being typed).
    var body: some View {
        switch page {
        case .activities: activitiesPage
        case .rules: rulesPage
        case .setup, .stats: EmptyView()
        }
    }

    // Pages of the main window's sidebar.
    private var activitiesPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(title: "Activities", subtitle: "Each one blocks what you list under Blocks while it runs.")
            lockBanner
            dayPlan               // the day first, the list that shapes it below
            activitiesSection
        }
        // On the page, not on the list: a modifier on ForEach is applied to every row.
        .alert("Delete \(askDelete?.name ?? "")?", isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }),
               presenting: askDelete) { a in
            Button("Delete", role: .destructive) {
                settings.value.activities.removeAll { $0.id == a.id }
                log("ui    deleted activity \(a.name)")
            }
            Button("Cancel", role: .cancel) {}
        } message: { a in
            Text("Are you sure? \(a.name) leaves your list and today's plan. Past sessions stay in Stats, and its block stays in blocks.json.")
        }
    }

    private var rulesPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: "Rules", subtitle: "Night, free time, session length, when settings may change, and permissions.")
            lockBanner
            pickerSection
            nightSection
            freeTimeSection
            durationSection
            lockSection
            group("Shortcuts", "Work from any app.") {
                ForEach(shortcuts, id: \.label) { k in
                    row(k.name) { Text(k.label).foregroundStyle(.secondary) }
                }
            }
            group("Permissions", "What macOS lets Tartip do. Rechecked when you come back from System Settings.") {
                PermissionsList(perms: perms, blocksSites: NativeBlocker.shared.rules.values.contains { !$0.web.isEmpty })
            }
            Text("Saved automatically to ~/modes/settings.json")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    // MARK: sections

    private var activitiesSection: some View {
        group("Your list", "Set a daily limit with the stepper; Edit for days, hours, what it blocks and opens.") {
            ForEach($settings.value.activities) { $a in
                activityRow($a)
            }
            HStack(spacing: 6) {
                TextField("New activity", text: $newActivity)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .card(radius: 9)
                    .onSubmit(addActivity)
                Button("Add", action: addActivity)
                    .disabled(newActivity.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func toggle(_ item: ActivitySetting) {
        if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
        log("ui    \(item.name) \(expanded.contains(item.id) ? "opened" : "closed")")
    }

    private func activityRow(_ a: Binding<ActivitySetting>) -> some View {
        let item = a.wrappedValue
        let st = ActivityStyle.of(item)
        let open = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: st.icon).foregroundStyle(st.color).frame(width: 18)
                TextField("Name", text: a.name).textFieldStyle(.plain).font(.system(size: 13))
                if !item.days.isEmpty {
                    Text(daysLabel(item.days)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if let from = item.fromMinute, let to = item.toMinute {
                    Text("\(clockLabel(from))–\(clockLabel(to))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if !item.dayMinutes.isEmpty {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 11)).foregroundStyle(.secondary)
                        .help("Different on " + weekOrder.compactMap { d in
                            item.dayMinutes[d].map { "\(weekdayShort[d] ?? ""): \(limitLabel($0))" } }.joined(separator: ", "))
                }
                Text(limitLabel(item.dailyMinutes))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(item.dailyMinutes == 0 ? .secondary : .primary)
                    .frame(width: 60, alignment: .trailing)
                Stepper("", value: a.dailyMinutes, in: 0...720, step: 15).labelsHidden().controlSize(.small)
                    .help(item.dayMinutes.isEmpty ? "Daily limit" : "Usual daily limit; some days have their own (⌄)")
                // A labelled button: a bare chevron was hard to see, hit and understand.
                Button { toggle(item) } label: {
                    Label(open ? "Done" : "Edit", systemImage: open ? "chevron.up" : "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .pill(selected: open)
                }
                .buttonStyle(.plain)
                .help("Days, limits, hours, what it blocks, what it opens, look")
            }
            // The rest of the row (not the name or the stepper) opens and closes it too.
            .contentShape(Rectangle())
            .onTapGesture { toggle(item) }
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Days")
                    dayPicker(a)
                    dayLimits(a)
                    Divider()
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
                    BlockEditor(block: item.block.isEmpty ? item.name : item.block)
                    Divider()
                    SectionLabel(text: "Look")
                    lookPicker(a, st)
                    if let model {
                        Divider()
                        OpensEditor(model: model, activity: item)
                    }
                    // Deleting lives here, away from Edit, and asks first.
                    Divider()
                    Button(role: .destructive) { askDelete = item } label: {
                        Label("Delete \(item.name.isEmpty ? "activity" : item.name)", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.red)
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .card(open ? st.color : nil, radius: 9)
    }

    private var pickerSection: some View {
        group("What's next?", "The window that asks what you'll do whenever nothing is running.") {
            Toggle("Full screen", isOn: Binding(get: { settings.value.pickerFullScreen },
                                                set: { on in if on { askFullScreen = true } else { settings.value.pickerFullScreen = false } }))
                .toggleStyle(.switch).controlSize(.small)
                .alert("Show \"What's next?\" full screen?", isPresented: $askFullScreen) {
                    Button("Full screen") { settings.value.pickerFullScreen = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(Warnings.fullScreenPicker)
                }
            Text(settings.value.pickerFullScreen
                 ? "Covers the whole screen and can't be moved; other screens go dark."
                 : "A window in the middle of the screen that can be dragged aside but not closed.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Toggle("Review full screen", isOn: $settings.value.reviewFullScreen)
                .toggleStyle(.switch).controlSize(.small)
            Text("\"Session done\" covers the whole screen too, until you say what you did. One click: the plan is already checked.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var nightSection: some View {
        group("Night", "Nothing is asked and no timers run; the night block stays on so you go to sleep.") {
            Toggle("Night mode", isOn: Binding(get: { settings.value.nightEnabled },
                                               set: { on in if on { askNight = true } else { settings.value.nightEnabled = false } }))
                .toggleStyle(.switch).controlSize(.small)
                .alert("Turn night on?", isPresented: $askNight) {
                    Button("Turn on") { settings.value.nightEnabled = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(Warnings.night({ var v = settings.value; v.nightEnabled = true; return v }()))
                }
            if settings.value.nightEnabled {
                row("From") { clockStepper($settings.value.nightFrom) }
                row("To") { clockStepper($settings.value.nightTo) }
                BlockEditor(block: settings.value.nightBlock)
                    .padding(10).card(radius: 9)
            }
        }
    }

    private var freeTimeSection: some View {
        group("Free time", "Nothing blocked: movies, YouTube, anything. Only when you take it on purpose; idle time doesn't count.") {
            row("Per day") { minuteStepper($settings.value.dailyFreeMinutes, 0...240, step: 5) }
            row("Longest break at once") { minuteStepper($settings.value.maxRestMinutes, 5...120, step: 5) }
            Text("Free time is taken in pieces; this caps one piece. It never goes past what's left for the day.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
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

    // MARK: settings lock

    // Where the lock stands, and why the last change was undone. Re-checked every 30 s,
    // since the lock starts and ends with the clock, not with an edit.
    private var lockBanner: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 6) {
                if let until = settings.lockedUntil {
                    Label("Locked until \(Fmt.weekdayClock.string(from: until)). You can make things stricter, not looser, and anything you add now stays until then.",
                          systemImage: "lock.fill")
                        .foregroundStyle(Theme.text)
                } else if let at = settings.locksAt {
                    Label("Settings lock at \(Fmt.clock.string(from: at)): finish your changes before then.", systemImage: "lock.open.fill")
                        .foregroundStyle(Theme.text)
                }
                if let why = settings.refused {
                    Label(why, systemImage: "hand.raised.fill").foregroundStyle(.orange)
                }
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Switching the lock on, or making it last longer, asks first; anything else just applies
    // (and a weaker lock is refused while locked).
    private func setLock(_ change: (inout LockSettings) -> Void) {
        var l = settings.value.lock
        change(&l)
        guard l != settings.value.lock else { return }
        let stronger = l.mode != settings.value.lock.mode || l.hours > settings.value.lock.hours
        if stronger { askLock = l } else { settings.value.lock = l }
    }

    private var lockSection: some View {
        let lock = $settings.value.lock
        return group("Changing settings",
                     "So a plan made calmly can't be undone in a weak moment. While locked, anything that makes things stricter still works.") {
            HStack(spacing: 6) {
                choicePill("Any time", lock.wrappedValue.mode == .off) { lock.wrappedValue.mode = .off }
                choicePill("Lock after a change", lock.wrappedValue.mode == .afterChange) { setLock { $0.mode = .afterChange } }
                choicePill("Only at set hours", lock.wrappedValue.mode == .hours) { setLock { $0.mode = .hours } }
            }
            .alert("Lock your settings?", isPresented: Binding(get: { askLock != nil }, set: { if !$0 { askLock = nil } }),
                   presenting: askLock) { l in
                Button("Lock") { settings.value.lock = l }
                Button("Cancel", role: .cancel) {}
            } message: { l in
                Text(Warnings.lock(l))
            }
            switch lock.wrappedValue.mode {
            case .off:
                EmptyView()
            case .afterChange:
                HStack(spacing: 6) {
                    Text("Locked for").font(.system(size: 13))
                    ForEach([2, 6, 12, 24, 48, 168], id: \.self) { h in
                        choicePill(h < 24 ? "\(h)h" : h == 24 ? "1 day" : h == 168 ? "1 week" : "\(h / 24) days",
                                   lock.wrappedValue.hours == h) { setLock { $0.hours = h } }
                    }
                }
                Text("Starts 10 minutes after your first change, so you can finish what you're doing.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            case .hours:
                row("Settings can be loosened from") { clockStepper(lock.from) }
                row("Until") { clockStepper(lock.to) }
                Text("Outside these hours you can only make things stricter.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: day plan

    // How one weekday's limits add up: active work, Rest (with blocking), free time,
    // and what's left of the waking day (24 h minus night). Only what's planned that day counts.
    // Below, today as two calendar columns: the plan, and what actually happened.
    private var dayPlan: some View {
        let s = settings.value
        let weekday = Calendar.current.component(.weekday, from: Date())
        let day = s.activities.filter { $0.isPlanned(onWeekday: weekday) }
        let limit = { (a: ActivitySetting) in a.limit(onWeekday: weekday) }
        let isRest = { (a: ActivitySetting) in a.name.lowercased() == "rest" }
        let active = day.filter { !isRest($0) }.reduce(0) { $0 + limit($1) }
        let rest = day.filter(isRest).reduce(0) { $0 + limit($1) }
        let free = s.dailyFreeMinutes
        let nightLen = s.nightEnabled ? (s.nightTo - s.nightFrom + 1440) % 1440 : 0
        let awake = 1440 - nightLen
        let planned = active + rest + free
        let unplanned = max(0, awake - planned)
        let noLimit = day.filter { limit($0) == 0 }.map(\.name)
        let parts: [(String, Int, Color)] = [("Active", active, .indigo), ("Rest", rest, .brown),
                                             ("Free time", free, .orange), ("Unplanned", unplanned, .gray)]

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.system(size: 13, weight: .semibold))
                Text(Fmt.dayTitle.string(from: Date())).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text("\(minutesLabel(planned)) planned of \(minutesLabel(awake)) awake")
                    .font(.system(size: 11)).foregroundStyle(planned > awake ? .red : .secondary)
            }
            if day.isEmpty && !s.activities.isEmpty {
                Text("Nothing planned: a day off, \"What's next?\" won't ask.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
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
            Divider().opacity(0.5)
            if let model {
                DayTimeline(day: model.today)
                Text("Not a schedule: within a period you pick any of these. Red: nothing can start then.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

    // Mon…Sun toggles. No days set means every day, shown as all seven on; switching
    // one off plans it for the rest. At least one day stays on.
    private func dayPicker(_ a: Binding<ActivitySetting>) -> some View {
        let days = a.days
        let on = days.wrappedValue.isEmpty ? Set(weekOrder) : Set(days.wrappedValue)
        return HStack(spacing: 4) {
            ForEach(weekOrder, id: \.self) { d in
                Button {
                    var next = on
                    if next.contains(d) { if next.count > 1 { next.remove(d) } } else { next.insert(d) }
                    days.wrappedValue = next.count == 7 ? [] : weekOrder.filter(next.contains)
                    a.wrappedValue.dayMinutes = a.wrappedValue.dayMinutes.filter { next.contains($0.key) }
                } label: {
                    Text(weekdayShort[d] ?? "").font(.system(size: 11, weight: on.contains(d) ? .semibold : .regular))
                        .frame(width: 34).padding(.vertical, 4)
                        .pill(selected: on.contains(d))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(daysLabel(days.wrappedValue)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // Per weekday: the usual limit, or its own (0 = no limit). Only planned days are listed:
    // "off" is the day toggle above, never a limit.
    private func dayLimits(_ a: Binding<ActivitySetting>) -> some View {
        let item = a.wrappedValue
        let open = !item.dayMinutes.isEmpty || limitsByDay.contains(item.id)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle("Different limit on some days", isOn: Binding(
                get: { open },
                set: { on in
                    if on { limitsByDay.insert(item.id) } else { limitsByDay.remove(item.id); a.wrappedValue.dayMinutes = [:] }
                }))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
            if open {
                ForEach(weekOrder.filter(item.isPlanned(onWeekday:)), id: \.self) { d in
                    let own = item.dayMinutes[d]
                    HStack(spacing: 6) {
                        Text(weekdayShort[d] ?? "").font(.system(size: 12, weight: .medium)).frame(width: 34, alignment: .leading)
                        choicePill("Usual · \(limitLabel(item.dailyMinutes))", own == nil) { a.wrappedValue.dayMinutes[d] = nil }
                        choicePill("Own", own != nil) {
                            if own == nil { a.wrappedValue.dayMinutes[d] = item.dailyMinutes }
                        }
                        if let own {
                            Text(limitLabel(own)).font(.system(size: 12)).monospacedDigit().frame(width: 60, alignment: .trailing)
                            Stepper("", value: Binding(get: { own }, set: { a.wrappedValue.dayMinutes[d] = $0 }),
                                    in: 0...720, step: 15).labelsHidden().controlSize(.small)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func choicePill(_ title: String, _ selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .pill(selected: selected)
        }
        .buttonStyle(.plain)
    }

    // Color swatches and an icon grid; "From the name" goes back to the guess.
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
            if a.wrappedValue.icon != nil || a.wrappedValue.color != nil {
                Button("From the name") { a.wrappedValue.icon = nil; a.wrappedValue.color = nil }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            IconPicker(icon: st.icon, color: st.color) { a.wrappedValue.icon = $0 }
        }
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
