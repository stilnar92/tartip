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

    // Daily limit in minutes (0 = none).
    func limitMinutes(_ activity: String) -> Int { setting(activity)?.dailyMinutes ?? 0 }

    // Seconds left today, or nil when the activity has no limit.
    func secondsLeftToday(_ activity: String) -> Int? {
        let limit = limitMinutes(activity)
        guard limit > 0 else { return nil }
        return max(0, limit * 60 - usedToday(activity))
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

    func canStart(_ activity: String) -> Bool { isOpen(activity) && hasTimeLeft(activity) }

    private func setting(_ activity: String) -> ActivitySetting? { settings.activities.first { $0.name == activity } }
}
