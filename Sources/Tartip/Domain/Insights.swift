import Foundation

// The extra numbers on Stats, each with one definition (also in logs/SCHEMA.md terms).
struct Insights: Equatable {
    var finished: Int?          // % of sessions that ran their full time (of those that say how they ended)
    var autoStarted: Int        // sessions that started by themselves
    var pickMedian: Int?        // typical seconds from "What's next?" to a start
    var free: Int               // seconds of free time used (pieces that have ended)
    var away: Int               // seconds away in stretches of up to 3 h; longer ones are sleep
    var blocked: [Blocked]      // most caught first
    var awayReasons: [AwayReason] = []  // what the time away went to, longest first

    struct Blocked: Equatable { var name: String; var count: Int }
    struct AwayReason: Equatable { var name: String; var seconds: Int }
}

let longestAway: TimeInterval = 3 * 3600
let notSaidAway = "Not said"

func insights(_ records: [SessionRecord], events: [Event], away: [AwayRecord], from: Date, to: Date) -> Insights {
    let ended = records.compactMap(\.ended)
    let picks = records.compactMap(\.pickSeconds).sorted()
    let recent = events.filter { $0.t >= from && $0.t < to }
    var counts: [String: Int] = [:]
    for e in recent where e.type == "blocked" { if let n = e.name { counts[n, default: 0] += 1 } }
    let stretches = away.filter { $0.end.timeIntervalSince($0.start) <= longestAway }
        .map { (record: $0, seconds: max(0, Int(min($0.end, to).timeIntervalSince(max($0.start, from))))) }
        .filter { $0.seconds > 0 }
    let awaySecs = stretches.reduce(0) { $0 + $1.seconds }
    // Several answers split the stretch evenly, as several activities split a session.
    var said: [String: Int] = [:]
    for (r, secs) in stretches {
        let names = r.reasons
        for (i, n) in names.enumerated() { said[n, default: 0] += secs / names.count + (i == 0 ? secs % names.count : 0) }
    }
    // "Not said" only once something was: before asking was on, every stretch is unexplained.
    let notSaid = awaySecs - said.values.reduce(0, +)
    let reasons = said.map { Insights.AwayReason(name: $0.key, seconds: $0.value) }
        .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
        + (said.isEmpty || notSaid <= 0 ? [] : [Insights.AwayReason(name: notSaidAway, seconds: notSaid)])
    return Insights(
        finished: ended.isEmpty ? nil : ended.filter { $0 == "done" }.count * 100 / ended.count,
        autoStarted: records.filter { $0.auto == true }.count,
        pickMedian: picks.isEmpty ? nil : picks[picks.count / 2],
        free: recent.filter { $0.type == "free" }.compactMap(\.seconds).reduce(0, +),
        away: awaySecs,
        blocked: counts.map { Insights.Blocked(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name },
        awayReasons: reasons)
}
