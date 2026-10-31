import Foundation

// Free time used on `day`, in seconds, not counting the stretch that's running.
struct DayStats: Codable, Equatable {
    var day: String
    var free = 0
}

// Everything the app needs to pick up where it left off after a restart.
struct StoredState: Codable, Equatable {
    var pendingRecords: [SessionRecord]? = nil // durable outbox until history append succeeds
    var phase: AppPhase = .idle
    var minutes = 0                    // length picked for the next start
    var pomodoro = false
    var restTaken = false              // free time can't be taken twice in a row
    var freeUsed = DayStats(day: "")
    var lastExtendedFreeAt: Date? = nil // when a longer (> alwaysFreeMinutes) stretch was last taken
    var opened: OpenedWorkspace?       // what the last start opened, to clean up on the next
    var nightUntil: Date?              // the night lock already sent
    var pickingSince: Date?            // when "What's next?" opened, for auto-start
    var round: Round?                  // today's limits started over (see roundIsUsedUp)
    var activeSince: Date?             // continuously present since; nil when away or not present
}

// Limits count sessions from `since` on, on `day` only.
struct Round: Codable, Equatable {
    var day: String
    var number: Int
    var since: Date
}

// One UserDefaults key holds the whole StoredState.
enum StateStore {
    private static let key = "state"
    // Before the state had one key, each value had its own.
    private static let legacyKeys = ["session", "review", "restEnd", "restStart", "restTaken", "stats",
                                     "minutes", "pomodoro", "opened", "nightUntil", "selected"]

    static func load(from d: UserDefaults = .standard) -> StoredState {
        if let data = d.data(forKey: key) {
            if let s = try? JSONDecoder().decode(StoredState.self, from: data) { return s }
            log("error: couldn't read the saved state, starting fresh")
            return StoredState()
        }
        let s = migrate(from: d, now: Date())
        save(s, to: d)
        legacyKeys.forEach(d.removeObject(forKey:))
        return s
    }

    static func save(_ s: StoredState, to d: UserDefaults = .standard) {
        do { d.set(try JSONEncoder().encode(s), forKey: key) } catch { log("error: couldn't save the state: \(error)") }
    }

    static func migrate(from d: UserDefaults, now: Date) -> StoredState {
        var s = StoredState()
        let dec = JSONDecoder()
        s.minutes = d.integer(forKey: "minutes")
        s.pomodoro = d.bool(forKey: "pomodoro")
        s.restTaken = d.bool(forKey: "restTaken")
        s.nightUntil = d.object(forKey: "nightUntil") as? Date
        if let stats = d.data(forKey: "stats").flatMap({ try? dec.decode(DayStats.self, from: $0) }) { s.freeUsed = stats }
        s.opened = d.data(forKey: "opened").flatMap { try? dec.decode(OpenedWorkspace.self, from: $0) }

        let session = d.data(forKey: "session").flatMap { try? dec.decode(Session.self, from: $0) }
        let review = d.data(forKey: "review").flatMap { try? recordDecoder().decode(SessionRecord.self, from: $0) }
        let restEnd = d.object(forKey: "restEnd") as? Date
        if let session, now < session.end {
            s.phase = .session(session)
        } else if let review {
            s.phase = .reviewing(review)
        } else if let restEnd, now < restEnd {
            // Without restStart, the old tick counter already put the time so far into stats.
            s.phase = .freeTime(start: d.object(forKey: "restStart") as? Date ?? now, end: restEnd)
        }
        return s
    }
}
