import SwiftUI
import AppKit

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

// Read top to bottom: one headline (time focused) with the few numbers that qualify it,
// then where that time went, then everything around it (free, away, blocked), then the log.
// Activity bars keep each activity's own color (identity follows the activity everywhere in
// the app); the context charts are one neutral hue, since their bars are ranked, not named.
struct StatsView: View {
    @ObservedObject var model: Model
    @State private var range = StatsRange.day
    @State private var daysBack = 0   // Day: 0 = today, up to StatsRange.maxDaysBack
    @State private var showsAllEntries = false

    private static let entriesShown = 30

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: range == .day ? -daysBack : 1 - range.days, to: today) ?? today
        let to = range == .day && daysBack > 0 ? (cal.date(byAdding: .day, value: 1, to: from) ?? today) : Date()
        let recs = model.recordsSince(from, upTo: to)
        let more = insights(recs, events: model.events.filter { $0.type != "free" } + model.freePieces, away: model.awayRecords, from: from, to: to)
        // Stretches away you said something about sit among the sessions, by time.
        let aways = model.awayRecords.filter { !$0.reasons.isEmpty && $0.start >= from && $0.start < to }
        let timeline: [(t: Date, session: SessionRecord?, away: AwayRecord?)] =
            (recs.map { ($0.start, $0, nil) } + aways.map { ($0.start, nil, $0) }).sorted { $0.t > $1.t }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                PageTitle(title: "Stats")
                Spacer()
                Picker("", selection: $range) {
                    ForEach(StatsRange.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }

            // One sheet on the page background, sections split by hairlines (as on Activities).
            headline(recs, more, from: from)
            Divider()
            activitiesCard(from: from, to: to)
            let debts = catchUpReport(model.catchUpDebts, records: model.recordsSince(from),
                                      fromDay: dayKey(from), toDay: dayKey(to.addingTimeInterval(-1)))
            if !debts.isEmpty || Settings.current.has(.catchUp) {
                Divider()
                catchUpCard(debts)
            }
            Divider()
            aroundCard(more)
            if !timeline.isEmpty {
                Divider()
                logCard(timeline, hasAway: !aways.isEmpty)
            }
        }
        .padding(22)
        .onAppear { model.reloadRecords() }
        .onChange(of: range) { _ in showsAllEntries = false }
        .onChange(of: daysBack) { _ in showsAllEntries = false }
    }

    // MARK: headline

    private func headline(_ recs: [SessionRecord], _ more: Insights, from: Date) -> some View {
        let focused = recs.reduce(0) { $0 + $1.seconds }
        let reviewed = recs.filter { !$0.actual.isEmpty && $0.planned != nil }
        let kept = reviewed.filter(\.asPlanned).count
        return VStack(alignment: .leading, spacing: 10) {
            periodBar(from)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(focused > 0 ? formatDuration(focused) : "0m")
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.text)
                Text("focused").font(.system(size: 15)).foregroundStyle(Theme.text2)
            }
            HStack(spacing: 0) {
                tile("\(recs.count)", "Sessions")
                tile(reviewed.isEmpty ? "–" : "\(kept * 100 / reviewed.count)%", "As planned",
                     help: "Reviewed sessions where what you did was what you picked.")
                tile(more.finished.map { "\($0)%" } ?? "–", "Ran full time",
                     help: "Sessions that ran until their time was up, not ended early or by being away too long.")
                tile(more.pickMedian.map(shortDuration) ?? "–", "To decide",
                     help: "Typical time from \"What's next?\" opening to a start (the median).")
            }
        }
    }

    // "Today ‹ ›" for a day, or the span covered for the longer ranges.
    private func periodBar(_ from: Date) -> some View {
        HStack(spacing: 10) {
            if range == .day {
                Text(daysBack == 0 ? "Today" : daysBack == 1 ? "Yesterday"
                     : from.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if daysBack > 0 {
                    Button("Today") { daysBack = 0 }.font(.system(size: 12))
                }
                stepButton("chevron.left", "Previous day", disabled: daysBack >= StatsRange.maxDaysBack) { daysBack += 1 }
                stepButton("chevron.right", "Next day", disabled: daysBack == 0) { daysBack -= 1 }
            } else {
                Text("\(from.formatted(.dateTime.day().month(.abbreviated))) – today")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func stepButton(_ icon: String, _ help: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.pill))
        }
        .foregroundStyle(disabled ? Theme.text2.opacity(0.4) : Theme.text)
        .disabled(disabled)
        .help(help)
    }

    private func tile(_ value: String, _ label: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.text)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help ?? "")
    }

    // MARK: activities

    // Today, an activity with a daily limit is a meter: how much of the limit is done. Anything
    // else (no limit, a past day, a longer range) is a ranked bar against the busiest activity.
    private func activitiesCard(from: Date, to: Date) -> some View {
        let isToday = range == .day && daysBack == 0
        var byActivity = model.secondsByActivity(since: from, upTo: to)
        for a in model.activities where byActivity[a] == nil { byActivity[a] = 0 }
        let order = model.activities + [otherActivity]
        let rows = byActivity.sorted {
            $0.value != $1.value ? $0.value > $1.value
                : (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99)
        }
        let busiest = max(1, rows.first?.value ?? 1)
        let limits = model.limits
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                cardTitle("Activities")
                Spacer()
                if isToday && rows.contains(where: { limits.limitMinutes($0.key) > 0 }) {
                    Text("bars show the daily limit").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
            }
            ForEach(rows, id: \.key) { name, secs in
                let limit = isToday ? limits.limitMinutes(name) : 0
                let fraction = limit > 0 ? Double(secs) / Double(limit * 60) : Double(secs) / Double(busiest)
                activityRow(name, secs: secs, limit: limit, fraction: fraction)
            }
        }
    }

    private func activityRow(_ name: String, secs: Int, limit: Int, fraction: Double) -> some View {
        let st = ActivityStyle.of(name)
        let met = limit > 0 && secs >= limit * 60
        return HStack(spacing: 12) {
            Image(systemName: st.icon).font(.system(size: 14)).foregroundStyle(st.color).frame(width: 20)
            HStack(spacing: 6) {
                Text(name).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secs > 0 ? Theme.text : Theme.text2)
                    .lineLimit(1)
                // Owed right now: the same "Catch-up Xm" the picker shows.
                if let d = model.catchUpDebts.first(where: { $0.activity == name && $0.settledAt == nil && !$0.expired }) {
                    Tag(text: "owes \(d.catchUpMinutes)m", color: .orange, fill: Color.orange.opacity(0.12))
                        .help("Catch-up still owed for \(d.day)")
                }
            }
            .frame(width: 150, alignment: .leading)
            bar(fraction, st.color)
            HStack(spacing: 4) {
                Text(secs > 0 ? formatDuration(secs) : "–").foregroundStyle(Theme.text)
                if limit > 0 { Text("/ \(limitLabel(limit))").foregroundStyle(Theme.text2) }
                if met { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("limit reached") }
            }
            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
            .lineLimit(1).fixedSize()
            .frame(width: 118, alignment: .trailing)
        }
        .help(limit > 0 ? "\(name): \(formatDuration(secs)) of \(limitLabel(limit)) today" : "\(name): \(formatDuration(secs))")
    }

    // A thin bar on a track of the same hue; anything above zero gets a visible sliver.
    private func bar(_ fraction: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.13))
                if fraction > 0 {
                    Capsule().fill(color).frame(width: max(6, g.size.width * min(1, fraction)))
                }
            }
        }
        .frame(height: 8)
    }

    // MARK: catch-up

    // Days an important activity fell short of its minimum, and what became of each debt.
    private func catchUpCard(_ debts: [CatchUpReport]) -> some View {
        let owed = debts.reduce(0) { $0 + $1.owedMinutes }
        let paid = debts.reduce(0) { $0 + $1.paidMinutes }
        let open = debts.filter { $0.status == .open }
        let missed = debts.filter { $0.status == .missed }
        return VStack(alignment: .leading, spacing: 10) {
            cardTitle("Catch-up")
            if debts.isEmpty {
                Text("Nothing fell short on these days: every important activity met its minimum.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text2)
            } else {
                HStack(spacing: 0) {
                    tile(minutesLabel(owed), "Owed", help: "Short of the daily minimum, added up over \(debts.count) \(debts.count == 1 ? "day" : "days").")
                    tile(minutesLabel(paid), "Paid off", help: "Done in catch-up sessions.")
                    tile(open.isEmpty ? "–" : minutesLabel(open.reduce(0) { $0 + $1.debt.catchUpMinutes }), "Still owed",
                         help: "Comes first at the next \"What's next?\".")
                    tile(missed.isEmpty ? "–" : "\(missed.count)", "Dropped", help: "Not caught up within its extra day.")
                }
                if owed > 0 { bar(Double(paid) / Double(owed), .green).help("\(paid) of \(owed) min paid off") }
                Divider()
                ForEach(Array(debts.prefix(12).enumerated()), id: \.offset) { _, r in debtRow(r) }
            }
        }
    }

    private func debtRow(_ r: CatchUpReport) -> some View {
        let st = ActivityStyle.of(r.debt.activity)
        let day = Fmt.dayKey.date(from: r.debt.day).map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? r.debt.day
        return HStack(spacing: 10) {
            Text(day).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2).frame(width: 74, alignment: .leading)
            Image(systemName: st.icon).font(.system(size: 12)).foregroundStyle(st.color).frame(width: 16)
            Text(r.debt.activity).font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            switch r.status {
            case .paid: Tag(text: "paid", color: .green, fill: Color.green.opacity(0.12))
            case .open: Tag(text: r.paidMinutes > 0 ? "\(r.debt.catchUpMinutes)m left" : "owed", color: .orange, fill: Color.orange.opacity(0.12))
            case .missed: Tag(text: "dropped", color: Theme.red, fill: Theme.redTint)
            }
            minutes(r.owedMinutes)
        }
    }

    // MARK: around the sessions

    private func aroundCard(_ more: Insights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("Around the sessions")
            HStack(spacing: 0) {
                tile(formatDuration(more.free), "Free time")
                tile(formatDuration(more.away), "Away", help: "Time away from the computer in stretches of up to 3 hours; longer ones are sleep.")
                tile("\(more.autoStarted)", "Auto-started", help: "Started by themselves after \"What's next?\" went unanswered.")
                tile("\(more.blocked.reduce(0) { $0 + $1.count })", "Blocked", help: "Apps quit and sites stopped, each once per lock.")
            }
            if !more.awayReasons.isEmpty {
                Divider()
                subTitle("Time away went to", help: "What you said you did when you came back. Several answers split a stretch evenly.")
                let top = max(1, more.awayReasons.map(\.seconds).max() ?? 1)
                ForEach(more.awayReasons, id: \.name) { r in
                    rankedRow(r.name, value: formatDuration(r.seconds), fraction: Double(r.seconds) / Double(top),
                              muted: r.name == notSaidAway)
                }
            }
            if !more.blocked.isEmpty {
                Divider()
                subTitle("Most blocked", help: "Each app or site counts once per lock it was caught in.")
                let top = max(1, more.blocked.first?.count ?? 1)
                ForEach(more.blocked.prefix(6), id: \.name) { b in
                    rankedRow(displayName(b.name), value: "\(b.count)×", fraction: Double(b.count) / Double(top))
                }
            }
        }
    }

    private func rankedRow(_ name: String, value: String, fraction: Double, muted: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(name).font(.system(size: 12)).foregroundStyle(muted ? Theme.text2 : Theme.text)
                .lineLimit(1).truncationMode(.middle).frame(width: 142, alignment: .leading)
            bar(fraction, muted ? Theme.text2 : Theme.accent)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                .lineLimit(1).fixedSize().frame(width: 64, alignment: .trailing)
        }
    }

    // "com.tdesktop.Telegram" → "Telegram"; a site's host stays as it is.
    private func displayName(_ id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: log

    private func logCard(_ timeline: [(t: Date, session: SessionRecord?, away: AwayRecord?)], hasAway: Bool) -> some View {
        let shown = showsAllEntries ? timeline : Array(timeline.prefix(Self.entriesShown))
        return VStack(alignment: .leading, spacing: 8) {
            cardTitle(hasAway ? "Sessions and time away" : "Sessions")
            ForEach(Array(shown.enumerated()), id: \.offset) { i, e in
                if i > 0 { Divider().opacity(0.6) }
                if let r = e.session { sessionRow(r) } else if let a = e.away { awayRow(a) }
            }
            if timeline.count > shown.count {
                Button("Show all \(timeline.count)") { showsAllEntries = true }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                    .padding(.top, 4)
            }
        }
    }

    private var timeFormat: DateFormatter {
        range == .day ? Fmt.clock : range == .week ? Fmt.weekdayClock : Fmt.dayClock
    }

    private func awayRow(_ a: AwayRecord) -> some View {
        HStack(spacing: 10) {
            timeLabel(a.start)
            Image(systemName: "figure.walk").font(.system(size: 12)).foregroundStyle(Theme.text2).frame(width: 16)
            Text(a.reasons.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
            Spacer()
            minutes(Int(a.end.timeIntervalSince(a.start)) / 60)
        }
    }

    private func sessionRow(_ r: SessionRecord) -> some View {
        let planned = r.planned ?? "–"
        let actual = r.actual.isEmpty ? "not reviewed" : r.actual.joined(separator: ", ")
        let name = r.actual.first ?? r.planned ?? otherActivity
        return HStack(spacing: 10) {
            timeLabel(r.start)
            Image(systemName: ActivityStyle.of(name).icon).font(.system(size: 12))
                .foregroundStyle(ActivityStyle.of(name).color).frame(width: 16)
            Text(r.asPlanned ? planned : "\(planned) → \(actual)").font(.system(size: 12)).foregroundStyle(Theme.text).lineLimit(1)
            if !r.asPlanned && !r.actual.isEmpty {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(.orange)
                    .help("Did something other than planned")
            }
            if r.auto == true { Tag(text: "auto", color: .secondary, fill: Theme.pill) }
            if r.ended == "stopped" { Tag(text: "ended early", color: .secondary, fill: Theme.pill) }
            if let n = r.note { Text("· \(n)").font(.system(size: 11)).foregroundStyle(Theme.text2).lineLimit(1) }
            Spacer()
            minutes(r.seconds / 60)
        }
    }

    private func timeLabel(_ d: Date) -> some View {
        Text(timeFormat.string(from: d)).font(.system(size: 11)).monospacedDigit()
            .foregroundStyle(Theme.text2).frame(width: 74, alignment: .leading)
    }

    private func minutes(_ m: Int) -> some View {
        Text("\(m)m").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Theme.text2)
    }

    // MARK: labels

    private func cardTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
    }

    private func subTitle(_ text: String, help: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2).help(help)
    }
}
