import SwiftUI

// MARK: - Stats window

struct StatsView: View {
    @ObservedObject var model: Model
    @State private var range = 0   // 0 = today, 1 = yesterday, 2 = 7 days, 3 = 30 days

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let from: Date = {
            switch range {
            case 0: return today
            case 1: return yesterday
            case 2: return cal.date(byAdding: .day, value: -6, to: today) ?? today
            default: return cal.date(byAdding: .day, value: -29, to: today) ?? today
            }
        }()
        let to = range == 1 ? today : Date()
        let recs = model.recordsSince(from, upTo: to)
        var byActivity = model.secondsByActivity(since: from, upTo: to)
        for a in model.activities where byActivity[a] == nil { byActivity[a] = 0 }
        // Every activity from the list is shown, busiest first; empty ones stay at the bottom.
        let order = model.activities + [otherActivity]
        let rows = byActivity.sorted {
            $0.value != $1.value ? $0.value > $1.value
                : (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99)
        }
        let total = rows.reduce(0) { $0 + $1.value }
        let limits = model.limits
        let reviewed = recs.filter { !$0.actual.isEmpty && $0.planned != nil }
        let kept = reviewed.filter(\.asPlanned).count
        let more = insights(recs, events: model.events.filter { $0.type != "free" } + model.freePieces, away: model.awayRecords, from: from, to: to)

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                PageTitle(title: "Stats")
                Spacer()
                Picker("", selection: $range) {
                    Text("Today").tag(0)
                    Text("Yesterday").tag(1)
                    Text("7 days").tag(2)
                    Text("30 days").tag(3)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }

            HStack(spacing: 0) {
                summary(formatDuration(total), "Focused")
                summary("\(recs.count)", "Sessions")
                summary(reviewed.isEmpty ? "–" : "\(kept * 100 / reviewed.count)%", "As planned")
            }
            .padding(.vertical, 10)
            .card(radius: 12)

            HStack(spacing: 0) {
                summary(more.finished.map { "\($0)%" } ?? "–", "Ran full time")
                    .help("Sessions that ran until their time was up, not stopped or ended by being away too long. Counted since this was recorded.")
                summary("\(more.autoStarted)", "Auto-started")
                    .help("Started by themselves after \"What's next?\" went unanswered.")
                summary(more.pickMedian.map(shortDuration) ?? "–", "To decide")
                    .help("Typical time from \"What's next?\" opening to a start (the median).")
                summary(formatDuration(more.free), "Free time")
                summary(formatDuration(more.away), "Away")
                    .help("Time away from the computer in stretches of up to 3 hours; longer ones are sleep.")
            }
            .padding(.vertical, 10)
            .card(radius: 12)

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
                        // Today: show progress against the daily limit, e.g. "45m / 1h".
                        let limit = limits.limitMinutes(name)
                        Text((secs > 0 ? formatDuration(secs) : "–") + (range == 0 && limit > 0 ? " / \(limitLabel(limit))" : "")).font(.system(size: 12, weight: .semibold))
                            .monospacedDigit().frame(width: 92, alignment: .trailing)
                    }
                }
            }

            if !more.blocked.isEmpty {
                SectionLabel(text: "Most blocked")
                    .help("Each app or site counts once per session it was caught in.")
                FlowLayout(spacing: 6) {
                    ForEach(more.blocked.prefix(8), id: \.name) { b in
                        Text("\(b.name)  \(b.count)×").font(.system(size: 11)).monospacedDigit()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.pill))
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
        .onAppear { model.reloadRecords() }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 18, weight: .bold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sessionRow(_ r: SessionRecord) -> some View {
        let f = range <= 1 ? Fmt.clock : range == 2 ? Fmt.weekdayClock : Fmt.dayClock
        let planned = r.planned ?? "–"
        let actual = r.actual.isEmpty ? "not reviewed" : r.actual.joined(separator: ", ")
        return HStack(spacing: 8) {
            Text(f.string(from: r.start)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Image(systemName: r.asPlanned ? "checkmark.circle.fill" : "arrow.triangle.branch")
                .font(.system(size: 11)).foregroundStyle(r.asPlanned ? .green : .orange)
            Text(r.asPlanned ? planned : "\(planned) → \(actual)").font(.system(size: 12)).lineLimit(1)
            if r.auto == true { Tag(text: "auto", color: .secondary, fill: Theme.pill) }
            if r.ended == "stopped" { Tag(text: "stopped", color: .secondary, fill: Theme.pill) }
            if let n = r.note { Text("· \(n)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            Text("\(r.seconds / 60)m").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
