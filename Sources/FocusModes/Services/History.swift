import Foundation

// Session history: one JSON line per session in ~/modes/logs/sessions.jsonl.

private func recordEncoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    return e
}

func recordDecoder() -> JSONDecoder {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}

func appendRecord(_ r: SessionRecord) {
    guard let data = try? recordEncoder().encode(r), let line = String(data: data, encoding: .utf8),
          appendText(line + "\n", to: sessionsFile)
    else { return log("error: couldn't save the session to \(sessionsFile.path)") }
}

func loadRecords() -> [SessionRecord] {
    guard let text = try? String(contentsOf: sessionsFile, encoding: .utf8) else { return [] }
    let dec = recordDecoder()
    return text.split(separator: "\n").compactMap { try? dec.decode(SessionRecord.self, from: Data($0.utf8)) }
}
