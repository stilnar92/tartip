import Foundation

struct Phase: Codable, Equatable {
    var isBreak: Bool
    var minutes: Int
}

struct Session: Codable, Equatable {
    var policy = SessionPolicy.legacy
    var block: String
    var phases: [Phase]
    var start: Date
    var planned: String? = nil      // activity picked before the start
    var maxDurationSeconds: Int? = nil // remaining daily allowance at the start
    var paused = 0                  // seconds spent away from the computer, which don't count
    var auto: Bool? = nil           // started by itself (for the record)
    var pickSeconds: Int? = nil     // time "What's next?" was open before the start (for the record)

    var totalMinutes: Int { phases.reduce(0) { $0 + $1.minutes } }
    // Where the timer would have started without the time away: phases and the end follow it.
    var shiftedStart: Date { start.addingTimeInterval(Double(paused)) }
    var end: Date { shiftedStart.addingTimeInterval(Double(min(totalMinutes * 60, maxDurationSeconds ?? totalMinutes * 60))) }
    var workRounds: Int { phases.filter { !$0.isBreak }.count }

    // Current phase index and the moment it ends, or nil when the session is over.
    func current(at now: Date) -> (index: Int, end: Date)? {
        guard now < end else { return nil }
        var t = shiftedStart
        for (i, p) in phases.enumerated() {
            t = t.addingTimeInterval(Double(p.minutes * 60))
            if now < t { return (i, min(t, end)) }
        }
        return nil
    }

    func completedRecord(at end: Date, ended: String) -> SessionRecord? {
        var r = SessionRecord(start: shiftedStart, end: min(end, self.end), mode: block, planned: planned)
        guard r.seconds >= 60 else { return nil }
        r.began = start
        r.plannedMinutes = totalMinutes
        r.rounds = workRounds > 1 ? workRounds : nil
        r.paused = paused > 0 ? paused : nil
        r.ended = ended
        r.auto = auto
        r.pickSeconds = pickSeconds
        return r
    }

    func round(of index: Int) -> Int { phases[0...index].filter { !$0.isBreak }.count }
}

extension Session {
    // Sessions saved before time away existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        policy = try c.decodeIfPresent(SessionPolicy.self, forKey: .policy) ?? .legacy
        block = try c.decode(String.self, forKey: .block)
        phases = try c.decode([Phase].self, forKey: .phases)
        start = try c.decode(Date.self, forKey: .start)
        planned = try c.decodeIfPresent(String.self, forKey: .planned)
        maxDurationSeconds = try c.decodeIfPresent(Int.self, forKey: .maxDurationSeconds)
        paused = try c.decodeIfPresent(Int.self, forKey: .paused) ?? 0
        auto = try c.decodeIfPresent(Bool.self, forKey: .auto)
        pickSeconds = try c.decodeIfPresent(Int.self, forKey: .pickSeconds)
    }
}

// What the app is doing. Night isn't a phase: it comes from the clock, and a session
// that's already running when night starts just finishes.
enum AppPhase: Codable, Equatable {
    case idle
    case picking                            // "What's next?" is open and can't be closed
    case session(Session)
    case freeTime(start: Date, end: Date)   // nothing blocked, from the daily budget
    case reviewing(SessionRecord)           // "What did you actually do?"
    case away(since: Date, paused: Session?) // left the computer: screen locked, nothing counts

    var session: Session? {
        if case .session(let s) = self { return s }
        return nil
    }

    var review: SessionRecord? {
        if case .reviewing(let r) = self { return r }
        return nil
    }

    var awaySince: Date? {
        if case .away(let since, _) = self { return since }
        return nil
    }

    var freeTimeEnd: Date? {
        if case .freeTime(_, let end) = self { return end }
        return nil
    }

    // Something can be started: nothing runs and no question is waiting for an answer.
    var canStart: Bool { self == .idle || self == .picking }
}
