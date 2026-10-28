import Foundation

// The extra numbers on Stats, each with one definition (also in logs/SCHEMA.md terms).
struct Insights: Equatable {
    var finished: Int?          // % of sessions that ran their full time (of those that say how they ended)
    var autoStarted: Int        // sessions that started by themselves
    var pickMedian: Int?        // typical seconds from "What's next?" to a start
    var free: Int               // seconds of free time used (pieces that have ended)
    var away: Int               // seconds away in stretches of up to 3 h; longer ones are sleep
    var blocked: [Blocked]      // most caught first

    struct Blocked: Equatable { var name: String; var count: Int }
}

let longestAway: TimeInterval = 3 * 3600

func insights(_ records: [SessionRecord], events: [Event], away: [AwayRecord], from: Date, to: Date) -> Insights {
    let ended = records.compactMap(\.ended)
    let picks = records.compactMap(\.pickSeconds).sorted()
    let recent = events.filter { $0.t >= from && $0.t < to }
    var counts: [String: Int] = [:]
    for e in recent where e.type == "blocked" { if let n = e.name { counts[n, default: 0] += 1 } }
    let awaySecs = away.filter { $0.end.timeIntervalSince($0.start) <= longestAway }.reduce(0) { sum, r in
        sum + max(0, Int(min(r.end, to).timeIntervalSince(max(r.start, from))))
    }
    return Insights(
        finished: ended.isEmpty ? nil : ended.filter { $0 == "done" }.count * 100 / ended.count,
        autoStarted: records.filter { $0.auto == true }.count,
        pickMedian: picks.isEmpty ? nil : picks[picks.count / 2],
        free: recent.filter { $0.type == "free" }.compactMap(\.seconds).reduce(0, +),
        away: awaySecs,
        blocked: counts.map { Insights.Blocked(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name })
}
