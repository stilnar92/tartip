import SwiftUI

// The day's activities as one Craft-style list. It is both the overview and the picker:
// click a row to start it. Used in the menu bar panel and in the forced "What's next?" window.
struct TodayList: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock  // hours and limits change as time passes
    // "What's next?" is itself the deliberate choice, so it starts without a warning;
    // the menu bar panel shows one on a block's first start.
    var warnOnStart = true
    @State private var hovered: String?
    @State private var request: StartRequest?  // waiting for "Start" in the warning

    var body: some View {
        let limits = model.limits
        return VStack(alignment: .leading, spacing: 12) {
            lengthBar
            let names = model.todayActivities
            if names.isEmpty && !model.activities.isEmpty {
                Label("Nothing planned for today", systemImage: "calendar")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
            }
            if !names.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(names.enumerated()), id: \.element) { i, a in
                        VStack(alignment: .leading, spacing: 0) {
                            row(a, limits)
                            if Settings.current.has(.tasks), let activity = Settings.current.activity(named: a) {
                                DailyTaskPreview(model: model, clock: clock, activity: activity.id)
                                    .padding(.leading, 46).padding(.trailing, 12).padding(.bottom, 10)
                            }
                        }
                        if i < names.count - 1 { Divider().opacity(0.4).padding(.leading, 44) }
                    }
                }
                .padding(.vertical, 4)
                .card(radius: 14)
            }

            if !names.isEmpty && !names.contains(where: limits.hasTimeLeft) {
                Label("All daily goals done 🎉", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
            } else if Settings.current.has(.scheduling) && model.roundNumber > 1 {
                Label(
                    "Round \(model.roundNumber): nothing else was open, so limits started over",
                    systemImage: "arrow.counterclockwise"
                )
                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
            if Settings.current.has(.scheduling) && !names.isEmpty {
                DayStrip(day: model.today)
            }
            if Settings.current.has(.guidance) && Settings.current.dailyFreeMinutes > 0 { freeTime }
            if Settings.current.has(.away) { away }
        }
        .alert(
            "Start \(request?.activity ?? "")?", isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
            presenting: request
        ) { r in
            Button("Start") {
                Warnings.acknowledge(block: Settings.current.block(for: r.activity))
                model.startActivity(r.activity, minutes: r.minutes, pomodoro: r.pomodoro)
            }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text(Warnings.start(r.activity, minutes: length(r)))
        }
    }

    // A first start (or one after its block changed) asks first; otherwise it starts right away.
    private func tryStart(_ a: String, minutes: Int? = nil, pomodoro: Bool? = nil) {
        if Settings.current.has(.blocking) && warnOnStart && Warnings.needsStartConfirm(block: Settings.current.block(for: a)) {
            request = StartRequest(activity: a, minutes: minutes, pomodoro: pomodoro)
        } else {
            model.startActivity(a, minutes: minutes, pomodoro: pomodoro)
        }
    }

    private func length(_ r: StartRequest) -> Int {
        let s = Settings.current
        let requested = r.pomodoro ?? model.pomodoro ? s.pomodoroPhases().reduce(0) { $0 + $1.minutes } : max(s.minMinutes, r.minutes ?? model.minutes)
        return (model.limits.sessionSeconds(r.activity, requested: requested * 60) + 59) / 60
    }

    // Length for the next start: pills, plus 🍅 for Pomodoro.
    private var lengthBar: some View {
        HStack(spacing: 6) {
            ForEach(Settings.current.sessionLengths, id: \.self) { n in
                let sel = !model.pomodoro && model.minutes == n
                Button {
                    model.pomodoro = false
                    model.minutes = n
                } label: {
                    Text(minutesLabel(n))
                        .font(.system(size: 12, weight: sel ? .semibold : .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .pill(selected: sel)
                }
                .buttonStyle(.plain)
            }
            if Settings.current.has(.pomodoro) {
                Button {
                    model.pomodoro.toggle()
                } label: {
                    Text("🍅").font(.system(size: 12))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .pill(selected: model.pomodoro)
                }
                .buttonStyle(.plain)
                .help("Pomodoro \(Settings.current.pomodoroWork)/\(Settings.current.pomodoroBreak) min × \(Settings.current.pomodoroRounds)")
            }

        }
    }

    // One activity: checkbox-like icon, name, tag on the right; hover shows "Start".
    private func row(_ a: String, _ limits: Limits) -> some View {
        let st = ActivityStyle.of(a)
        let left = limits.secondsLeftToday(a)
        let done = left == 0
        let closed = limits.opensLabel(a)
        let canStart = !done && closed == nil && model.phase.canStart
        let hover = hovered == a && canStart
        return Button {
            tryStart(a)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(done ? Theme.accent : st.color.opacity(0.14))
                    Image(systemName: done ? "checkmark" : st.icon)
                        .font(.system(size: done ? 11 : 12, weight: .semibold))
                        .foregroundStyle(done ? .white : st.color)
                }
                .frame(width: 26, height: 26)
                Text(a)
                    .font(.system(size: 14))
                    .foregroundStyle(canStart ? Theme.text : Theme.text2)
                    .strikethrough(done, color: Theme.text2)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if hover || (!Settings.current.has(.scheduling) && canStart) {
                    Label(
                        "Start \(formatDuration(limits.sessionSeconds(a, requested: (model.pomodoro ? Settings.current.pomodoroPhases().reduce(0) { $0 + $1.minutes } : max(Settings.current.minMinutes, model.minutes)) * 60)))",
                        systemImage: "play.fill"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent))
                } else if let closed {
                    Tag(text: closed)
                } else if done {
                    Tag(text: "done", color: Theme.accent, fill: Theme.accentTint)
                } else if let left {
                    Tag(text: "\(formatDuration(left)) left")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Theme.accentTint.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .onHover { hovered = $0 ? a : (hovered == a ? nil : hovered) }
        // Right-click: start with a specific length.
        .contextMenu {
            ForEach(Settings.current.sessionLengths, id: \.self) { n in
                Button("Start for \(formatDuration(limits.sessionSeconds(a, requested: n * 60)))") { tryStart(a, minutes: n, pomodoro: false) }
            }
            if Settings.current.has(.pomodoro) { Button("Start Pomodoro") { tryStart(a, pomodoro: true) } }
        }
    }

    // Leaving the computer: no length, it lasts until you unlock. Not free time: nothing is
    // spent from the budget, and the computer can't be used meanwhile.
    private var away: some View {
        Button {
            model.stepAway()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk").font(.system(size: 14)).foregroundStyle(Theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Step away").font(.system(size: 14)).foregroundStyle(Theme.text)
                    Text("Locks the screen; your tasks keep running").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
                Spacer()
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(radius: 12)
    }

    // 🍿 Free time: nothing blocked, from the daily budget, never twice in a row.
    private var freeTime: some View {
        HStack(spacing: 8) {
            Text("🍿").font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text("Free time").font(.system(size: 14)).foregroundStyle(model.canRest ? Theme.text : Theme.text2)
                    .help("Nothing blocked")
                Text(model.restTaken ? "after a session" : "\(model.freeLeft / 60)m left")
                    .font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            Spacer()
            ForEach(Settings.current.freeTimeLengths.filter { $0 <= 60 }, id: \.self) { n in
                Button {
                    model.startRest(minutes: n)
                } label: {
                    Text(minutesLabel(n))
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .pill()
                }
                .buttonStyle(.plain)
                .disabled(!model.canRest || model.freeLeft < n * 60)
                .opacity(model.canRest && model.freeLeft >= n * 60 ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .card(radius: 12)
    }
}

struct StartRequest: Identifiable {
    let id = UUID()
    let activity: String
    let minutes: Int?
    let pomodoro: Bool?
}
