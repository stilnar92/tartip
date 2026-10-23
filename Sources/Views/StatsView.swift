import SwiftUI
import AppKit
import ApplicationServices

// MARK: - Stats window

struct StatsView: View {
    @ObservedObject var m: Model
    @State private var range = 0   // 0 = today, 1 = 7 days

    var body: some View {
        let cal = Calendar.current
        let from = range == 0 ? cal.startOfDay(for: Date()) : cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))!
        var recs = m.records.filter { $0.start >= from }
        // The running session counts live, under its planned activity.
        if let s = m.session, let planned = s.planned {
            recs.append(SessionRecord(start: s.pickedAt ?? s.start, end: min(m.now, s.end), mode: s.block, planned: planned))
        }
        // Split each session's time evenly between what was actually done
        // (or what was planned, until it's reviewed).
        var byActivity: [String: Int] = [:]
        for a in m.activities + [otherActivity] { byActivity[a] = 0 }
        for r in recs {
            let acts = r.actual.isEmpty ? [r.planned ?? otherActivity] : r.actual
            for a in acts { byActivity[a, default: 0] += r.seconds / acts.count }
        }
        // Every activity from the list is shown, busiest first; empty ones stay at the bottom.
        let order = m.activities + [otherActivity]
        let rows = byActivity.sorted {
            $0.value != $1.value ? $0.value > $1.value
                : (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99)
        }
        let total = rows.reduce(0) { $0 + $1.value }
        let reviewed = recs.filter { !$0.actual.isEmpty && $0.planned != nil }
        let kept = reviewed.filter(\.asPlanned).count

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Where the time went").font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Picker("", selection: $range) {
                    Text("Today").tag(0)
                    Text("7 days").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }

            HStack(spacing: 0) {
                summary(formatDuration(total), "Focused")
                summary("\(recs.count)", "Sessions")
                summary(reviewed.isEmpty ? "–" : "\(kept * 100 / reviewed.count)%", "As planned")
            }
            .padding(.vertical, 10)
            .card(radius: 12)

            do {
                VStack(spacing: 10) {
                    ForEach(rows, id: \.key) { name, secs in
                        let st = ActivityStyle.of(name)
                        HStack(spacing: 10) {
                            Image(systemName: st.icon).foregroundStyle(st.color).frame(width: 20)
                            Text(name).font(.system(size: 13, weight: .medium)).frame(width: 100, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(st.color.opacity(0.12))
                                    if secs > 0 {
                                        Capsule().fill(st.color.gradient)
                                            .frame(width: max(6, g.size.width * CGFloat(secs) / CGFloat(max(total, 1))))
                                    }
                                }
                            }
                            .frame(height: 10)
                            Text(secs > 0 ? formatDuration(secs) : "–").font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit().frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }

            if !recs.isEmpty {
                Divider()
                SectionLabel(text: "Sessions")
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(recs.reversed().enumerated()), id: \.offset) { _, r in sessionRow(r) }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear { m.reloadRecords() }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionRow(_ r: SessionRecord) -> some View {
        let f = DateFormatter(); f.dateFormat = range == 0 ? "HH:mm" : "EEE HH:mm"
        let planned = r.planned ?? "–"
        let actual = r.actual.isEmpty ? "not reviewed" : r.actual.joined(separator: ", ")
        return HStack(spacing: 8) {
            Text(f.string(from: r.start)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Image(systemName: r.asPlanned ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: 11)).foregroundStyle(r.asPlanned ? .green : .orange)
            Text(r.asPlanned ? planned : "\(planned) → \(actual)").font(.system(size: 12)).lineLimit(1)
            if let n = r.note { Text("· \(n)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Text("\(r.seconds / 60)m").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
