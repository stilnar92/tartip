import Foundation

// The day as periods: it's cut wherever an activity's hours start or end, and each period
// lists what can be picked then. Not a schedule: within a period you choose freely.

// A stretch of what happened today, in minutes since midnight (`end` may pass 1440 when
// the day crosses it).
struct PlanSlot: Equatable {
    var start: Int
    var end: Int
    var activity: String?      // nil: no session ran then
    var away = false           // away from the computer (no activity)
    var free = false           // free time (no activity)

    var minutes: Int { end - start }
}

func isRest(_ activity: String) -> Bool { activity.lowercased() == "rest" }

// What one activity has at a moment when it's planned and open.
struct OpenActivity {
    var name: String
    var limitSeconds: Int      // 0 = no limit
    var usedSeconds: Int
}

// A new round starts when no work can start, yet some is open with its limit used up:
// limits count from zero again, so a gap in the day or its end still has something to do.
// Work without a limit can always start, so it never needs one. Rest doesn't count.
func roundIsUsedUp(_ open: [OpenActivity]) -> Bool {
    let work = open.filter { !isRest($0.name) }
    return !work.isEmpty && work.allSatisfy { $0.limitSeconds > 0 && $0.usedSeconds >= $0.limitSeconds }
}

// The waking day: from the end of the night to its start, or the whole day with night off.
func wakingHours(_ s: AppSettings) -> (from: Int, to: Int) {
    guard s.has(.night), s.nightEnabled, s.nightFrom != s.nightTo else { return (0, 1440) }
    return (s.nightTo, s.nightTo < s.nightFrom ? s.nightFrom : s.nightFrom + 1440)
}

// A stretch of the day when the same activities can be picked.
struct Period: Equatable {
    var start: Int
    var end: Int
    var available: [String]    // in list order; empty: nothing can start

    var minutes: Int { end - start }
}

// from..<to cut where any planned activity's hours start or end. Hours may cross midnight
// and `to` may pass 1440. Neighbours with the same activities are one period.
func availability(_ s: AppSettings, weekday: Int, from: Int, to: Int) -> [Period] {
    let planned = s.activities.filter { !$0.name.isEmpty && $0.isPlanned(onWeekday: weekday) }
    var cuts = Set([from, to])
    for a in planned {
        for w in a.windows {
            for edge in [w.from, w.to] {
                for m in [edge, edge + 1440] where m > from && m < to { cuts.insert(m) }
            }
        }
    }
    let edges = cuts.sorted()
    var out: [Period] = []
    for (start, end) in zip(edges, edges.dropFirst()) {
        let names = planned.filter { a in
            a.windows.isEmpty || a.windows.contains { inWindow(start % 1440, $0.from, $0.to) }
        }.map(\.name)
        out.append(Period(start: start, end: end, available: names))
    }
    return merged(out)
}

// Activities planned today whose daily limit asks for more than their own windows can fit in
// a day — e.g. a 2h limit squeezed into a single 1h window. Checked per activity, against its
// own windows only: an activity with windows spread across the day is fine as long as their
// combined length covers its limit, even if any one window alone falls short.
func overcommittedActivities(_ s: AppSettings, weekday: Int) -> [String] {
    s.activities.filter { a in
        guard !a.name.isEmpty, a.isPlanned(onWeekday: weekday), a.hasSchedule else { return false }
        let limit = a.limit(onWeekday: weekday)
        guard limit > 0 else { return false }
        let span = a.windows.reduce(0) { $0 + (($1.to - $1.from + 1440) % 1440) }
        return limit > span
    }.map(\.name)
}

// Activities sharing a period whose daily limits can't all fit there — even allowing each
// activity to use every minute of its OTHER windows first. Real, unavoidable overcommitment:
// no way to arrange the day fills everyone's limit, not just "this period looks crowded."
// Midnight-crossing windows are split at midnight into same-day pieces for this analysis.
func overcommittedPeriods(_ s: AppSettings, weekday: Int) -> [String] {
    struct Span { var start: Int; var end: Int }
    let planned = s.activities.filter { !$0.name.isEmpty && $0.isPlanned(onWeekday: weekday) && $0.hasSchedule && $0.limit(onWeekday: weekday) > 0 }
    guard !planned.isEmpty else { return [] }

    // Each activity's windows, split at midnight into same-day [0, 1440) pieces.
    var spans: [String: [Span]] = [:]
    for a in planned {
        spans[a.name] = a.windows.flatMap { w -> [Span] in
            if w.from < w.to { return [Span(start: w.from, end: w.to)] }
            return [Span(start: w.from, end: 1440), Span(start: 0, end: w.to)]
        }
    }
    let totalSpan = { (name: String) in spans[name]?.reduce(0) { $0 + ($1.end - $1.start) } ?? 0 }

    // Cut the day wherever any activity's spans start or end (same rule as availability()).
    var cuts = Set([0, 1440])
    for a in planned { for sp in spans[a.name] ?? [] { cuts.insert(sp.start); cuts.insert(sp.end) } }
    let edges = cuts.sorted()

    var out: Set<String> = []
    for (start, end) in zip(edges, edges.dropFirst()) {
        let here = planned.filter { a in (spans[a.name] ?? []).contains { $0.start <= start && start < $0.end } }
        guard !here.isEmpty else { continue }
        // Minutes this activity needs HERE even if every minute of its other windows is used first.
        let required = here.reduce(0) { sum, a in
            let elsewhere = totalSpan(a.name) - (end - start)
            return sum + max(0, a.limit(onWeekday: weekday) - elsewhere)
        }
        if required > end - start { out.formUnion(here.map(\.name)) }
    }
    return out.sorted()
}

// Neighbours with the same activities become one period.
func merged(_ periods: [Period]) -> [Period] {
    var out: [Period] = []
    for p in periods {
        if var last = out.last, last.available == p.available, last.end == p.start {
            last.end = p.end
            out[out.count - 1] = last
        } else {
            out.append(p)
        }
    }
    return out
}

// The day so far: sessions back to back merge (Work, then Work again, is one block),
// and the time between them, from waking up until now, is a "no session" slot.
func pastDay(_ sessions: [PlanSlot], from: Int, until: Int) -> [PlanSlot] {
    var out: [PlanSlot] = []
    var at = from
    for var s in sessions.sorted(by: { $0.start < $1.start }) where s.end > max(from, at) {
        s.start = max(s.start, from, at)   // overlaps (a session paused while away) go to the earlier one
        if s.start - at >= 5 { out.append(PlanSlot(start: at, end: s.start, activity: nil)) }
        if var last = out.last, last.activity != nil, last.activity == s.activity, last.away == s.away, last.free == s.free, s.start - last.end <= 2 {
            last.end = max(last.end, s.end)
            out[out.count - 1] = last
        } else {
            out.append(s)
        }
        at = max(at, s.end)
    }
    if until - at >= 5 { out.append(PlanSlot(start: at, end: until, activity: nil)) }
    return out
}
