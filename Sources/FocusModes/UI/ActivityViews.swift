import SwiftUI

// MARK: - "What's next?" (forced when nothing runs) and the review after a session

// The same Today list as the panel, in its own window that stays on top.
struct ActivityPickerView: View {
    @ObservedObject var m: Model
    @ObservedObject var clock: Clock

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's next?").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                Text("Click an activity to start it, or take free time. Nothing is blocked until you choose.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TodayList(m: m, clock: clock)
        }
        .padding(24)
        .frame(width: 420)
    }
}

// After a session: the activity list as a checklist with the plan already checked.
// One click on "Save" confirms; tick or untick to change what you actually did.
struct ReviewView: View {
    @ObservedObject var m: Model
    @State private var picked: [String]? = nil

    var body: some View {
        let r = m.review
        let mins = (r?.seconds ?? 0) / 60
        let checked = picked ?? (r?.planned.map { [$0] } ?? [])
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session done").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Tag(text: "\(mins) min", color: Theme.accent, fill: Theme.accentTint)
                    if let planned = r?.planned { Tag(text: "planned: \(planned)") }
                }
                Text("What did you actually do? The plan is checked; change it if needed.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
            }

            VStack(spacing: 0) {
                let names = m.activities
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

            Button { m.saveReview(actual: checked) } label: {
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
