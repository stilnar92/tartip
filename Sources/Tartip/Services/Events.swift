import Foundation

// Facts that aren't sessions, one JSON line each in ~/modes/logs/events.jsonl, for looking back
// and for analysis outside the app (logs/SCHEMA.md says what each field means). Stats reads
// them; limits never do: sessions.jsonl stays the one record of time spent.
struct Event: Codable, Equatable {
    var t: Date                 // when it happened (free time: when it started)
    var type: String            // "free", "blocked" or "round"
    var name: String? = nil     // blocked: the app's bundle id or the site's host
    var block: String? = nil    // blocked: the block that caught it
    var seconds: Int? = nil     // free: time actually used
    var minutes: Int? = nil     // free: the length taken
    var number: Int? = nil      // round: which round of the day began
}

// Called from the main thread and from the Chrome sweep; writes go through one queue.
private let eventQueue = DispatchQueue(label: "events")

func record(_ e: Event) {
    guard let data = try? recordEncoder().encode(e), let line = String(data: data, encoding: .utf8) else { return }
    eventQueue.async { appendText(line + "\n", to: eventsFile) }
}

func loadEvents() -> [Event] {
    guard let text = try? String(contentsOf: eventsFile, encoding: .utf8) else { return [] }
    let dec = recordDecoder()
    return text.split(separator: "\n").compactMap { try? dec.decode(Event.self, from: Data($0.utf8)) }
}

// A blocked app or site counts once per lock: an app relaunched ten times, or a site
// reopened, is still one distraction.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var keys = Set<String>()
    func first(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return keys.insert(key).inserted }
}
private let seenBlocked = Seen()

func recordBlocked(_ name: String, block: String, until: Date) {
    guard seenBlocked.first("\(block)|\(name)|\(Int(until.timeIntervalSince1970))") else { return }
    record(Event(t: Date(), type: "blocked", name: name, block: block))
}

// Only the host is kept, never the page: "https://www.youtube.com/watch?v=…" → "youtube.com".
func siteName(_ url: String) -> String? {
    guard var host = URL(string: url)?.host?.lowercased(), !host.isEmpty else { return nil }
    if host.hasPrefix("www.") { host.removeFirst(4) }
    return host
}
