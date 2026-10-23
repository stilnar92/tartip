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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(14)
        .frame(width: 300)
        .animation(.snappy(duration: 0.2), value: m.session == nil)
        .animation(.snappy(duration: 0.2), value: editing)
        .animation(.snappy(duration: 0.2), value: showLink)
        .animation(.snappy(duration: 0.2), value: custom)
    }

    // MARK: header / footer

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)))
            Text("Focus").font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            // Today at a glance
            HStack(spacing: 8) {
                stat("scope", formatDuration(m.stats.focus), .indigo)
                stat("cup.and.saucer.fill", "\(m.freeLeft / 60)m", m.freeLeft > 0 ? .green : .red)
            }
            .help("Today: focus · thinking · free time left")
        }
    }

    private func stat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(color)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if m.session == nil && m.restEnd == nil {
                Button { editing.toggle() } label: {
                    Label(editing ? "Done" : "Edit modes", systemImage: editing ? "checkmark" : "slider.horizontal.3")
                }
            }
            Button {
                // Close the menu bar panel first so it doesn't cover the stats window.
                NSApp.keyWindow?.close()
                m.openStats()
            } label: { Label("Stats", systemImage: "chart.bar.fill") }
            Button {
                NSApp.keyWindow?.close()
                m.openSettings()
            } label: { Image(systemName: "gearshape.fill") }
            .help("Settings")
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Cold Turkey Blocker.app"))
            } label: {
                Label("Cold Turkey", systemImage: "arrow.up.forward.app")
            }
            Spacer()
            Circle().fill(enforcementActive(m.now) ? Color.green : Color.secondary).frame(width: 6, height: 6)
                .help(enforcementActive(m.now) ? "Guard on · weekdays 10–22" : "Guard off")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    // MARK: setup (compact)

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            // How long is chosen in the "What will you work on?" window (default 30 min).
            HStack(spacing: 6) {
                Text(m.pomodoro ? "Pomodoro 25/5 × 4" : "Duration: choose when starting")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Toggle(isOn: $m.pomodoro) { Text("🍅").font(.system(size: 12)) }
                    .toggleStyle(.switch).controlSize(.mini)
                    .help("Pomodoro 25/5 × 4")
            }

            if showLink {
                HStack(spacing: 6) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Also open this time…", text: $m.oneTimeLink).textFieldStyle(.plain)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .card(radius: 9)
            }

            HStack(spacing: 6) {
                startButton
                iconButton("link", active: showLink || !m.oneTimeLink.isEmpty, help: "Open an extra link this time") {
                    showLink.toggle()
                }
                restMenu
            }
        }
    }

    private func modeTile(_ b: String) -> some View {
        let st = BlockStyle.of(b)
        let sel = m.selected == b
        return HStack(spacing: 6) {
            Image(systemName: st.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sel ? .white : st.color)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(sel ? AnyShapeStyle(st.color.gradient) : AnyShapeStyle(st.color.opacity(0.15))))
            Text(b.replacingOccurrences(of: "_Mode", with: "").replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 12, weight: sel ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(6)
        .card(sel ? st.color : nil, radius: 10)
        .contentShape(Rectangle())
        .onTapGesture { m.selected = b }
        .help(b)
    }

    private func iconButton(_ icon: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.6))))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var restMenu: some View {
        Menu {
            Section(m.restTaken ? "Rest used · start a mode first" : "Rest · nothing blocked · \(m.freeLeft / 60) min left today") {
                ForEach(restOptions, id: \.self) { n in
                    Button("☕ \(n) min") { m.startRest(minutes: n) }
                        .disabled(!m.canRest)
                }
            }
        } label: {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.6)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Rest (\(m.freeLeft / 60) min left today)")
    }

    // MARK: editor (add/remove modes, what each opens)

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What each activity opens on Desktop \(m.desktop). Add or rename activities in Settings; each needs a Cold Turkey block with the same name.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(m.activities + [m.focusBlock], id: \.self) { b in
                let st = ActivityStyle.of(b == m.focusBlock ? otherActivity : b)
                HStack(spacing: 8) {
                    Image(systemName: st.icon).foregroundStyle(st.color).frame(width: 18)
                    Text(b == m.focusBlock ? "Other → \(b)" : b)
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
            HStack {
                Image(systemName: "rectangle.on.rectangle").foregroundStyle(.secondary)
                Text(m.desktop == 0 ? "Open on the current desktop" : "Open on Desktop \(m.desktop)")
                    .font(.system(size: 12))
                Spacer()
                Stepper("", value: $m.desktop, in: 0...9).labelsHidden().controlSize(.mini)
            }
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
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
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
            Text("☕").font(.system(size: 44))
            Text(m.remaining(until))
                .font(.system(size: 42, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text("Rest · nothing blocked · \(m.freeLeft / 60) min left today")
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
