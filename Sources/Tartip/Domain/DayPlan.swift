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
    guard s.nightEnabled, s.nightFrom != s.nightTo else { return (0, 1440) }
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
        guard let f = a.fromMinute, let t = a.toMinute, f != t else { continue }
        for edge in [f, t] {
            for m in [edge, edge + 1440] where m > from && m < to { cuts.insert(m) }
        }
    }
    let edges = cuts.sorted()
    var out: [Period] = []
    for (start, end) in zip(edges, edges.dropFirst()) {
        let names = planned.filter { a in
            guard let f = a.fromMinute, let t = a.toMinute, f != t else { return true }
            return inWindow(start % 1440, f, t)
        }.map(\.name)
        out.append(Period(start: start, end: end, available: names))
    }
    return merged(out)
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
