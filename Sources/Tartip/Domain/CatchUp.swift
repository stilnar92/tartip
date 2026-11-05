import Foundation

// An activity's scheduled windows closed for the day without catchUpMinutes worth of it done.
// catchUpMinutes does double duty: it's both the minimum minutes a day needs to clear the day
// (no debt), and — when the day falls short — the forced catch-up is only the SHORTFALL
// (catchUpMinutes minus whatever was actually done), never more than catchUpMinutes itself.
// "Important" means catchUpMinutes > 0; activities without it are never tracked here.
// Persisted (like Round) so a debt survives a restart and the day it was missed on, not just
// recomputed from scratch: recomputing alone can't tell "settled by a dedicated catch-up"
// from "happened to log time some other way" (see settledBy on Session/SessionRecord).
struct CatchUpDebt: Codable, Equatable, Identifiable {
    var id = UUID()
    var activity: String
    var day: String          // dayKey of the calendar day the shortfall fell on; identity key with activity
    var windowEnd: Date      // when the day's last window closed, as of the last recompute —
                             // NOT part of the debt's identity: editing the activity's hours mid-day
                             // (adding/moving a window) updates this in place rather than opening a
                             // second debt for the same (activity, day).
    var catchUpMinutes: Int  // the shortfall at detection time (catchUpMinutes setting minus minutes
                             // already done that day), snapshotted so editing the setting or doing
                             // more of the activity afterward doesn't change an open debt
    var settledAt: Date?
    var expired = false      // past its day of grace, unsettled; kept (not removed) so it still shows in Stats
}

// A day's worth of scheduled windows, fully closed by `now`, with less than catchUpMinutes
// worth of the activity actually done across the WHOLE day (summed from the post-session
// review, full session lengths — not clipped to window edges). One activity can have several
// windows in a day (e.g. Work 10-12 and 16-18): the minimum is judged per day, not per window.
// `records` must cover yesterday and today from yesterday's midnight. Call it only when no
// session is open (AppPhase.hasOpenSession): a running session counts just its elapsed part.
// A shortfall under a minute is ignored, so seconds of timing slack never force a catch-up.
func missedWindows(_ s: AppSettings, records: [SessionRecord], now: Date,
                   calendar: Calendar = .current) -> [(activity: String, day: String, windowEnd: Date, shortfall: Int)] {
    var out: [(activity: String, day: String, windowEnd: Date, shortfall: Int)] = []
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
            let dayEnd = dayStart.addingTimeInterval(86_400)
            let doneSeconds = secondsByActivity(Tartip.records(records, from: dayStart, to: dayEnd))[a.name] ?? 0
            let shortfall = (a.catchUpMinutes * 60 - doneSeconds) / 60
            if shortfall > 0 { out.append((a.name, dayKey(dayStart), lastEnd, shortfall)) }
        }
    }
    return out
}

// A session started to pay this debt is over. Run to its end, it settles the debt. Cut short
// (End session, away too long, a forced break), only the time the review gives the activity
// counts: the debt shrinks by that and stays owed until nothing is left, so ending a catch-up
// after a minute doesn't clear it.
func pay(_ debt: inout CatchUpDebt, with r: SessionRecord, at now: Date) {
    guard debt.settledAt == nil else { return }
    if r.ended != "done" {
        debt.catchUpMinutes -= (secondsByActivity([r])[debt.activity] ?? 0) / 60
        guard debt.catchUpMinutes <= 0 else { return }
    }
    debt.settledAt = now
}

// A debt as Stats shows it. catchUpMinutes shrinks as an ended-early catch-up pays part of it,
// so what was owed is rebuilt from the sessions that paid it plus whatever is still open.
struct CatchUpReport: Equatable {
    enum Status: Equatable { case paid, open, missed }
    var debt: CatchUpDebt
    var owedMinutes: Int
    var paidMinutes: Int
    var status: Status
}

func catchUpReport(_ debts: [CatchUpDebt], records: [SessionRecord], fromDay: String, toDay: String) -> [CatchUpReport] {
    debts.filter { $0.day >= fromDay && $0.day <= toDay }.map { d in
        let paid = (secondsByActivity(records.filter { $0.settles == d.id })[d.activity] ?? 0) / 60
        let status: CatchUpReport.Status = d.settledAt != nil ? .paid : d.expired ? .missed : .open
        let owed = status == .paid ? max(paid, d.catchUpMinutes) : paid + max(0, d.catchUpMinutes)
        return CatchUpReport(debt: d, owedMinutes: owed, paidMinutes: status == .paid ? owed : paid, status: status)
    }
    .sorted { $0.debt.day != $1.debt.day ? $0.debt.day > $1.debt.day : $0.debt.activity < $1.debt.activity }
}

// The oldest unsettled, unexpired debt; ties (same windowEnd) broken by the activities' list order.
func owedDebt(_ debts: [CatchUpDebt], order: [String]) -> CatchUpDebt? {
    debts.filter { $0.settledAt == nil && !$0.expired }.min { a, b in
        if a.windowEnd != b.windowEnd { return a.windowEnd < b.windowEnd }
        return (order.firstIndex(of: a.activity) ?? .max) < (order.firstIndex(of: b.activity) ?? .max)
    }
}
