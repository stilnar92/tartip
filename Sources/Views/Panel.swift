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

// Craft-style section heading: small, bold, grey, sentence case.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.text2)
    }
}

struct ContentView: View {
    @ObservedObject var m: Model
    @State private var newBlock = ""
    @State private var adding = false
    @State private var custom = false
    @State private var hovered: String?

    private let presets = durationOptions

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
        .background(Theme.bg)
        .environment(\.colorScheme, .light)
        .animation(.snappy(duration: 0.2), value: m.session == nil)
        .animation(.snappy(duration: 0.2), value: showLink)
        .animation(.snappy(duration: 0.2), value: custom)
    }

    // MARK: header / footer

    // Craft-style title: big "Today", then "Thursday · 23 Oct" and a status tag.
    private var header: some View {
        let f = DateFormatter(); f.dateFormat = "EEEE · d MMM"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(isNight(m.now) ? "Night" : "Today")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Tag(text: statusText, color: statusColor, fill: statusColor.opacity(0.12))
            }
            Text(f.string(from: m.now)).font(.system(size: 14)).foregroundStyle(Theme.text2)
        }
    }

    private var statusColor: Color {
        isNight(m.now) ? .purple : (m.session != nil ? Theme.accent : (m.restEnd != nil ? .orange : Theme.text2))
    }

    private var statusText: String {
        if isNight(m.now) { return "until \(clockLabel(S.nightTo))" }
        if m.session != nil { return "In a session" }
        if m.restEnd != nil { return "Free time" }
        if m.availableActivities.isEmpty && !m.canRest { return "Day done 🎉" }
        if m.pickableActivities.isEmpty && !m.canRest { return "Nothing open" }
        return "Pick what's next"
    }

    // Footer: a floating white pill with icon buttons, like Craft's toolbar.
    private var footer: some View {
        HStack(spacing: 2) {
            tool("chart.bar", "Stats") {
                // Close the menu bar panel first so it doesn't cover the window.
                NSApp.keyWindow?.close()
                m.openStats()
            }
            tool("gearshape", "Settings") {
                NSApp.keyWindow?.close()
                m.openSettings()
            }
            tool("arrow.up.forward.app", "Cold Turkey") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Cold Turkey Blocker.app"))
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.card).shadow(color: .black.opacity(0.08), radius: 8, y: 2))
        .frame(maxWidth: .infinity)
    }

    private func tool(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            todayCard

            // Pomodoro switch; otherwise the length is picked in the "What's next?" window.
            HStack(spacing: 10) {
                Text("🍅").font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pomodoro").font(.system(size: 14)).foregroundStyle(Theme.text)
                    Text(m.pomodoro ? "\(S.pomodoroWork)/\(S.pomodoroBreak) min × \(S.pomodoroRounds)" : "Off · length picked at start")
                        .font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Toggle("", isOn: $m.pomodoro).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Theme.accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .card(radius: 12)

            if showLink {
                HStack(spacing: 6) {
                    Image(systemName: "link").foregroundStyle(Theme.text2)
                    TextField("Paste a site to open with this session…", text: $m.oneTimeLink).textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 9)
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

    // Today: three numbers as tags, then the daily goals as a Craft-style checklist.
    private var todayCard: some View {
        let today = Calendar.current.startOfDay(for: m.now)
        let used = m.secondsByActivity(since: today)
        let goals = S.activities.filter { $0.dailyMinutes > 0 }
        let sessions = m.recordsSince(today).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Tag(text: "⏱ \(formatDuration(m.stats.focus)) focused", color: Theme.accent, fill: Theme.accentTint)
                Tag(text: "\(sessions) sessions")
                Tag(text: "🍿 \(m.freeLeft / 60)m free",
                    color: m.freeLeft > 0 ? Theme.text2 : Theme.red, fill: m.freeLeft > 0 ? Theme.pill : Theme.redTint)
            }
            if goals.isEmpty {
                Text("Set daily goals for activities in Settings.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(goals.enumerated()), id: \.element.id) { i, g in
                        let secs = used[g.name] ?? 0
                        let done = secs >= g.dailyMinutes * 60
                        HStack(spacing: 10) {
                            // Craft's square checkbox: blue and checked once the goal is reached.
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(done ? Theme.accent : Color.clear)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(done ? Theme.accent : Theme.text2.opacity(0.5), lineWidth: 1.2)
                                if done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                            }
                            .frame(width: 16, height: 16)
                            Text(g.name).font(.system(size: 14)).foregroundStyle(done ? Theme.text2 : Theme.text)
                                .strikethrough(done, color: Theme.text2)
                                .lineLimit(1)
                            Spacer()
                            Tag(text: "\(formatDuration(secs)) / \(limitLabel(g.dailyMinutes))",
                                color: done ? Theme.accent : Theme.text2, fill: done ? Theme.accentTint : Theme.pill)
                        }
                        .padding(.vertical, 7)
                        if i < goals.count - 1 { Divider().opacity(0.5) }
                    }
                }
            }
        }
        .padding(12)
        .card(radius: 14)
    }

    private func secondary(_ icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .pill(selected: active)
        }
        .buttonStyle(.plain)
    }

    private var restMenu: some View {
        Menu {
            Section(m.restTaken ? "Free time used · do a session first" : "Free time · nothing blocked · \(m.freeLeft / 60) min left today") {
                ForEach(restOptions, id: \.self) { n in
                    Button("🍿 \(n) min") { m.startRest(minutes: n) }
                        .disabled(!m.canRest)
                }
            }
        } label: {
            Label(m.canRest ? "Free time · \(m.freeLeft / 60)m" : "Free time used", systemImage: "popcorn")
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .pill()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Free time: nothing blocked (\(m.freeLeft / 60) min left today)")
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
        let color = Theme.accent
        let disabled = !m.pomodoro && m.minutes < 1
        return Button(action: m.start) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text(startLabel)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Capsule().fill(color))
            .shadow(color: color.opacity(0.25), radius: 6, y: 2)
            .contentShape(Capsule())
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
            Text("Night").font(.system(size: 20, weight: .bold))
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
                .font(.system(size: 42, weight: .semibold))
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
                        .font(.system(size: 36, weight: .semibold))
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
