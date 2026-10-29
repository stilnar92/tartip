import Foundation

// Daily limits and activity hours, worked out for one moment.
struct Limits {
    let settings: AppSettings
    let now: Date
    let calendar: Calendar
    private let used: [String: Int]

    // today: today's part of every session, the running one included.
    init(settings: AppSettings, today: [SessionRecord], now: Date, calendar: Calendar = .current) {
        self.settings = settings
        self.now = now
        self.calendar = calendar
        used = secondsByActivity(today)
    }

    func usedToday(_ activity: String) -> Int { used[activity] ?? 0 }

    // Today's limit in minutes (0 = none): the one for today's weekday if it has its own.
    func limitMinutes(_ activity: String) -> Int {
        setting(activity)?.limit(onWeekday: calendar.component(.weekday, from: now)) ?? 0
    }

    // Seconds left today, or nil when the activity has no limit.
    func secondsLeftToday(_ activity: String) -> Int? {
        let limit = limitMinutes(activity)
        guard limit > 0 else { return nil }
        return max(0, limit * 60 - usedToday(activity))
    }

    // Shared by manual starts, Pomodoro, auto-start, and their previews.
    func sessionSeconds(_ activity: String, requested: Int) -> Int {
        guard settings.capSessionsToRemainingTime, let left = secondsLeftToday(activity) else { return requested }
        return min(requested, left)
    }

    func hasTimeLeft(_ activity: String) -> Bool { (secondsLeftToday(activity) ?? 1) > 0 }

    // Activity hours: outside them the activity is greyed out in the picker.
    func isOpen(_ activity: String) -> Bool {
        guard let a = setting(activity), let from = a.fromMinute, let to = a.toMinute, from != to else { return true }
        return inWindow(minuteOfDay(now, calendar: calendar), from, to)
    }

    // "from 12:00" for an activity that's closed right now.
    func opensLabel(_ activity: String) -> String? {
        guard !isOpen(activity), let from = setting(activity)?.fromMinute else { return nil }
        return "from \(clockLabel(from))"
    }

    // Planned for today's weekday (activities without days are planned every day).
    func isToday(_ activity: String) -> Bool { setting(activity)?.isPlanned(on: now, calendar: calendar) ?? true }

    func canStart(_ activity: String) -> Bool { isToday(activity) && isOpen(activity) && hasTimeLeft(activity) }

    // Time for a new round: no work can start now, but some that's planned and open is used up.
    // Never at night, when nothing is asked anyway.
    func needsNewRound(_ activities: [String]) -> Bool {
        guard !settings.isNight(at: now, calendar: calendar) else { return false }
        let open = activities.filter { isToday($0) && isOpen($0) }.map { a in
            OpenActivity(name: a, limitSeconds: limitMinutes(a) * 60, usedSeconds: usedToday(a))
        }
        return roundIsUsedUp(open)
    }

    // What auto-start picks when "What's next?" goes unanswered: of the activities that can
    // start now, the one furthest behind its daily limit (most time left), then ones without
    // a limit, in list order. Rest only if nothing else can start.
    func autoPick(from activities: [String]) -> String? {
        let open = activities.filter(canStart)
        let work = open.filter { $0.lowercased() != "rest" }
        let pool = work.isEmpty ? open : work
        let limited = pool.filter { secondsLeftToday($0) != nil }
        if let best = limited.max(by: { (secondsLeftToday($0) ?? 0) < (secondsLeftToday($1) ?? 0) }) { return best }
        return pool.first
    }

    private func setting(_ activity: String) -> ActivitySetting? { settings.activities.first { $0.name == activity } }
}
