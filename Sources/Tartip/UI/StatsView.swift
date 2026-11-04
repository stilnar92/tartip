import SwiftUI

// MARK: - Stats window

// One day (stepped back up to maxDaysBack), or the last 7, 30 or 90 days up to now.
enum StatsRange: CaseIterable {
    case day, week, month, quarter
    static let maxDaysBack = 89   // today and the 89 days before it: 90 days
    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }
    var title: String { self == .day ? "Day" : "\(days) days" }
}

struct StatsView: View {
    @ObservedObject var model: Model
    @State private var range = StatsRange.day
    @State private var daysBack = 0   // Day: 0 = today, up to StatsRange.maxDaysBack

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: range == .day ? -daysBack : 1 - range.days, to: today) ?? today
        let to = range == .day && daysBack > 0 ? (cal.date(byAdding: .day, value: 1, to: from) ?? today) : Date()
        let isToday = range == .day && daysBack == 0
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
        // Stretches away you said something about sit among the sessions, by time.
        let aways = model.awayRecords.filter { !$0.reasons.isEmpty && $0.start >= from && $0.start < to }
        let timeline: [(t: Date, session: SessionRecord?, away: AwayRecord?)] =
            (recs.map { ($0.start, $0, nil) } + aways.map { ($0.start, nil, $0) }).sorted { $0.t > $1.t }

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                PageTitle(title: "Stats")
                Spacer()
                Picker("", selection: $range) {
                    ForEach(StatsRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }

            if range == .day { dayStepper(from) }

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
                        Text((secs > 0 ? formatDuration(secs) : "–") + (isToday && limit > 0 ? " / \(limitLabel(limit))" : "")).font(.system(size: 12, weight: .semibold))
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

            if !more.awayReasons.isEmpty {
                SectionLabel(text: "Time away went to")
                    .help("What you said you did when you came back. Several answers split a stretch evenly.")
                FlowLayout(spacing: 6) {
                    ForEach(more.awayReasons, id: \.name) { r in
                        Text("\(r.name)  \(formatDuration(r.seconds))").font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(r.name == notSaidAway ? Theme.text2 : Theme.text)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.pill))
                    }
                }
            }

            if !timeline.isEmpty {
                Divider()
                SectionLabel(text: aways.isEmpty ? "Sessions" : "Sessions and time away")
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(timeline.enumerated()), id: \.offset) { _, e in
                            if let r = e.session { sessionRow(r) } else if let a = e.away { awayRow(a) }
                        }
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

    // ‹ Mon, 2 Nov › — one day at a time, back to StatsRange.maxDaysBack.
    private func dayStepper(_ day: Date) -> some View {
        let label = daysBack == 0 ? "Today" : daysBack == 1 ? "Yesterday"
            : day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return HStack(spacing: 12) {
            Button { daysBack += 1 } label: { Image(systemName: "chevron.left") }
                .disabled(daysBack >= StatsRange.maxDaysBack)
                .help("Previous day")
            Text(label).font(.system(size: 13, weight: .semibold)).frame(minWidth: 110)
            Button { daysBack -= 1 } label: { Image(systemName: "chevron.right") }
                .disabled(daysBack == 0)
                .help("Next day")
            if daysBack > 0 {
                Button("Today") { daysBack = 0 }.font(.system(size: 12))
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
    }

    private var timeFormat: DateFormatter {
        range == .day ? Fmt.clock : range == .week ? Fmt.weekdayClock : Fmt.dayClock
    }

    private func awayRow(_ a: AwayRecord) -> some View {
        HStack(spacing: 8) {
            Text(timeFormat.string(from: a.start)).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Image(systemName: "figure.walk").font(.system(size: 11)).foregroundStyle(Theme.text2)
            Text(a.reasons.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            Spacer()
            Text("\(Int(a.end.timeIntervalSince(a.start)) / 60)m").font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func sessionRow(_ r: SessionRecord) -> some View {
        let f = timeFormat
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
