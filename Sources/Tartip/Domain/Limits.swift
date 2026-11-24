import Foundation

// Daily limits and activity hours, worked out for one moment.
struct Limits {
    let settings: AppSettings
    let now: Date
    let calendar: Calendar
    let debts: [CatchUpDebt]
    private let used: [String: Int]

    // today: today's part of every session, the running one included.
    init(settings: AppSettings, today: [SessionRecord], now: Date, calendar: Calendar = .current, debts: [CatchUpDebt] = []) {
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.debts = debts
        used = secondsByActivity(today)
    }

    // The oldest unsettled catch-up owed right now, if any; see CatchUp.swift.
    var owedDebt: CatchUpDebt? { settings.has(.catchUp) ? Tartip.owedDebt(debts, order: settings.activities.map(\.name)) : nil }

    func usedToday(_ activity: String) -> Int { used[activity] ?? 0 }

    // Today's limit in minutes (0 = none): the one for today's weekday if it has its own.
    func limitMinutes(_ activity: String) -> Int {
        settings.has(.scheduling) ? (setting(activity)?.limit(onWeekday: weekday) ?? 0) : 0
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

    // Activity hours (today's own, if today has them): outside them the activity is greyed out in the picker.
    func isOpen(_ activity: String) -> Bool {
        guard settings.has(.scheduling), let windows = setting(activity)?.windows(onWeekday: weekday), !windows.isEmpty else { return true }
        return windows.contains { inWindow(minuteOfDay(now, calendar: calendar), $0.from, $0.to) }
    }

    // "from 12:00" for an activity that's closed right now: whichever window opens soonest.
    func opensLabel(_ activity: String) -> String? {
        guard !isOpen(activity), let windows = setting(activity)?.windows(onWeekday: weekday), !windows.isEmpty else { return nil }
        let m = minuteOfDay(now, calendar: calendar)
        guard let next = windows.min(by: { ($0.from - m + 1440) % 1440 < ($1.from - m + 1440) % 1440 }) else { return nil }
        return "from \(clockLabel(next.from))"
    }

    // Planned for today's weekday (activities without days are planned every day).
    func isToday(_ activity: String) -> Bool { !settings.has(.scheduling) || (setting(activity)?.isPlanned(on: now, calendar: calendar) ?? true) }

    // What the Today list and "What's next?" offer: today's planned activities, plus the one
    // owing a catch-up even if it isn't planned today. Otherwise a debt from yesterday hides
    // the only activity that can start while every other row says "do X first".
    func offered(_ activities: [String]) -> [String] {
        let owed = owedToday
        return activities.filter { isToday($0) || $0 == owed }
    }

    // The activity owing a catch-up, if it can be paid today: it starts at any hour, but a day
    // off (nothing planned) stays quiet, so a debt never brings work into it.
    var owedToday: String? {
        guard let a = owedDebt?.activity, settings.activity(named: a) != nil,
              settings.activities.contains(where: { !$0.name.isEmpty && isToday($0.name) }) else { return nil }
        return a
    }

    // A debt owed by an activity still in the list forces it as the only choice, except for
    // activities allowed during a catch-up: those follow their usual rules. One deleted from
    // Settings since is orphaned (moot, not settled): fall through to the normal rule.
    func canStart(_ activity: String) -> Bool {
        if let debt = owedDebt, settings.activity(named: debt.activity) != nil {
            if activity == debt.activity { return true }
            if !blockedByDebt(activity) { return isToday(activity) && isOpen(activity) && hasTimeLeft(activity) }
            return false
        }
        return isToday(activity) && isOpen(activity) && hasTimeLeft(activity)
    }

    // Not one of the offered `activities` can start (a gap, a day off, every limit reached).
    // One owing a catch-up counts even on a day it isn't planned: it can always start.
    // With no activities at all there's nothing to say: false.
    func nothingCanStart(_ activities: [String]) -> Bool {
        !activities.isEmpty && !offered(activities).contains(where: canStart)
    }

    // Held back by a catch-up another activity owes (allowed-during-catch-up ones never are).
    func blockedByDebt(_ activity: String) -> Bool {
        guard let debt = owedDebt, settings.activity(named: debt.activity) != nil, debt.activity != activity else { return false }
        return setting(activity)?.allowedDuringCatchUp != true
    }

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
        // A catch-up owed is still what gets picked, even with others allowed alongside it.
        if let debt = owedDebt, settings.activity(named: debt.activity) != nil { return debt.activity }
        let open = activities.filter(canStart)
        let work = open.filter { $0.lowercased() != "rest" }
        let pool = work.isEmpty ? open : work
        let limited = pool.filter { secondsLeftToday($0) != nil }
        if let best = limited.max(by: { (secondsLeftToday($0) ?? 0) < (secondsLeftToday($1) ?? 0) }) { return best }
        return pool.first
    }

    private var weekday: Int { calendar.component(.weekday, from: now) }

    private func setting(_ activity: String) -> ActivitySetting? { settings.activities.first { $0.name == activity } }
}
