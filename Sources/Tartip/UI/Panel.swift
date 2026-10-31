import AppKit
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
            } else if let since = model.phase.awaySince {
                awayCard(since)
            } else if Settings.current.isNight(at: model.now) {
                nightCard
            } else {
                TodayList(model: model, clock: clock)
                if Settings.current.has(.workspace) { siteRow }
            }
            if !model.message.isEmpty {
                Label(model.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !Setup.isPending && model.session == nil { toolbar }
            if !Settings.current.has(.relaunch) {
                Button("Quit Tartip") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(model.session == nil ? Theme.bg : Theme.card)
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
                if !Setup.isPending && Settings.current.has(.tasks) {
                    Button {
                        openMain(.tasks)
                    } label: {
                        Label("Tasks", systemImage: "checklist")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.text2)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open today's task plan")
                }
            }
            HStack(spacing: 6) {
                Tag(text: "⏱ \(formatDuration(model.focusedToday))", color: Theme.accent, fill: Theme.accentTint)
                Tag(text: "\(sessions) sessions")
                if Settings.current.has(.guidance) && Settings.current.dailyFreeMinutes > 0 {
                    Tag(
                        text: "🍿 \(model.freeLeft / 60)m", color: model.freeLeft > 0 ? Theme.text2 : Theme.red,
                        fill: model.freeLeft > 0 ? Theme.pill : Theme.redTint)
                }

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
            Button {
                showLink.toggle()
            } label: {
                Label(
                    model.oneTimeLink.isEmpty ? "Open a site with the next session" : "Site added for the next session",
                    systemImage: "safari"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.oneTimeLink.isEmpty ? Theme.text2 : Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // Floating white pill with icon buttons, like Craft's toolbar.
    private var toolbar: some View {
        HStack(spacing: 2) {
            tool("gearshape", "Settings") { openMain(.activities) }
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
                .padding(.horizontal, 7).padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: session

    // During a session only what matters, compact: what you're doing and the time left on one
    // line, today's progress on this activity as a bar, and Step away as the main button
    // (you often need it).
    private func sessionCard(_ s: Session, _ cur: (index: Int, end: Date)) -> some View {
        let p = s.phases[cur.index]
        let name = s.planned ?? s.block.replacingOccurrences(of: "_", with: " ")
        let st = ActivityStyle.of(name)
        let total = Double(p.minutes * 60)
        let left = max(0, cur.end.timeIntervalSince(model.now))
        let progress = total > 0 ? 1 - left / total : 1
        let f = Fmt.clock
        let color = p.isBreak ? Color.green : st.color

        return VStack(spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: p.isBreak ? "cup.and.saucer.fill" : st.icon)
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(color)
                Text(name)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if Settings.current.has(.tasks) {
                    Button {
                        openMain(.tasks)
                    } label: {
                        Image(systemName: "checklist")
                            .font(.system(size: 16)).foregroundStyle(Theme.text2)
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Today's tasks")
                    .help("Today's tasks")
                }
                Button {
                    openMain(.activities)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16)).foregroundStyle(Theme.text2)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .help("Settings")
            }

            Button {
                if Settings.current.has(.tasks) { openMain(.tasks) }
            } label: {
                VStack(spacing: 6) {
                    if s.workRounds > 1 || p.isBreak {
                        Text(p.isBreak ? "Break" : "Focus · round \(s.round(of: cur.index))/\(s.workRounds)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(color)
                    }
                    Text(countdown(to: cur.end, from: model.now))
                        .font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(countsDown: true))
                    Text(
                        s.workRounds > 1 || p.isBreak
                            ? "\(p.isBreak ? "Break" : "Focus") ends \(f.string(from: cur.end)) · session ends \(f.string(from: s.end))"
                            : "ends at \(f.string(from: s.end))"
                    )
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!Settings.current.has(.tasks))
            .accessibilityLabel(Settings.current.has(.tasks) ? "Open tasks for \(name)" : "Session timer")

            VStack(spacing: 12) {
                bar(progress, color, height: 3)
                    .animation(.linear(duration: 1), value: progress)
                dailySummary(name)
            }

            VStack(spacing: 10) {
                if Settings.current.has(.away) {
                    Button {
                        model.stepAway()
                    } label: {
                        Label("Step away", systemImage: "figure.walk")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .pill(selected: true)
                    }
                    .buttonStyle(.plain)
                    .help("Locks the screen and pauses the timer. ⌃⌥⌘L")
                }

            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
    }

    private func bar(_ fraction: Double, _ color: Color, height: CGFloat) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.pill)
                Capsule().fill(color).frame(width: g.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }

    private func dailySummary(_ name: String) -> some View {
        let limits = model.limits
        let used = formatDuration(limits.usedToday(name))
        let remaining = limits.secondsLeftToday(name)
        return Text(
            remaining.map { "Today · \(used) spent · \(formatDuration($0)) left" }
                ?? "Today · \(used) spent"
        )
        .font(.system(size: 11)).foregroundStyle(Theme.text2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: free time

    // Only seen if the screen didn't lock: then "I'm back" is right here.
    private func awayCard(_ since: Date) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.walk").font(.system(size: 30)).foregroundStyle(Theme.accent)
            Text("Away since \(Fmt.clock.string(from: since))").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
            Text("The timer is paused and your tasks keep running.").font(.system(size: 12)).foregroundStyle(Theme.text2)
            Button("I'm back") { model.comeBack() }.controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .card(radius: 18)
    }

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
            Button {
                model.endRest()
            } label: {
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
            Text("Choose an activity and a duration. Add optional tools later.")
                .font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            Button {
                openMain(.setup)
            } label: {
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
