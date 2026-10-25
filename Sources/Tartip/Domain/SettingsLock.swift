import Foundation

// Settings lock: a plan made calmly can't be loosened in a weak moment. While it's on,
// stricter changes still go through; looser ones (see `loosenings`) are refused.
struct LockSettings: Codable, Equatable {
    enum Mode: String, Codable { case off, afterChange, hours }
    var mode: Mode = .off
    var hours = 24              // afterChange: how long settings stay locked after you change them
    var from = 21 * 60          // hours: settings can be loosened only from…
    var to = 21 * 60 + 30       // …until (minutes since midnight, may cross midnight)

    // A change starts the lock this long after it, so one sitting can be finished.
    static let grace: TimeInterval = 10 * 60

    // Until when settings are locked at `now`; nil = not locked. `changedAt` is when the
    // current round of changes began (afterChange only).
    func lockedUntil(now: Date, changedAt: Date?, calendar: Calendar = .current) -> Date? {
        switch mode {
        case .off:
            return nil
        case .afterChange:
            guard let c = changedAt else { return nil }
            let start = c.addingTimeInterval(Self.grace), end = start.addingTimeInterval(Double(hours) * 3600)
            return now >= start && now < end ? end : nil
        case .hours:
            // Just switched on: a few minutes to set the hours before they apply.
            if let c = changedAt, now < c.addingTimeInterval(Self.grace) { return nil }
            guard from != to, !inWindow(minuteOfDay(now, calendar: calendar), from, to) else { return nil }
            let today = calendar.date(bySettingHour: from / 60, minute: from % 60, second: 0, of: now) ?? now
            return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
    }

    // When the grace after a change (or after switching the mode) ends, for "locks at 14:32".
    func locksAt(changedAt: Date?, now: Date) -> Date? {
        guard mode != .off, let c = changedAt else { return nil }
        let start = c.addingTimeInterval(Self.grace)
        // Only if it really locks then: at set hours the window may be open by that time.
        return now < start && lockedUntil(now: start, changedAt: c) != nil ? start : nil
    }

    // A change at `now` begins a new round unless one is still running (grace or lock).
    func newRound(now: Date, changedAt: Date?) -> Bool {
        guard mode == .afterChange else { return false }
        guard let c = changedAt else { return true }
        return now >= c.addingTimeInterval(Self.grace + Double(hours) * 3600)
    }
}

// What in `n` is looser than in `o`, in words; empty = the change is as strict or stricter.
func loosenings(from o: AppSettings, to n: AppSettings) -> [String] {
    var out: [String] = []
    // A limit of 0 means no limit, the most time an activity can take.
    let cap = { (m: Int) in m == 0 ? Int.max : m }
    let span = { (from: Int?, to: Int?) -> Int in
        guard let f = from, let t = to, f != t else { return 1440 }
        return (t - f + 1440) % 1440
    }

    for a in o.activities {
        guard let b = n.activities.first(where: { $0.id == a.id }) else { out.append("removing \(a.name)"); continue }
        let oldDays = (1...7).filter(a.isPlanned(onWeekday:)), newDays = (1...7).filter(b.isPlanned(onWeekday:))
        if !Set(oldDays).isSubset(of: Set(newDays)) { out.append("fewer days for \(a.name)") }
        if oldDays.contains(where: { cap(b.limit(onWeekday: $0)) < cap(a.limit(onWeekday: $0)) }) {
            out.append("a lower limit for \(a.name)")
        }
        if span(b.fromMinute, b.toMinute) < span(a.fromMinute, a.toMinute) { out.append("shorter hours for \(a.name)") }
        if b.block != a.block { out.append("\(a.name) locking another block") }
    }

    if n.dailyFreeMinutes > o.dailyFreeMinutes { out.append("more free time") }
    if n.maxRestMinutes > o.maxRestMinutes { out.append("a longer free time stretch") }

    let night = { (s: AppSettings) in s.nightEnabled ? span(s.nightFrom, s.nightTo) : 0 }
    if night(n) < night(o) { out.append(n.nightEnabled ? "a shorter night" : "turning night off") }
    if n.nightBlock != o.nightBlock || n.otherBlock != o.otherBlock { out.append("another night block") }

    let autoWait = { (s: AppSettings) in s.autoStartAfterMinutes == 0 ? Int.max : s.autoStartAfterMinutes }
    if autoWait(n) > autoWait(o) { out.append(n.autoStartAfterMinutes == 0 ? "turning auto-start off" : "a later auto-start") }
    if n.autoStartMinutes < o.autoStartMinutes { out.append("shorter auto-started sessions") }
    if n.minMinutes < o.minMinutes { out.append("a shorter minimum session") }
    if o.pickerFullScreen && !n.pickerFullScreen { out.append("a smaller \"What's next?\"") }

    let lo = o.lock, ln = n.lock
    let weaker: Bool = switch lo.mode {
    case .off: false
    case .afterChange: ln.mode != .afterChange || ln.hours < lo.hours
    case .hours: ln.mode != .hours || (ln.from, ln.to) != (lo.from, lo.to)   // moving the window could open it now
    }
    if weaker { out.append(ln.mode == .off ? "turning the settings lock off" : "a weaker settings lock") }
    return out
}
