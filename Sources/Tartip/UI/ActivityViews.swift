import SwiftUI

// MARK: - "What's next?" (forced when nothing runs) and the review after a session

// The same Today list as the panel, in its own window that stays on top.
struct ActivityPickerView: View {
    @ObservedObject var model: Model
    @ObservedObject var clock: Clock

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageTitle(title: "What's next?",
                      subtitle: "Click an activity to start it, or take free time. Nothing is blocked until you choose.")
            // If nobody answers, an activity starts by itself; say which and when.
            if let at = model.autoStartAt, let activity = model.autoStartActivity {
                HStack(spacing: 8) {
                    Image(systemName: "timer").foregroundStyle(Theme.accent)
                    Text("\(activity) starts by itself in \(countdown(to: at, from: clock.now)) for \(Settings.current.autoStartMinutes) min")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentTint))
            }
            TodayList(model: model, clock: clock, warnOnStart: false)
        }
        .padding(24)
        .frame(width: 420)
    }
}

// After a session: the activity list as a checklist with the plan already checked.
// One click on "Save" confirms; tick or untick to change what you actually did.
struct ReviewView: View {
    @ObservedObject var model: Model
    @State private var picked: [String]? = nil

    var body: some View {
        let r = model.review
        let mins = (r?.seconds ?? 0) / 60
        let checked = picked ?? (r?.planned.map { [$0] } ?? [])
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                PageTitle(title: "Session done")
                HStack(spacing: 6) {
                    Tag(text: "\(mins) min", color: Theme.accent, fill: Theme.accentTint)
                    if let planned = r?.planned { Tag(text: "planned: \(planned)") }
                }
                Text("What did you actually do? The plan is checked; change it if needed.")
                    .font(Theme.subtitle).foregroundStyle(Theme.text2)
            }

            VStack(spacing: 0) {
                let names = model.activities
                ForEach(Array(names.enumerated()), id: \.element) { i, a in
                    let on = checked.contains(a)
                    let st = ActivityStyle.of(a)
                    Button {
                        var c = checked
                        if let idx = c.firstIndex(of: a) { c.remove(at: idx) } else { c.append(a) }
                        picked = c
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(on ? Theme.accent : Color.clear)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(on ? Theme.accent : Theme.text2.opacity(0.5), lineWidth: 1.2)
                                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                            }
                            .frame(width: 16, height: 16)
                            Image(systemName: st.icon).font(.system(size: 12)).foregroundStyle(st.color).frame(width: 18)
                            Text(a).font(.system(size: 14)).foregroundStyle(Theme.text)
                            Spacer()
                            if a == r?.planned { Tag(text: "plan") }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < names.count - 1 { Divider().opacity(0.4).padding(.leading, 40) }
                }
            }
            .padding(.vertical, 4)
            .card(radius: 14)

            Button { model.saveReview(actual: checked) } label: {
                Text(checked == (r?.planned.map { [$0] } ?? []) && !checked.isEmpty ? "Yes, as planned" : "Save")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(checked.isEmpty)
            .opacity(checked.isEmpty ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 420)
    }
}
