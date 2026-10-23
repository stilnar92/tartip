import SwiftUI
import AppKit
import ApplicationServices

// MARK: - UI

struct BlockStyle {
    let icon: String
    let color: Color

    static func of(_ name: String) -> BlockStyle {
        let n = name.lowercased()
        if n.contains("interview") { return BlockStyle(icon: "person.2.wave.2.fill", color: .indigo) }
        if n.contains("focus") { return BlockStyle(icon: "scope", color: .indigo) }
        if n.contains("think") { return BlockStyle(icon: "brain.head.profile", color: .orange) }
        if n.contains("strict") { return BlockStyle(icon: "lock.shield.fill", color: .red) }
        if n.contains("educ") || n.contains("english") || n.contains("study") { return BlockStyle(icon: "graduationcap.fill", color: .teal) }
        if n.contains("work") || n.contains("code") { return BlockStyle(icon: "laptopcomputer", color: .blue) }
        let palette: [Color] = [.orange, .pink, .purple, .green, .mint, .cyan]
        let i = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count
        return BlockStyle(icon: "target", color: palette[i])
    }
}

extension View {
    @ViewBuilder func card(_ tint: Color? = nil, radius: CGFloat = 14) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint.map { AnyShapeStyle($0.opacity(0.14)) } ?? AnyShapeStyle(.quaternary.opacity(0.5)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tint?.opacity(0.55) ?? Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct ContentView: View {
    @ObservedObject var m: Model
    @State private var newBlock = ""
    @State private var adding = false
    @State private var custom = false
    @State private var hovered: String?
    @State private var newLink = ""

    private let presets = durationOptions

    @State private var editing = false
    @State private var customText = ""
    @FocusState private var customFocused: Bool
    @State private var showLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let r = m.restEnd {
                resting(r)
            } else if let s = m.session, let cur = s.current(at: m.now) {
                running(s, cur)
            } else if editing {
                editor
            } else if isNight(m.now) {
                nightView
            } else {
                setup
            }
            if !m.message.isEmpty {
                Label(m.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(16)
        .frame(width: 340)
        .animation(.snappy(duration: 0.2), value: m.session == nil)
        .animation(.snappy(duration: 0.2), value: editing)
        .animation(.snappy(duration: 0.2), value: showLink)
        .animation(.snappy(duration: 0.2), value: custom)
    }

    // MARK: header / footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isNight(m.now) ? "moon.stars.fill" : "scope")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Focus").font(.system(size: 16, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    Circle().fill(guardColor).frame(width: 6, height: 6)
                    Text(guardText).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var guardColor: Color {
        isNight(m.now) ? .purple : (m.session != nil ? .green : (m.restEnd != nil ? .orange : .secondary))
    }

    private var guardText: String {
        if isNight(m.now) { return "Night until \(clockLabel(S.nightTo))" }
        if m.session != nil { return "In a session" }
        if m.restEnd != nil { return "Free time" }
        if m.availableActivities.isEmpty && !m.canRest { return "Day done 🎉" }
        return "Pick what's next"
    }

    // Footer: four equal tools, icon above a caption, so nothing wraps.
    private var footer: some View {
        HStack(spacing: 4) {
            if m.session == nil && m.restEnd == nil {
                tool(editing ? "checkmark" : "slider.horizontal.3", editing ? "Done" : "Edit") { editing.toggle() }
            }
            tool("chart.bar.fill", "Stats") {
                // Close the menu bar panel first so it doesn't cover the window.
                NSApp.keyWindow?.close()
                m.openStats()
            }
            tool("gearshape.fill", "Settings") {
                NSApp.keyWindow?.close()
                m.openSettings()
            }
            tool("arrow.up.forward.app", "Cold Turkey") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Cold Turkey Blocker.app"))
            }
        }
    }

    private func tool(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary.opacity(0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            todayCard

            // Pomodoro switch; otherwise the length is picked in the "What will you work on?" window.
            HStack(spacing: 10) {
                Text("🍅").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pomodoro").font(.system(size: 13, weight: .medium))
                    Text(m.pomodoro ? "\(S.pomodoroWork)/\(S.pomodoroBreak) min × \(S.pomodoroRounds)" : "Off · length picked at start")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $m.pomodoro).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .card(radius: 12)

            if showLink {
                HStack(spacing: 6) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Paste a site to open with this session…", text: $m.oneTimeLink).textFieldStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .card(radius: 10)
            }

            startButton

            HStack(spacing: 8) {
                secondary("safari", m.oneTimeLink.isEmpty ? "Open a site" : "Site added",
                          active: showLink || !m.oneTimeLink.isEmpty) { showLink.toggle() }
                restMenu
            }
        }
    }

    // Today: totals plus progress for every activity that has a daily limit.
    private var todayCard: some View {
        let today = Calendar.current.startOfDay(for: m.now)
        let used = m.secondsByActivity(since: today)
        let goals = S.activities.filter { $0.dailyMinutes > 0 }
        let sessions = m.recordsSince(today).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                todayStat(formatDuration(m.stats.focus), "Focused", .indigo)
                todayStat("\(sessions)", "Sessions", .primary)
                todayStat("\(m.freeLeft / 60)m", "Free left", m.freeLeft > 0 ? .green : .red)
            }
            if goals.isEmpty {
                Text("Set daily goals for activities in Settings.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(goals) { g in
                        let secs = used[g.name] ?? 0
                        let st = ActivityStyle.of(g.name)
                        let done = secs >= g.dailyMinutes * 60
                        HStack(spacing: 8) {
                            Image(systemName: done ? "checkmark.circle.fill" : st.icon)
                                .font(.system(size: 11)).foregroundStyle(done ? .green : st.color).frame(width: 16)
                            Text(g.name).font(.system(size: 12)).lineLimit(1).frame(width: 86, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(st.color.opacity(0.15))
                                    Capsule().fill(done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(st.color.gradient))
                                        .frame(width: geo.size.width * min(1, CGFloat(secs) / CGFloat(g.dailyMinutes * 60)))
                                }
                            }
                            .frame(height: 6)
                            Text("\(formatDuration(secs)) / \(limitLabel(g.dailyMinutes))")
                                .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                                .foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(12)
        .card(radius: 14)
    }

    private func todayStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func secondary(_ icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.6))))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var restMenu: some View {
        Menu {
            Section(m.restTaken ? "Free time used · do a session first" : "Free time · nothing blocked · \(m.freeLeft / 60) min left today") {
                ForEach(restOptions, id: \.self) { n in
                    Button("☕ \(n) min") { m.startRest(minutes: n) }
                        .disabled(!m.canRest)
                }
            }
        } label: {
            Label(m.canRest ? "Free time · \(m.freeLeft / 60)m" : "Free time used", systemImage: "popcorn.fill")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.6)))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Free time: nothing blocked (\(m.freeLeft / 60) min left today)")
    }

    // MARK: editor (add/remove modes, what each opens)

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What each activity opens when it starts. Add or rename activities in Settings; each needs a Cold Turkey block with the same name.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(m.activities, id: \.self) { b in
                let st = ActivityStyle.of(b)
                HStack(spacing: 8) {
                    Image(systemName: st.icon).foregroundStyle(st.color).frame(width: 18)
                    Text(b)
                        .font(.system(size: 12, weight: m.selected == b ? .semibold : .regular))
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .card(m.selected == b ? st.color : nil, radius: 8)
                .contentShape(Rectangle())
                .onTapGesture { m.selected = b }
            }
            if !m.selected.isEmpty {
                Divider()
                opens(m.selected)
            }
        }
    }

    private func opens(_ block: String) -> some View {
        let c = m.config(block)
        let tint = BlockStyle.of(block).color
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Opens")
            do {
                HStack(spacing: 8) {
                    ForEach(c.apps, id: \.self) { path in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable().frame(width: 30, height: 30)
                            .help(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                            .contextMenu {
                                Button("Remove", role: .destructive) { m.updateConfig(block) { $0.apps.removeAll { $0 == path } } }
                            }
                    }
                    Button { m.chooseApps(for: block) } label: {
                        Image(systemName: "plus.app")
                            .font(.system(size: 16))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Add apps")
                }
            }
            ForEach(c.urls, id: \.self) { u in
                HStack(spacing: 8) {
                    Image(systemName: "globe").foregroundStyle(tint)
                    Text(u.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { m.updateConfig(block) { $0.urls.removeAll { $0 == u } } } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("Paste a link and press Enter", text: $newLink)
                    .textFieldStyle(.plain)
                    .onSubmit { addLink(block) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .card(radius: 9)
            Toggle(isOn: Binding(get: { m.config(block).maximize },
                                 set: { v in m.updateConfig(block) { $0.maximize = v } })) {
                Text("Stretch windows to fill the screen").font(.system(size: 12))
            }
            .toggleStyle(.switch).controlSize(.mini).tint(tint)
        }
    }

    private func addLink(_ block: String) {
        let l = newLink.trimmingCharacters(in: .whitespaces)
        newLink = ""
        guard !l.isEmpty else { return }
        m.updateConfig(block) { if !$0.urls.contains(l) { $0.urls.append(l) } }
    }

    private func chip(_ title: String, selected: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        let tint = BlockStyle.of(m.selected).color
        return Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var startLabel: String {
        m.pomodoro ? "Start · 🍅 2h" : "Start"
    }

    private var oneTimeField: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").foregroundStyle(.secondary)
            TextField("This time also open… (optional link)", text: $m.oneTimeLink)
                .textFieldStyle(.plain)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .card(radius: 9)
    }

    private var startButton: some View {
        let color = BlockStyle.of(m.selected).color
        let disabled = m.selected.isEmpty || (!m.pomodoro && m.minutes < 1)
        return Button(action: m.start) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text(startLabel)
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: color.opacity(0.35), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: night

    private var nightView: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom))
            Text("Night").font(.system(size: 20, weight: .bold, design: .rounded))
            Text("\(S.nightBlock) is on until \(clockLabel(S.nightTo)).\nNothing to do now but sleep.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: rest

    private func resting(_ until: Date) -> some View {
        VStack(spacing: 14) {
            Text("🍿").font(.system(size: 44))
            Text(m.remaining(until))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text("Free time · nothing blocked · \(m.freeLeft / 60) min left today")
                .font(.caption).foregroundStyle(.secondary)
            Button { m.endRest() } label: {
                Text("Back to work")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .card(radius: 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: running

    private func running(_ s: Session, _ cur: (index: Int, end: Date)) -> some View {
        let p = s.phases[cur.index]
        let st = BlockStyle.of(s.block)
        let ringColor: Color = p.isBreak ? .green : st.color
        let total = Double(p.minutes * 60)
        let left = max(0, cur.end.timeIntervalSince(m.now))
        let progress = total > 0 ? 1 - left / total : 1
        let f = DateFormatter(); f.dateFormat = "HH:mm"

        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: st.icon).foregroundStyle(st.color)
                Text(s.block.replacingOccurrences(of: "_", with: " ")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(p.isBreak ? "BREAK" : "FOCUS")
                    .font(.system(size: 10, weight: .bold)).tracking(0.8)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(ringColor.opacity(0.18)))
                    .foregroundStyle(ringColor)
            }

            ZStack {
                Circle().stroke(ringColor.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [ringColor.opacity(0.6), ringColor], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 2) {
                    Text(m.remaining(cur.end))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(p.isBreak ? "Stand up · drink water" : "Stay on it")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.vertical, 4)

            if s.workRounds > 1 {
                HStack(spacing: 6) {
                    ForEach(1...s.workRounds, id: \.self) { r in
                        let done = r < s.round(of: cur.index) || (r == s.round(of: cur.index) && p.isBreak)
                        let now = r == s.round(of: cur.index) && !p.isBreak
                        Capsule()
                            .fill(done ? st.color : (now ? st.color.opacity(0.5) : Color.secondary.opacity(0.2)))
                            .frame(width: now ? 22 : 10, height: 6)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text("Blocked until \(f.string(from: s.end))")
            }
            .font(.caption).foregroundStyle(.secondary)

            Button { m.stop() } label: {
                Text("Stop timer")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .card(radius: 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func add() {
        m.addBlock(newBlock)
        newBlock = ""
        adding = false
    }
}
