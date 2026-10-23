import Foundation

let otherActivity = "Other"

// One line per session in sessions.jsonl.
struct SessionRecord: Codable, Equatable {
    var start: Date
    var end: Date
    var mode: String
    var planned: String?
    var actual: [String] = []
    var note: String?               // only in old records

    var seconds: Int { max(0, Int(end.timeIntervalSince(start))) }
    var asPlanned: Bool { planned.map { actual == [$0] } ?? false }
}

// The part of each session after `from`: a session that crosses midnight counts
// on each day only for the time it ran that day.
func records(_ all: [SessionRecord], since from: Date) -> [SessionRecord] {
    all.compactMap { r in
        guard r.end > from else { return nil }
        var clipped = r
        clipped.start = max(r.start, from)
        return clipped
    }
}

// Seconds per activity: what was actually done, or what was planned until it's reviewed.
// A session that covered several activities is split evenly; the first gets the remainder.
func secondsByActivity(_ records: [SessionRecord]) -> [String: Int] {
    var out: [String: Int] = [:]
    for r in records {
        let acts = r.actual.isEmpty ? [r.planned ?? otherActivity] : r.actual
        let share = r.seconds / acts.count
        for (i, a) in acts.enumerated() {
            out[a, default: 0] += share + (i == 0 ? r.seconds % acts.count : 0)
        }
    }
    return out
}
