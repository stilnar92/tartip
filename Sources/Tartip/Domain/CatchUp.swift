import Foundation

// An activity's scheduled window closed with none of it actually done. "Important" means
// catchUpMinutes > 0; activities without it are never tracked here.
// Persisted (like Round) so a debt survives a restart and the day it was missed on, not just
// recomputed from scratch: recomputing alone can't tell "settled by a dedicated catch-up"
// from "happened to log time some other way" (see settledBy on Session/SessionRecord).
struct CatchUpDebt: Codable, Equatable, Identifiable {
    var id = UUID()
    var activity: String
    var day: String          // dayKey of the calendar day the missed window fell on
    var windowEnd: Date      // the exact `to` instant that closed unmet; identity key with (activity, day)
    var catchUpMinutes: Int  // snapshotted at detection time, so editing the setting later doesn't change it
    var settledAt: Date?
    var expired = false      // past its day of grace, unsettled; kept (not removed) so it still shows in Stats
}

// A scheduled window, closed by `now` with nothing done in it. `records` must include a
// running session under `planned` (Model.recordsSince already does), so a session still in
// progress, or finished but awaiting its review, is never counted as missed.
func missedWindows(_ s: AppSettings, records: [SessionRecord], now: Date,
                   calendar: Calendar = .current) -> [(activity: String, day: String, windowEnd: Date)] {
    var out: [(activity: String, day: String, windowEnd: Date)] = []
    for a in s.activities where a.catchUpMinutes > 0 {
        guard let from = a.fromMinute, let to = a.toMinute, from != to else { continue }
        // Yesterday and today only: anything that closed before that is already past its grace (see expiry below).
        let days = [-1, 0].map { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now))! }
        for dayStart in days {
            guard a.isPlanned(onWeekday: calendar.component(.weekday, from: dayStart)) else { continue }
            let windowStart = dayStart.addingTimeInterval(Double(from) * 60)
            var windowEnd = dayStart.addingTimeInterval(Double(to) * 60)
            if to <= from { windowEnd = windowEnd.addingTimeInterval(86_400) }   // crosses midnight
            guard windowEnd <= now else { continue }                            // not closed yet
            let covered = Tartip.records(records, from: windowStart, to: windowEnd)
                .contains { ($0.actual.isEmpty ? [$0.planned ?? otherActivity] : $0.actual).contains(a.name) }
            if !covered { out.append((a.name, dayKey(dayStart), windowEnd)) }
        }
    }
    return out
}

// The oldest unsettled, unexpired debt; ties (same windowEnd) broken by the activities' list order.
func owedDebt(_ debts: [CatchUpDebt], order: [String]) -> CatchUpDebt? {
    debts.filter { $0.settledAt == nil && !$0.expired }.min { a, b in
        if a.windowEnd != b.windowEnd { return a.windowEnd < b.windowEnd }
        return (order.firstIndex(of: a.activity) ?? .max) < (order.firstIndex(of: b.activity) ?? .max)
    }
}
