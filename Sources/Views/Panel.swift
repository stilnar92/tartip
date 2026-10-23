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

// The menu bar panel: a "Today" page. Idle = the day's list (click a row to start);
// in a session = the session card; free time and night have their own cards.
struct ContentView: View {
    @ObservedObject var m: Model
    @State private var showLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if m.session == nil { header }
            if let r = m.restEnd {
                freeTimeCard(r)
            } else if let s = m.session, let cur = s.current(at: m.now) {
                sessionCard(s, cur)
            } else if isNight(m.now) {
                nightCard
            } else {
                TodayList(m: m)
                siteRow
            }
            if !m.message.isEmpty {
                Label(m.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            toolbar
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.bg)
        .environment(\.colorScheme, .light)
        .animation(.snappy(duration: 0.2), value: m.session == nil)
        .animation(.snappy(duration: 0.2), value: m.restEnd == nil)
        .animation(.snappy(duration: 0.2), value: showLink)
    }

    // MARK: header

    // "Today" + date, then the day in three tags.
    private var header: some View {
        let f = DateFormatter(); f.dateFormat = "EEEE · d MMM"
        let sessions = m.recordsSince(Calendar.current.startOfDay(for: m.now)).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(isNight(m.now) ? "Night" : "Today")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                Text(f.string(from: m.now)).font(.system(size: 13)).foregroundStyle(Theme.text2)
                Spacer()
            }
            HStack(spacing: 6) {
                Tag(text: "⏱ \(formatDuration(m.stats.focus))", color: Theme.accent, fill: Theme.accentTint)
                Tag(text: "\(sessions) sessions")
                Tag(text: "🍿 \(m.freeLeft / 60)m", color: m.freeLeft > 0 ? Theme.text2 : Theme.red,
                    fill: m.freeLeft > 0 ? Theme.pill : Theme.redTint)
            }
        }
    }

    // MARK: idle extras

    // A one-off site for the next start.
    private var siteRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showLink {
                HStack(spacing: 6) {
                    Image(systemName: "link").foregroundStyle(Theme.text2)
                    TextField("Paste a site to open with the next session…", text: $m.oneTimeLink).textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .card(radius: 10)
            }
            Button { showLink.toggle() } label: {
                Label(m.oneTimeLink.isEmpty ? "Open a site with the next session" : "Site added for the next session",
                      systemImage: "safari")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(m.oneTimeLink.isEmpty ? Theme.text2 : Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // Floating white pill with icon buttons, like Craft's toolbar.
    private var toolbar: some View {
        HStack(spacing: 2) {
            tool("chart.bar", "Stats") { hideMenuPanel(); m.openMain(.stats) }
            tool("list.bullet", "Activities") { hideMenuPanel(); m.openMain(.activities) }
            tool("gearshape", "Rules") { hideMenuPanel(); m.openMain(.rules) }
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
                .padding(.horizontal, 10).padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: session

    // During a session only what matters: what you're doing, the time left (huge),
    // when it ends, and today's progress on this activity. Stop is a quiet link.
    private func sessionCard(_ s: Session, _ cur: (index: Int, end: Date)) -> some View {
        let p = s.phases[cur.index]
        let name = s.planned ?? s.block.replacingOccurrences(of: "_", with: " ")
        let st = ActivityStyle.of(name)
        let total = Double(p.minutes * 60)
        let left = max(0, cur.end.timeIntervalSince(m.now))
        let progress = total > 0 ? 1 - left / total : 1
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let color = p.isBreak ? Color.green : st.color

        return VStack(spacing: 18) {
            // What
            HStack(spacing: 10) {
                Image(systemName: p.isBreak ? "cup.and.saucer.fill" : st.icon)
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(color)
                Text(p.isBreak ? "Break" : name)
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
                if s.workRounds > 1 {
                    Tag(text: "\(s.round(of: cur.index))/\(s.workRounds)", color: color, fill: color.opacity(0.12))
                }
            }

            // How long: ring + huge time, end time right under it
            ZStack {
                Circle().stroke(Theme.pill, lineWidth: 8)
                Circle().trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 2) {
                    Text(m.remaining(cur.end))
                        .font(.system(size: 56, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(countsDown: true))
                    Text(p.isBreak ? "stand up · back at \(f.string(from: cur.end))" : "until \(f.string(from: s.end))")
                        .font(.system(size: 13)).foregroundStyle(Theme.text2)
                }
            }
            .frame(width: 220, height: 220)

            if !p.isBreak { dailyProgress(name, color) }

            Button { m.stop() } label: {
                Text("Stop session").font(.system(size: 12)).foregroundStyle(Theme.text2).underline()
            }
            .buttonStyle(.plain)
            .help("The Cold Turkey block stays on until \(f.string(from: s.end))")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20).padding(.horizontal, 16)
        .card(radius: 18)
    }

    // Today's progress on this activity, counting this session live. Centered like the rest:
    // "25m left today", a bar, then "34m of 1h".
    private func dailyProgress(_ name: String, _ color: Color) -> some View {
        let used = m.secondsByActivity(since: Calendar.current.startOfDay(for: m.now))[name] ?? 0
        let limit = m.limitMinutes(name)
        let left = m.secondsLeftToday(name) ?? 0
        return VStack(spacing: 6) {
            Text(limit > 0 ? (left > 0 ? "\(formatDuration(left)) left today" : "Daily limit reached")
                           : "\(formatDuration(used)) today")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(limit > 0 && left == 0 ? Theme.red : Theme.text)
            if limit > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.pill)
                        Capsule().fill(color.opacity(0.85))
                            .frame(width: g.size.width * min(1, CGFloat(used) / CGFloat(limit * 60)))
                    }
                }
                .frame(width: 200, height: 6)
                Text("\(formatDuration(used)) of \(limitLabel(limit))").font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: free time

    private func freeTimeCard(_ until: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("🍿").font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Free time").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("Nothing blocked · \(m.freeLeft / 60)m left today").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
            }
            Text(m.remaining(until))
                .font(.system(size: 52, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(countsDown: true))
                .frame(maxWidth: .infinity)
            Button { m.endRest() } label: {
                Text("Back to work").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .pill(selected: true)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .card(radius: 16)
    }

    // MARK: night

    private var nightCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 34))
                .foregroundStyle(.purple)
            Text("Time to sleep").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
            Text("\(S.nightBlock) is on until \(clockLabel(S.nightTo)). Nothing to do until morning.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .card(radius: 16)
    }
}
