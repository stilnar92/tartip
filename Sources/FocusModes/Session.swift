import Foundation

struct Phase: Codable {
    var isBreak: Bool
    var minutes: Int
}

struct Session: Codable {
    var block: String
    var phases: [Phase]
    var start: Date
    var planned: String? = nil      // activity picked before the start
    var note: String? = nil         // free text when the activity is "Other"

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
