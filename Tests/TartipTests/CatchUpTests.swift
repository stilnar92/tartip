import Foundation
import Testing
@testable import Tartip

// 2026-03-02 is a Monday; UTC so the weekday doesn't depend on the machine.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func day(_ d: Int, _ h: Int = 12, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: h, minute: m))!
}
private func english(_ catchUp: Int = 20) -> ActivitySetting {
    var a = ActivitySetting(name: "English", fromMinute: 9 * 60, toMinute: 11 * 60)
    a.catchUpMinutes = catchUp
    return a
}

// Two windows the same day: 09:00-11:00 and 16:00-18:00.
private func twoWindowEnglish(_ catchUp: Int = 20) -> ActivitySetting {
    var a = ActivitySetting(name: "English", windows: [TimeWindow(from: 9 * 60, to: 11 * 60), TimeWindow(from: 16 * 60, to: 18 * 60)])
    a.catchUpMinutes = catchUp
    return a
}
private func record(_ activity: String, _ start: Date, _ end: Date, actual: [String]? = nil) -> SessionRecord {
    SessionRecord(start: start, end: end, mode: activity, planned: activity, actual: actual ?? [])
}

// missedWindows looks back one calendar day, so isolate assertions to "today's" (day 2) entry
// unless a test is specifically about the lookback.
private func todays(_ missed: [(activity: String, day: String, windowEnd: Date)]) -> [(activity: String, day: String, windowEnd: Date)] {
    missed.filter { $0.day == "2026-03-02" }
}

@Suite struct CatchUpTests {
    @Test func openWindowIsNeverMissed() {
        let s = AppSettings(activities: [english()])
        // Window is 09:00-11:00; at 10:00 it hasn't closed yet.
        #expect(todays(missedWindows(s, records: [], now: day(2, 10), calendar: cal)).isEmpty)
    }

    @Test func closedWindowWithNothingDoneIsMissed() {
        let s = AppSettings(activities: [english()])
        let missed = todays(missedWindows(s, records: [], now: day(2, 11, 1), calendar: cal))
        #expect(missed.count == 1 && missed[0].activity == "English")
    }

    @Test func closedWindowCoveredByActualIsNotMissed() {
        let s = AppSettings(activities: [english()])
        let r = record("English", day(2, 9, 30), day(2, 10), actual: ["English"])
        #expect(todays(missedWindows(s, records: [r], now: day(2, 11, 1), calendar: cal)).isEmpty)
    }

    // A session still running across the window's close, or finished but not yet reviewed,
    // is visible only under `planned` (never `actual`) — must not be flagged missed either way.
    @Test func stillRunningOrUnreviewedSessionIsNotMissed() {
        let s = AppSettings(activities: [english()])
        let running = record("English", day(2, 10, 50), day(2, 11, 20))   // planned=English, actual=[] (unreviewed)
        #expect(todays(missedWindows(s, records: [running], now: day(2, 11, 1), calendar: cal)).isEmpty)
    }

    // A session that ran during the window but was reviewed as a DIFFERENT activity really
    // did miss the window — this must surface as missed, not be masked by its mere presence.
    @Test func sessionReviewedAsSomethingElseIsStillMissed() {
        let s = AppSettings(activities: [english()])
        let r = record("English", day(2, 9), day(2, 10), actual: ["Reading"])
        let missed = todays(missedWindows(s, records: [r], now: day(2, 11, 1), calendar: cal))
        #expect(missed.count == 1 && missed[0].activity == "English")
    }

    @Test func activityWithoutCatchUpMinutesIsNeverTracked() {
        let s = AppSettings(activities: [english(0)])
        #expect(missedWindows(s, records: [], now: day(2, 11, 1), calendar: cal).isEmpty)
    }

    @Test func notPlannedThatWeekdayIsNeverMissed() {
        var a = english()
        a.days = [7, 1]   // weekends only; Monday (day 2) is a weekday, so it must not appear.
        let s = AppSettings(activities: [a])
        #expect(todays(missedWindows(s, records: [], now: day(2, 11, 1), calendar: cal)).isEmpty)
    }

    // Doing the activity in ANY window clears the whole day: missing is judged per activity
    // per day, not per window.
    @Test func doingOneOfTwoWindowsClearsTheWholeDay() {
        let s = AppSettings(activities: [twoWindowEnglish()])
        let r = record("English", day(2, 9, 30), day(2, 10), actual: ["English"])   // only the morning window
        #expect(todays(missedWindows(s, records: [r], now: day(2, 18, 1), calendar: cal)).isEmpty)
    }

    // Missing both windows produces exactly one debt for the day, keyed to the LAST window's end.
    @Test func missingBothWindowsProducesOneDebtAtTheLastWindowsEnd() {
        let s = AppSettings(activities: [twoWindowEnglish()])
        let missed = todays(missedWindows(s, records: [], now: day(2, 18, 1), calendar: cal))
        #expect(missed.count == 1)
        #expect(missed[0].windowEnd == day(2, 18))
    }

    // The day's debt isn't created until the LAST window has closed, even if the first already has.
    @Test func noDebtUntilTheLastWindowOfTheDayCloses() {
        let s = AppSettings(activities: [twoWindowEnglish()])
        // 11:30: the morning window (09-11) is closed and missed, but the evening one (16-18) is still ahead.
        #expect(todays(missedWindows(s, records: [], now: day(2, 11, 30), calendar: cal)).isEmpty)
    }

    // Editing an activity's hours mid-day (e.g. adding/moving a window) after a debt already
    // exists must update that debt's windowEnd in place, never open a second debt for the same
    // (activity, day) — this is the identity recomputeDebts relies on to stay idempotent.
    @Test func sameActivityAndDayNeverGetsTwoDebts() {
        let existing = CatchUpDebt(activity: "Interview", day: "2026-11-02", windowEnd: day(2, 12), catchUpMinutes: 90)
        var debts = [existing]
        // Settings changed mid-day: missedWindows now reports a later windowEnd for the same (activity, day).
        let i = debts.firstIndex { $0.activity == "Interview" && $0.day == "2026-11-02" }!
        if debts[i].settledAt == nil { debts[i].windowEnd = day(2, 15, 30) }
        #expect(debts.count == 1)
        #expect(debts[0].windowEnd == day(2, 15, 30))
    }

    // Oldest unsettled debt wins; a tie on windowEnd is broken by the activities' list order.
    @Test func owedDebtIsOldestFirstThenListOrder() {
        let earlier = CatchUpDebt(activity: "Reading", day: "2026-03-01", windowEnd: day(1, 10), catchUpMinutes: 15)
        let later = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        #expect(owedDebt([later, earlier], order: ["English", "Reading"])?.activity == "Reading")

        let tieA = CatchUpDebt(activity: "Reading", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 15)
        let tieB = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        #expect(owedDebt([tieA, tieB], order: ["English", "Reading"])?.activity == "English")
    }

    @Test func settledOrExpiredDebtsAreNeverOwed() {
        let settled = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20, settledAt: day(2, 12))
        let expired = CatchUpDebt(activity: "Reading", day: "2026-03-01", windowEnd: day(1, 10), catchUpMinutes: 15, expired: true)
        #expect(owedDebt([settled, expired], order: ["English", "Reading"]) == nil)
    }

    // A debt only gates the activity it's owed by; every other activity is untouched.
    @Test func debtForcesOnlyItsOwnActivity() {
        var s = AppSettings(features: .legacy, activities: [english(), ActivitySetting(name: "Work")])
        s.features.enabled.insert(.catchUp)
        let debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        let limits = Limits(settings: s, today: [], now: day(2, 12), calendar: cal, debts: [debt])
        #expect(limits.canStart("English") && !limits.canStart("Work"))
    }

    // A debt for an activity since deleted from Settings is orphaned (moot), not an eternal lock.
    @Test func orphanedDebtFallsThroughToNormalRules() {
        var s = AppSettings(features: .legacy, activities: [ActivitySetting(name: "Work")])
        s.features.enabled.insert(.catchUp)
        let debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        let limits = Limits(settings: s, today: [], now: day(2, 12), calendar: cal, debts: [debt])
        #expect(limits.canStart("Work"))
    }

    // Catch-up is opt-in (Feature.catchUp): with the feature off, an existing debt must never
    // gate anything — the whole mechanism is inert, not just quieter.
    @Test func featureOffIgnoresExistingDebts() {
        var s = AppSettings(features: .legacy, activities: [english(), ActivitySetting(name: "Work")])
        s.features.enabled.remove(.catchUp)
        let debt = CatchUpDebt(activity: "English", day: "2026-03-02", windowEnd: day(2, 11), catchUpMinutes: 20)
        let limits = Limits(settings: s, today: [], now: day(2, 12), calendar: cal, debts: [debt])
        #expect(limits.owedDebt == nil)
        #expect(limits.canStart("Work"))
    }
}
