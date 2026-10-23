import Foundation

struct Phase: Codable, Equatable {
    var isBreak: Bool
    var minutes: Int
}

struct Session: Codable, Equatable {
    var block: String
    var phases: [Phase]
    var start: Date
    var planned: String? = nil      // activity picked before the start

    var totalMinutes: Int { phases.reduce(0) { $0 + $1.minutes } }
    var end: Date { start.addingTimeInterval(Double(totalMinutes * 60)) }
    var workRounds: Int { phases.filter { !$0.isBreak }.count }

    // Current phase index and the moment it ends, or nil when the session is over.
    func current(at now: Date) -> (index: Int, end: Date)? {
        var t = start
        for (i, p) in phases.enumerated() {
            t = t.addingTimeInterval(Double(p.minutes * 60))
            if now < t { return (i, t) }
        }
        return nil
    }

    func round(of index: Int) -> Int { phases[0...index].filter { !$0.isBreak }.count }
}

// What the app is doing. Night isn't a phase: it comes from the clock, and a session
// that's already running when night starts just finishes.
enum AppPhase: Codable, Equatable {
    case idle
    case picking                            // "What's next?" is open and can't be closed
    case session(Session)
    case freeTime(start: Date, end: Date)   // nothing blocked, from the daily budget
    case reviewing(SessionRecord)           // "What did you actually do?"

    var session: Session? {
        if case .session(let s) = self { return s }
        return nil
    }

    var review: SessionRecord? {
        if case .reviewing(let r) = self { return r }
        return nil
    }

    var freeTimeEnd: Date? {
        if case .freeTime(_, let end) = self { return end }
        return nil
    }

    // Something can be started: nothing runs and no question is waiting for an answer.
    var canStart: Bool { self == .idle || self == .picking }
}
