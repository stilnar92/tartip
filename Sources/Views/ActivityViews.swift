import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Activity picker (before) and review (after)

struct ActivityChip: View {
    let name: String
    let selected: Bool
    var detail: String? = nil      // e.g. "35m left"
    let action: () -> Void

    var body: some View {
        let st = ActivityStyle.of(name)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: st.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? .white : st.color)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? AnyShapeStyle(st.color.gradient) : AnyShapeStyle(st.color.opacity(0.15))))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 13, weight: selected ? .semibold : .medium)).lineLimit(1)
                    if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(st.color) }
            }
            .padding(8)
            .card(selected ? st.color : nil, radius: 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ActivityPickerView: View {
    @ObservedObject var m: Model
    @State private var minutes: Int? = nil

    // Pomodoro (several rounds) keeps its own timing; no duration row then.
    private var showsDuration: Bool { (m.pendingStart?.phases.count ?? 1) == 1 }
    private var chosen: Int { minutes ?? defaultMinutes }

    var body: some View {
        let auto = m.pendingStart?.auto ?? true
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's next?").font(.system(size: 18, weight: .bold, design: .rounded))
                Text(auto ? "Pick an activity (its block starts right away) or take free time."
                          : (showsDuration ? "Pick how long and what, then it starts" : "Pick one to start · \(m.pendingLabel)"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if showsDuration {
                HStack(spacing: 6) {
                    ForEach(durationOptions, id: \.self) { n in
                        let sel = chosen == n
                        Button { minutes = n } label: {
                            Text(n == 60 ? "1 h" : "\(n) min")
                                .font(.system(size: 12, weight: sel ? .semibold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .foregroundStyle(sel ? Color.white : Color.primary)
                                .background(Capsule().fill(sel ? AnyShapeStyle(Color.indigo.gradient) : AnyShapeStyle(.quaternary.opacity(0.6))))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            let available = m.availableActivities
            if available.isEmpty {
                Label("All daily goals done 🎉 Take free time or call it a day.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.green)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(available, id: \.self) { a in
                    ActivityChip(name: a, selected: false,
                                 detail: m.secondsLeftToday(a).map { "\(formatDuration($0)) left today" }) {
                        m.choosePlan(a, note: nil, minutes: chosen)
                    }
                }
            }
            Divider()
            FreeTimeRow(m: m)

            if !auto {
                Button("Cancel") { m.cancelPick() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

}

struct ReviewView: View {
    @ObservedObject var m: Model
    @State private var picked: [String] = []

    var body: some View {
        let r = m.review
        let mins = (r?.seconds ?? 0) / 60
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session done · \(mins) min").font(.system(size: 18, weight: .bold, design: .rounded))
                Text("What did you actually do?").font(.system(size: 12)).foregroundStyle(.secondary)
            }

            if let planned = r?.planned {
                let st = ActivityStyle.of(planned)
                Button { m.saveReview(actual: [planned], note: r?.note) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Yes, \(planned)\(r?.note.map { " · \($0)" } ?? "")").lineLimit(1)
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(st.color.gradient))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                SectionLabel(text: "Or something else / more")
            } else {
                SectionLabel(text: "Pick all that apply")
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(m.activities, id: \.self) { a in
                    ActivityChip(name: a, selected: picked.contains(a)) {
                        if let i = picked.firstIndex(of: a) { picked.remove(at: i) } else { picked.append(a) }
                    }
                }
            }
            Button(action: save) {
                Text("Save").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .card(radius: 10).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(picked.isEmpty)
            .opacity(picked.isEmpty ? 0.4 : 1)
        }
        .padding(22)
        .frame(width: 400)
    }

    private func save() { m.saveReview(actual: picked, note: nil) }
}
