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

    // Nothing but the idle list gets the separate "Today" header: every other state carries
    // its own icon, title and Tasks/Settings inside its own card (see statusCard).
    private var showsDayHeader: Bool {
        model.freeTimeEnd == nil && model.session == nil && !Setup.isPending
            && model.phase.awaySince == nil && !Settings.current.isNight(at: model.now)
    }

    // Every state but the idle list is a single full-width card and nothing else: matching
    // the panel's own background to the card's removes the seam between them, instead of a
    // white card floating on a visibly different grey behind it.
    private var showsSingleCard: Bool { !showsDayHeader }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsDayHeader { header }
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
            if !Settings.current.has(.relaunch) {
                Button("Quit Tartip") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(showsSingleCard ? Theme.card : Theme.bg)
        .environment(\.colorScheme, .light)
        .animation(.snappy(duration: 0.2), value: model.session == nil)
        .animation(.snappy(duration: 0.2), value: model.freeTimeEnd == nil)
        .animation(.snappy(duration: 0.2), value: showLink)
    }

    // MARK: header

    // Only before the idle list: "Today" + date, and the day in three tags. Every other state
    // carries its own icon, title and these same Tasks/Settings buttons inside its own card.
    private var header: some View {
        let sessions = model.recordsSince(Calendar.current.startOfDay(for: model.now)).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("Today").font(Theme.title).foregroundStyle(Theme.text)
                Text(Fmt.dayTitle.string(from: model.now)).font(.system(size: 13)).foregroundStyle(Theme.text2)
                Spacer()
                headerIcon("checklist", "Today's tasks") { openMain(.tasks) }
                headerIcon("gearshape", "Settings") { openMain(.activities) }
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

    // Icon+title row shared by every card (session, free time, away, night): the activity or
    // state's icon and name on the left, Tasks and Settings on the right. `icon` is an SF
    // Symbol name, except 🍿 (no matching symbol), passed through as a literal emoji.
    private func cardHeader(_ icon: String, _ color: Color, _ title: String) -> some View {
        HStack(spacing: 10) {
            if icon == "🍿" {
                Text(icon).font(.system(size: 18))
            } else {
                Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(color)
            }
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            if !Setup.isPending && Settings.current.has(.tasks) { headerIcon("checklist", "Today's tasks") { openMain(.tasks) } }
            headerIcon("gearshape", "Settings") { openMain(.activities) }
        }
    }

    private func headerIcon(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundStyle(Theme.text2)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .help(help)
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


    // MARK: session

    // The template every "something is happening, here's a timer and one action" card follows:
    // icon+title+Tasks/Settings, a big countdown, an "ends at"-style subtitle, a progress bar,
    // a summary line, and one pill button — only those pieces change between states.
    private func sessionCard(_ s: Session, _ cur: (index: Int, end: Date)) -> some View {
        let p = s.phases[cur.index]
        let name = s.planned ?? s.block.replacingOccurrences(of: "_", with: " ")
        let st = ActivityStyle.of(name)
        let total = Double(p.minutes * 60)
        let left = max(0, cur.end.timeIntervalSince(model.now))
        let progress = total > 0 ? 1 - left / total : 1
        let f = Fmt.clock
        let color = p.isBreak ? Color.green : st.color
        let roundLabel = s.workRounds > 1 || p.isBreak ? (p.isBreak ? "Break" : "Focus · round \(s.round(of: cur.index))/\(s.workRounds)") : nil
        let endsLabel = s.workRounds > 1 || p.isBreak
            ? "\(p.isBreak ? "Break" : "Focus") ends \(f.string(from: cur.end)) · session ends \(f.string(from: s.end))"
            : "ends at \(f.string(from: s.end))"

        return VStack(spacing: 16) {
            cardHeader(p.isBreak ? "cup.and.saucer.fill" : st.icon, color, name)
            Button {
                if Settings.current.has(.tasks) { openMain(.tasks) }
            } label: {
                VStack(spacing: 6) {
                    if let roundLabel { Text(roundLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(color) }
                    Text(countdown(to: cur.end, from: model.now))
                        .font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(countsDown: true))
                    Text(endsLabel).font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
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

            if Settings.current.has(.away) {
                Button {
                    model.stepAway()
                } label: {
                    Label("Step away", systemImage: "figure.walk")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .pill(selected: true)
                }
                .buttonStyle(.plain)
                .help("Locks the screen and pauses the timer. ⌃⌥⌘L")
            }
        }
        .padding(16)
        .flatCard()
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

    // MARK: shared status card
    //
    // Same template as sessionCard, for every "nothing to pick, just wait or confirm" state
    // (free time, away, night, first-run setup): icon+title+Tasks/Settings, a big countdown,
    // a subtitle, and one pill button. Only those pieces change between states.
    private func statusCard(
        _ icon: String, _ color: Color, _ title: String, _ subtitle: String,
        readout: String, buttonTitle: String? = nil, action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 16) {
            cardHeader(icon, color, title)
            VStack(spacing: 6) {
                Text(readout)
                    .font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText(countsDown: true))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle).font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .pill(selected: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .flatCard()
    }

    // MARK: free time, away, night, setup

    // Only seen if the screen didn't lock: then "I'm back" is right here.
    private func awayCard(_ since: Date) -> some View {
        let subtitle = model.stepAwayUntil.flatMap { $0 > model.now ? "At least \(minutesLabel(Int($0.timeIntervalSince(model.now)) / 60 + 1)) left" : nil }
            ?? "Your tasks keep running"
        return statusCard(
            "figure.walk", Theme.accent, "Away", subtitle,
            readout: Fmt.clock.string(from: since),
            buttonTitle: "I'm back", action: model.comeBack
        )
    }

    private func freeTimeCard(_ until: Date) -> some View {
        statusCard(
            "🍿", Theme.accent, "Free time", "Nothing blocked · \(model.freeLeft / 60)m left today",
            readout: countdown(to: until, from: model.now),
            buttonTitle: "Back to work", action: model.endRest
        )
    }

    // MARK: first-run setup

    // Nothing can start before setup: the panel only leads to Get started.
    private var setupCard: some View {
        statusCard(
            "sparkles", Theme.accent, "Let's set you up", "Choose an activity and a duration. Add optional tools later.",
            readout: "👋",
            buttonTitle: "Get started", action: { openMain(.setup) }
        )
    }

    // MARK: night

    private var nightCard: some View {
        statusCard(
            "moon.stars.fill", .purple, "Time to sleep", "Nothing to do until morning",
            readout: clockLabel(Settings.current.nightTo)
        )
    }
}
