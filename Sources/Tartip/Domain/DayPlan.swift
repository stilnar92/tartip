import Foundation

// How a day can go: which activity fits when, where it has to repeat, and where nothing fits.
// A simulation with the app's own rules (weekdays, hours, daily limits, rounds), not a schedule
// the app follows: "What's next?" still asks, and auto-start still picks the one furthest behind.

// A stretch of the day, in minutes since midnight (`end` may pass 1440 when the day crosses it).
struct PlanSlot: Equatable {
    var start: Int
    var end: Int
    var activity: String?      // nil: nothing can start then
    var round = 1              // which time through its limit: above 1 it's a repeat
    var done = false           // already happened: today's sessions, not the plan

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

// Fills from..<to in 5-minute steps. Of what can start, it takes the work whose hours close
// soonest (then list order), work without a limit next, Rest last. `used` is seconds per
// activity in the current round; `repeats`, how many times each already used up its limit.
func planDay(_ s: AppSettings, weekday: Int, from: Int, to: Int,
             used: [String: Int] = [:], repeats: [String: Int] = [:], step: Int = 5) -> [PlanSlot] {
    let planned = s.activities.filter { !$0.name.isEmpty && $0.isPlanned(onWeekday: weekday) }
    var used = used.mapValues { $0 / 60 }   // minutes from here on
    var repeats = repeats
    var slots: [PlanSlot] = []

    var m = from
    while m < to {
        let len = min(step, to - m)
        let clock = m % 1440
        let open = planned.filter { a in
            guard let f = a.fromMinute, let t = a.toMinute, f != t else { return true }
            return inWindow(clock, f, t)
        }
        let limit = { (a: ActivitySetting) in a.limit(onWeekday: weekday) }
        if roundIsUsedUp(open.map { OpenActivity(name: $0.name, limitSeconds: limit($0) * 60,
                                                 usedSeconds: (used[$0.name] ?? 0) * 60) }) {
            for a in planned where limit(a) > 0 && (used[a.name] ?? 0) >= limit(a) { repeats[a.name, default: 0] += 1 }
            used = [:]
        }
        let left = open.filter { limit($0) == 0 || (used[$0.name] ?? 0) < limit($0) }
        // Minutes until its hours close; any time = never.
        let closes = { (a: ActivitySetting) -> Int in
            guard let f = a.fromMinute, let t = a.toMinute, f != t else { return Int.max }
            return (t - clock + 1440) % 1440
        }
        let work = left.filter { !isRest($0.name) }
        let pick = work.filter { limit($0) > 0 }.min { closes($0) < closes($1) }   // min keeps list order on ties
            ?? work.first
            ?? left.first

        if let pick { used[pick.name, default: 0] += len }
        let slot = PlanSlot(start: m, end: m + len, activity: pick?.name, round: pick.map { (repeats[$0.name] ?? 0) + 1 } ?? 1)
        // One block per stretch: repeats of the same activity run together.
        if var last = slots.last, last.activity == slot.activity, last.end == slot.start,
           last.round == slot.round || (last.round > 1 && slot.round > 1) {
            last.end = slot.end
            slots[slots.count - 1] = last
        } else {
            slots.append(slot)
        }
        m += len
    }
    return slots
}

// The day so far: sessions back to back merge (Work, then Work again, is one block),
// and the time between them, from waking up until now, is a "no session" slot.
func pastDay(_ sessions: [PlanSlot], from: Int, until: Int) -> [PlanSlot] {
    var out: [PlanSlot] = []
    var at = from
    for var s in sessions.sorted(by: { $0.start < $1.start }) where s.end > from {
        s.start = max(s.start, from)
        if s.start - at >= 5 { out.append(PlanSlot(start: at, end: s.start, activity: nil, done: true)) }
        if var last = out.last, last.done, last.activity != nil, last.activity == s.activity, s.start - last.end <= 2 {
            last.end = max(last.end, s.end)
            out[out.count - 1] = last
        } else {
            out.append(s)
        }
        at = max(at, s.end)
    }
    if until - at >= 5 { out.append(PlanSlot(start: at, end: until, activity: nil, done: true)) }
    return out
}
