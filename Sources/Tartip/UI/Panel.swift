import SwiftUI

// MARK: - UI

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
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock
    let openMain: (MainTab) -> Void
    @State private var showLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.session == nil { header }
            if let end = model.freeTimeEnd {
                freeTimeCard(end)
            } else if let s = model.session, let cur = s.current(at: model.now) {
                sessionCard(s, cur)
            } else if Setup.isPending {
                setupCard
            } else if Settings.current.isNight(at: model.now) {
                nightCard
            } else {
                TodayList(model: model, clock: clock)
                siteRow
            }
            if !model.message.isEmpty {
                Label(model.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !Setup.isPending { toolbar }
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.bg)
        .environment(\.colorScheme, .light)
        .animation(.snappy(duration: 0.2), value: model.session == nil)
        .animation(.snappy(duration: 0.2), value: model.freeTimeEnd == nil)
        .animation(.snappy(duration: 0.2), value: showLink)
    }

    // MARK: header

    // "Today" + date, then the day in three tags.
    private var header: some View {
        let sessions = model.recordsSince(Calendar.current.startOfDay(for: model.now)).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Settings.current.isNight(at: model.now) ? "Night" : "Today")
                    .font(Theme.title).foregroundStyle(Theme.text)
                Text(Fmt.dayTitle.string(from: model.now)).font(.system(size: 13)).foregroundStyle(Theme.text2)
                Spacer()
            }
            HStack(spacing: 6) {
                Tag(text: "⏱ \(formatDuration(model.focusedToday))", color: Theme.accent, fill: Theme.accentTint)
                Tag(text: "\(sessions) sessions")
                Tag(text: "🍿 \(model.freeLeft / 60)m", color: model.freeLeft > 0 ? Theme.text2 : Theme.red,
                    fill: model.freeLeft > 0 ? Theme.pill : Theme.redTint)
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
                    TextField("Paste a site to open with the next session…", text: $model.oneTimeLink).textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .card(radius: 10)
            }
            Button { showLink.toggle() } label: {
                Label(model.oneTimeLink.isEmpty ? "Open a site with the next session" : "Site added for the next session",
                      systemImage: "safari")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.oneTimeLink.isEmpty ? Theme.text2 : Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // Floating white pill with icon buttons, like Craft's toolbar.
    private var toolbar: some View {
        HStack(spacing: 2) {
            tool("chart.bar", "Stats") { openMain(.stats) }
            tool("list.bullet", "Activities") { openMain(.activities) }
            tool("gearshape", "Rules") { openMain(.rules) }
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
        let left = max(0, cur.end.timeIntervalSince(model.now))
        let progress = total > 0 ? 1 - left / total : 1
        let f = Fmt.clock
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
                    Text(countdown(to: cur.end, from: model.now))
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

            Button { model.stop() } label: {
                Text("Stop session").font(.system(size: 12)).foregroundStyle(Theme.text2).underline()
            }
            .buttonStyle(.plain)
            .help("The block stays on until \(f.string(from: s.end))")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20).padding(.horizontal, 16)
        .card(radius: 18)
    }

    // Today's progress on this activity, counting this session live. Centered like the rest:
    // "25m left today", a bar, then "34m of 1h".
    private func dailyProgress(_ name: String, _ color: Color) -> some View {
        let limits = model.limits
        let used = limits.usedToday(name)
        let limit = limits.limitMinutes(name)
        let left = limits.secondsLeftToday(name) ?? 0
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
                    Text("Nothing blocked · \(model.freeLeft / 60)m left today").font(.system(size: 12)).foregroundStyle(Theme.text2)
                }
                Spacer()
            }
            Text(countdown(to: until, from: model.now))
                .font(.system(size: 52, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText(countsDown: true))
                .frame(maxWidth: .infinity)
            Button { model.endRest() } label: {
                Text("Back to work").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .pill(selected: true)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .card(radius: 16)
    }

    // MARK: first-run setup

    // Nothing can start before setup: the panel only leads to Get started.
    private var setupCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(Theme.accent)
            Text("Let's set you up").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
            Text("Pick your activities and what should be blocked. About two minutes.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            Button { openMain(.setup) } label: {
                Text("Get started").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .card(radius: 16)
    }

    // MARK: night

    private var nightCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 34))
                .foregroundStyle(.purple)
            Text("Time to sleep").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
            Text("Night mode is on until \(clockLabel(Settings.current.nightTo)). Nothing to do until morning.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .card(radius: 16)
    }
}
