import Foundation

// Session history: one JSON line per session in ~/modes/logs/sessions.jsonl.

func recordEncoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}

func recordDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}

@discardableResult
func appendRecord(_ r: SessionRecord) -> Bool {
    guard let data = try? recordEncoder().encode(r), let line = String(data: data, encoding: .utf8),
          appendText(line + "\n", to: sessionsFile)
    else { log("error: couldn't save the session to \(sessionsFile.path)"); return false }
    return true
}

func loadRecords() -> [SessionRecord] {
    guard let text = try? String(contentsOf: sessionsFile, encoding: .utf8) else { return [] }
    let dec = recordDecoder()
    return text.split(separator: "\n").compactMap { try? dec.decode(SessionRecord.self, from: Data($0.utf8)) }
}

// Time away from the computer, one JSON line per stretch in ~/modes/logs/away.jsonl. Kept apart
// from sessions: it's not an activity, so it never counts toward limits or stats.
struct AwayRecord: Codable, Equatable {
    var start: Date
    var end: Date
}

func appendAway(_ r: AwayRecord) {
    guard let data = try? recordEncoder().encode(r), let line = String(data: data, encoding: .utf8),
          appendText(line + "\n", to: awayFile)
    else { return log("error: couldn't save the time away to \(awayFile.path)") }
}

func loadAway() -> [AwayRecord] {
    guard let text = try? String(contentsOf: awayFile, encoding: .utf8) else { return [] }
    let dec = recordDecoder()
    return text.split(separator: "\n").compactMap { try? dec.decode(AwayRecord.self, from: Data($0.utf8)) }
}
