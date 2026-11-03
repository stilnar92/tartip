import Foundation

// An activity's scheduled window closed with none of it actually done. "Important" means
// catchUpMinutes > 0; activities without it are never tracked here.
// Persisted (like Round) so a debt survives a restart and the day it was missed on, not just
// recomputed from scratch: recomputing alone can't tell "settled by a dedicated catch-up"
// from "happened to log time some other way" (see settledBy on Session/SessionRecord).
struct CatchUpDebt: Codable, Equatable, Identifiable {
    var id = UUID()
    var activity: String
    var day: String          // dayKey of the calendar day the missed window fell on; identity key with activity
    var windowEnd: Date      // the `to` instant that closed it unmet, as of the last recompute —
                             // NOT part of the debt's identity: editing the activity's hours mid-day
                             // (adding/moving a window) updates this in place rather than opening a
                             // second debt for the same (activity, day).
    var catchUpMinutes: Int  // snapshotted at detection time, so editing the setting later doesn't change it
    var settledAt: Date?
    var expired = false      // past its day of grace, unsettled; kept (not removed) so it still shows in Stats
}

// A day's worth of scheduled windows, fully closed by `now` with nothing done in ANY of them.
// One activity can have several windows in a day (e.g. Work 10-12 and 16-18): missing is
// judged per day, not per window — doing it in any one window clears the whole day.
// `records` must include a running session under `planned` (Model.recordsSince already does),
// so a session still in progress, or finished but awaiting its review, is never counted as missed.
func missedWindows(_ s: AppSettings, records: [SessionRecord], now: Date,
                   calendar: Calendar = .current) -> [(activity: String, day: String, windowEnd: Date)] {
    var out: [(activity: String, day: String, windowEnd: Date)] = []
    for a in s.activities where a.catchUpMinutes > 0 {
        guard !a.windows.isEmpty else { continue }
        // Yesterday and today only: anything that closed before that is already past its grace (see expiry below).
        let days = [-1, 0].map { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now))! }
        for dayStart in days {
            guard a.isPlanned(onWeekday: calendar.component(.weekday, from: dayStart)) else { continue }
            let spans = a.windows.map { w -> (start: Date, end: Date) in
                let start = dayStart.addingTimeInterval(Double(w.from) * 60)
                var end = dayStart.addingTimeInterval(Double(w.to) * 60)
                if w.to <= w.from { end = end.addingTimeInterval(86_400) }   // crosses midnight
                return (start, end)
            }
            guard let lastEnd = spans.map(\.end).max(), lastEnd <= now else { continue }   // today's last window not closed yet
            let covered = spans.contains { span in
                Tartip.records(records, from: span.start, to: span.end)
                    .contains { ($0.actual.isEmpty ? [$0.planned ?? otherActivity] : $0.actual).contains(a.name) }
            }
            if !covered { out.append((a.name, dayKey(dayStart), lastEnd)) }
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
