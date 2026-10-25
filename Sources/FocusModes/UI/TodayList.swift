import SwiftUI

// The day's activities as one Craft-style list. It is both the overview and the picker:
// click a row to start it. Used in the menu bar panel and in the forced "What's next?" window.
struct TodayList: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock     // hours and limits change as time passes
    @State private var hovered: String?

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
                        row(a, limits)
                        if i < names.count - 1 { Divider().opacity(0.4).padding(.leading, 44) }
                    }
                }
                .padding(.vertical, 4)
                .card(radius: 14)
            }

            if !names.isEmpty && !names.contains(where: limits.hasTimeLeft) {
                Label("All daily goals done 🎉", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
            }
            freeTime
        }
    }

    // Length for the next start: pills, plus 🍅 for Pomodoro.
    private var lengthBar: some View {
        HStack(spacing: 6) {
            ForEach(Settings.current.sessionLengths, id: \.self) { n in
                let sel = !model.pomodoro && model.minutes == n
                Button { model.pomodoro = false; model.minutes = n } label: {
                    Text(minutesLabel(n))
                        .font(.system(size: 12, weight: sel ? .semibold : .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .pill(selected: sel)
                }
                .buttonStyle(.plain)
            }
            Button { model.pomodoro.toggle() } label: {
                Text("🍅").font(.system(size: 12))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .pill(selected: model.pomodoro)
            }
            .buttonStyle(.plain)
            .help("Pomodoro \(Settings.current.pomodoroWork)/\(Settings.current.pomodoroBreak) min × \(Settings.current.pomodoroRounds)")
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
        return Button { model.startActivity(a) } label: {
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
                if hover {
                    Label(model.pomodoro ? "Start 🍅" : "Start \(model.minutes)m", systemImage: "play.fill")
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
                Button("Start for \(minutesLabel(n))") { model.startActivity(a, minutes: n, pomodoro: false) }
            }
            Button("Start Pomodoro") { model.startActivity(a, pomodoro: true) }
        }
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
                Button { model.startRest(minutes: n) } label: {
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
